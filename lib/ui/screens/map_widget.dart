import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class DermatogistsMapWidget extends StatefulWidget {
  final String initialDisease;
  final geo.Position? currentPosition;
  const DermatogistsMapWidget(
      {super.key,
      required this.initialDisease,
      required this.currentPosition});

  @override
  DermatogistsMapWidgetState createState() => DermatogistsMapWidgetState();
}

class DermatogistsMapWidgetState extends State<DermatogistsMapWidget>
    with AutomaticKeepAliveClientMixin {
  // Raggio iniziale
  static const double _initialRadiusKm = 100.0;
  static const double _boundsPaddingFactor = 0.5;
  static const double _initialZoom = 9.0;

  // Timeout
  static const Duration _networkTimeout = Duration(seconds: 45);

  // Chiave (shared_preferences) persistenza dati cache
  static const String _centersCachePrefix = 'centers_cache_';

  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;
  List<dynamic> _suggestions = [];
  Timer? _debounce;

  String _selectedDisease = 'Dermatite Atopica';
  List<dynamic> _centers = [];
  List<dynamic> _visibleCenters = [];
  bool _isLoadingCenters = false;
  bool _mapReady = false;
  final Map<String, List<dynamic>> _centersCache = {};

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _selectedDisease = widget.initialDisease;
    _loadPersistedCentersThenFetch();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.currentPosition == null) {
        _showPositionWarning();
      }
    });
  }

  // Carica la cache persistente dei centri (se presente) e poi avvia il fetch
  Future<void> _loadPersistedCentersThenFetch() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final disease in const ['Psoriasi', 'Dermatite Atopica']) {
        final raw = prefs.getString('$_centersCachePrefix$disease');
        if (raw != null && raw.isNotEmpty) {
          final decoded = json.decode(raw);
          if (decoded is List) {
            _centersCache[disease] = List<dynamic>.from(decoded);
          }
        }
      }
    } catch (e) {
      debugPrint('Errore caricamento cache persistente: $e');
    }
    if (mounted) _fetchCenters();
  }

  // Salva la lista dei centri su disco (shared_preferences)
  Future<void> _persistCenters(String disease, List<dynamic> centers) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          '$_centersCachePrefix$disease', json.encode(centers));
    } catch (e) {
      debugPrint('Errore salvataggio cache persistente: $e');
    }
  }

  Future<void> _fetchCenters({bool forceRefresh = false}) async {
    if (!forceRefresh && _centersCache.containsKey(_selectedDisease)) {
      setState(() {
        _centers = _centersCache[_selectedDisease]!;
      });
      _preloadOtherDisease();
      _updateVisibleCenters();
      return;
    }

    setState(() {
      _isLoadingCenters = true;
    });

    try {
      final centers = await _fetchCentersForDisease(_selectedDisease);
      if (centers != null) {
        _centersCache[_selectedDisease] = centers;
        _persistCenters(_selectedDisease, centers);
        setState(() {
          _centers = centers;
          // Primo caricamento
          if (!_mapReady) {
            _visibleCenters = _centersWithinInitialRadius();
          }
        });
        _preloadOtherDisease();
        _updateVisibleCenters();
      } else {
        _restoreCentersFromCacheOrKeep();
        _showFetchError();
      }
    } catch (e) {
      debugPrint("Error fetching centers: $e");
      _restoreCentersFromCacheOrKeep();
      _showFetchError();
    } finally {
      if (mounted) setState(() => _isLoadingCenters = false);
    }
  }

  // Ripristina i centri dalla cache se disponibili
  void _restoreCentersFromCacheOrKeep() {
    final cached = _centersCache[_selectedDisease];
    if (cached != null && cached.isNotEmpty && _centers.isEmpty) {
      setState(() {
        _centers = cached;
      });
      _updateVisibleCenters();
    }
  }

  void _showFetchError() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Errore durante il caricamento dei centri. Riprova."),
        duration: Duration(seconds: 3),
      ),
    );
  }

  Future<void> _preloadOtherDisease() async {
    final otherDisease = _selectedDisease == 'Psoriasi' ? 'Dermatite Atopica' : 'Psoriasi';
    if (!_centersCache.containsKey(otherDisease)) {
      try {
        final centers = await _fetchCentersForDisease(otherDisease);
        if (centers != null) {
          _centersCache[otherDisease] = centers;
          _persistCenters(otherDisease, centers);
        }
      } catch (e) {
        debugPrint("Error preloading centers: $e");
      }
    }
  }

  Future<List<dynamic>?> _fetchCentersForDisease(String disease) async {
    if (disease == 'Psoriasi') {
      final response = await http
          .get(
            Uri.parse('https://www.vicinidipelle.it/wp-json/wpgmza/v1/markers?map_id=4'),
            // User-Agent tipo browser, per evitare blocchi
            headers: {
              'User-Agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
                      '(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36',
              'Accept': 'application/json',
            },
          )
          .timeout(_networkTimeout);
      if (response.statusCode == 200) {
        // Il body arriva con BOM UTF-8 iniziale... non json.encode utilizzabile...
        final String body = _decodeUtf8Body(response);
        final dynamic decoded = json.decode(body);
        if (decoded is! List) return null;
        final List<dynamic> allMarkers = decoded;
        return allMarkers.where((m) {
          final mapId = m['map_id']?.toString();
          final category = m['category']?.toString() ?? '';
          final categories = category.split(',').map((e) => e.trim()).toList();
          // Categoria 1: "Centri psoriasi/artrite psoriasica"
          // Categoria 4: "Centri dermatite atopica"
          // Usiamo solamente 1
          return mapId == '4' && categories.contains('1');
        }).map((m) {
          final desc = m['description']?.toString() ?? '';
          if (desc.isNotEmpty) {
            m['phone'] = _extractPhone(desc);
            m['email'] = _extractEmail(desc);
          }
          return m;
        }).toList();
      }
    } else {
      // Dermatite Atopica
      final response = await http
          .get(Uri.parse('https://centri.dermatopia.it/public-center'))
          .timeout(_networkTimeout);
      if (response.statusCode == 200) {
        final String body = _decodeUtf8Body(response);
        final decoded = json.decode(body);
        if (decoded['data'] is List) {
          return List<dynamic>.from(decoded['data']);
        }
      }
    }
    return null;
  }

  // Decodifica body
  String _decodeUtf8Body(http.Response response) {
    var body = utf8.decode(response.bodyBytes, allowMalformed: true);
    if (body.isNotEmpty && body.codeUnitAt(0) == 0xFEFF) {
      body = body.substring(1);
    }
    return body;
  }

  String? _extractEmail(String html) {
    // Trova email
    final emailRegex = RegExp(r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}');
    final matches = emailRegex
        .allMatches(html)
        .map((m) => m.group(0)!)
        .toSet()
        .toList();
    return matches.isEmpty ? null : matches.join(', ');
  }

  String? _extractPhone(String html) {
    final cleanText = html.replaceAll(RegExp(r'<[^>]*>'), ' ').trim();
    final phoneRegex = RegExp(r'\+?\d[\d\s\/\-\.\(\)]{7,}');
    final matches = phoneRegex
        .allMatches(cleanText)
        .map((m) => m.group(0)!.trim())
        // Scarta errori email
        .where((p) =>
            !p.contains('@') && RegExp(r'\d').allMatches(p).length >= 5)
        .toSet()
        .toList();
    return matches.isEmpty ? null : matches.join(' - ');
  }

  // Converte una coordinata in double, (spesso l'API ritorna valori errati)
  double? _parseCoordinate(dynamic value) {
    if (value == null) return null;
    var s = value.toString().trim();
    if (s.isEmpty) return null;
    final parts = s.split('.');
    if (parts.length > 2) {
      s = '${parts.first}.${parts.skip(1).join()}';
    }
    return double.tryParse(s);
  }

  // Colore del marker in base alla patologia selezionata
  Color _markerColorForDisease(String disease) {
    return disease == 'Psoriasi' ? Colors.redAccent : Colors.orangeAccent;
  }

  // Aggiorna la lista dei centri mostrati sulla mappa
  void _updateVisibleCenters() {
    if (!_mapReady) return;
    final camera = _mapController.camera;
    final bounds = camera.visibleBounds;

    final latPad = (bounds.north - bounds.south) * _boundsPaddingFactor;
    final lonPad = (bounds.east - bounds.west) * _boundsPaddingFactor;

    final visible = _centers.where((derm) {
      final lat = _parseCoordinate(derm['lat']);
      final lon = _parseCoordinate(derm['lon'] ?? derm['lng']);
      if (lat == null || lon == null) return false;
      return lat >= bounds.south - latPad &&
          lat <= bounds.north + latPad &&
          lon >= bounds.west - lonPad &&
          lon <= bounds.east + lonPad;
    }).toList();

    if (_sameCenters(_visibleCenters, visible)) return;
    if (mounted) {
      setState(() => _visibleCenters = visible);
    } else {
      _visibleCenters = visible;
    }
  }

  // Fusione delle liste (in pratica molti centri di dermatite fanno anche psoriasi
  // quindi standardizziamo i dati
  bool _sameCenters(List<dynamic> a, List<dynamic> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  // Filtra centri nel raggio
  List<dynamic> _centersWithinInitialRadius() {
    final LatLng center = widget.currentPosition != null
        ? LatLng(widget.currentPosition!.latitude, widget.currentPosition!.longitude)
        : const LatLng(41.9028, 12.4964);
    const Distance distance = Distance();
    return _centers.where((derm) {
      final lat = _parseCoordinate(derm['lat']);
      final lon = _parseCoordinate(derm['lon'] ?? derm['lng']);
      if (lat == null || lon == null) return false;
      final km = distance.as(
        LengthUnit.Kilometer,
        center,
        LatLng(lat, lon),
      );
      return km <= _initialRadiusKm;
    }).toList();
  }

  void _showPositionWarning() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Posizione corrente non disponibile"),
        duration: Duration(seconds: 4),
      ),
    );
  }

  void _showDermatologistPopup(Map<String, dynamic> derm) {
    String address = derm['address'] ?? '';
    if (derm['city'] != null && derm['city'].toString().isNotEmpty) {
      address += (address.isEmpty ? '' : ', ') + derm['city'];
    }
    if (derm['district'] != null && derm['district'].toString().isNotEmpty) {
      address += ' (${derm['district']})';
    }

    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      elevation: 5,
      barrierColor: Colors.black12,
      backgroundColor: Colors.transparent,
      builder: (_) => DermatologistPopup(
        name: derm['center_name'] ?? derm['name'] ?? derm['title'] ?? 'N/A',
        specialty: derm['department'] ?? derm['specialty'] ?? 'Centro Dermatologico',
        address: address,
        phone: derm['phone'],
        email: derm['email'],
      ),
    );
  }

  Future<void> _searchAddress() async {
    final query = _searchController.text;
    if (query.isEmpty) return;

    setState(() {
      _isSearching = true;
      _suggestions = [];
    });
    try {
      // Nominatim da OpenStreetMap
      final url = Uri.parse('https://nominatim.openstreetmap.org/search?q=${Uri.encodeComponent(query)}&format=json&limit=1');
      final response = await http.get(url, headers: {'User-Agent': 'tesi_derma_bsa'});
      
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        if (data.isNotEmpty) {
          final lat = double.parse(data[0]['lat']);
          final lon = double.parse(data[0]['lon']);
          _mapController.move(LatLng(lat, lon), 14.0);
          _updateVisibleCenters();
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Indirizzo non trovato")),
            );
          }
        }
      } else {
        throw Exception("Errore API");
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Errore durante la ricerca: $e")),
        );
      }
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      _fetchSuggestions(query);
    });
  }

  Future<void> _fetchSuggestions(String query) async {
    if (query.isEmpty) {
      setState(() => _suggestions = []);
      return;
    }

    try {
      final url = Uri.parse('https://nominatim.openstreetmap.org/search?q=${Uri.encodeComponent(query)}&format=json&limit=5&addressdetails=1');
      final response = await http.get(url, headers: {'User-Agent': 'tesi_derma_bsa'});
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (mounted) {
          setState(() {
            _suggestions = data;
          });
        }
      }
    } catch (e) {
      debugPrint('Error fetching suggestions: $e');
    }
  }

  void _selectSuggestion(dynamic suggestion) {
    final lat = double.parse(suggestion['lat']);
    final lon = double.parse(suggestion['lon']);
    final displayName = suggestion['display_name'];

    _searchController.text = displayName;
    setState(() {
      _suggestions = [];
    });
    _mapController.move(LatLng(lat, lon), 15.0);
    _updateVisibleCenters();
    FocusScope.of(context).unfocus();
  }

  void _zoomIn() {
    _mapController.move(_mapController.camera.center, _mapController.camera.zoom + 1);
    _updateVisibleCenters();
  }

  void _zoomOut() {
    _mapController.move(_mapController.camera.center, _mapController.camera.zoom - 1);
    _updateVisibleCenters();
  }

  void _moveToCurrentPosition() {
    if (widget.currentPosition != null) {
      _mapController.move(
        LatLng(widget.currentPosition!.latitude, widget.currentPosition!.longitude),
        15.0,
      );
      _updateVisibleCenters();
    } else {
      _showPositionWarning();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final LatLng initialCenter = widget.currentPosition != null
        ? LatLng(widget.currentPosition!.latitude, widget.currentPosition!.longitude)
        : const LatLng(41.9028, 12.4964);

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: initialCenter,
              // Zoom iniziale
              initialZoom: _initialZoom,
              onMapReady: () {
                _mapReady = true;
                _updateVisibleCenters();
              },
              onMapEvent: (event) {
                // Ricarica centri visibili
                if (event is MapEventMoveEnd ||
                    event is MapEventFlingAnimationEnd ||
                    event is MapEventDoubleTapZoomEnd ||
                    event is MapEventScrollWheelZoom ||
                    event is MapEventRotateEnd) {
                  _updateVisibleCenters();
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.tesi_derma_bsa',
              ),
              MarkerLayer(
                markers: _visibleCenters.map((derm) {
                  double? lat = _parseCoordinate(derm['lat']);
                  double? lon = _parseCoordinate(derm['lon'] ?? derm['lng']);

                  if (lat == null || lon == null) return const Marker(point: LatLng(0,0), child: SizedBox());

                  return Marker(
                    point: LatLng(lat, lon),
                    width: 50,
                    height: 50,
                    child: GestureDetector(
                      onTap: () => _showDermatologistPopup(derm),
                      child: Icon(
                        Icons.location_on,
                        color: _markerColorForDisease(_selectedDisease),
                        size: 40,
                      ),
                    ),
                  );
                }).where((m) => m.point.latitude != 0).toList(),
              ),
              if (widget.currentPosition != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: LatLng(widget.currentPosition!.latitude, widget.currentPosition!.longitude),
                      width: 20,
                      height: 20,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.blue,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.blue.withValues(alpha: 0.5),
                              blurRadius: 10,
                              spreadRadius: 5,
                            )
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),

          // Barra UI Ricerca
          Positioned(
            top: 50,
            left: 20,
            right: 20,
            child: Column(
              children: [
                Row(
                  children: [
                    _buildCircleButton(Icons.arrow_back_ios_new, () => Navigator.of(context).pop()),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 15),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(30),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.1),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            )
                          ],
                        ),
                        child: TextField(
                          controller: _searchController,
                          textAlignVertical: TextAlignVertical.center,
                          decoration: InputDecoration(
                            hintText: "Cerca indirizzo...",
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(vertical: 12),
                            isDense: true,
                            suffixIcon: _isSearching
                                ? const Padding(
                                    padding: EdgeInsets.all(12.0),
                                    child: SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(strokeWidth: 2)),
                                  )
                                : IconButton(
                                    icon: const Icon(Icons.search),
                                    onPressed: _searchAddress,
                                  ),
                          ),
                          onChanged: _onSearchChanged,
                          onSubmitted: (_) => _searchAddress(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'Dermatite Atopica', label: Text('Dermatite')),
                    ButtonSegment(value: 'Psoriasi', label: Text('Psoriasi')),
                  ],
                  selected: {_selectedDisease},
                  style: SegmentedButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.9),
                    selectedBackgroundColor: Theme.of(context).colorScheme.primary,
                    selectedForegroundColor: Colors.white,
                  ),
                  onSelectionChanged: (Set<String> newSelection) {
                    setState(() {
                      _selectedDisease = newSelection.first;
                    });
                    _fetchCenters();
                  },
                ),
                if (_suggestions.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 5, left: 55),
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(15),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        )
                      ],
                    ),
                    constraints: const BoxConstraints(maxHeight: 250),
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      itemCount: _suggestions.length,
                      separatorBuilder: (context, index) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final suggestion = _suggestions[index];
                        return ListTile(
                          leading: const Icon(Icons.location_on_outlined, size: 20),
                          title: Text(
                            suggestion['display_name'],
                            style: const TextStyle(fontSize: 14),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => _selectSuggestion(suggestion),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),

          // Controlli mappa
          Positioned(
            bottom: 120,
            right: 20,
            child: Column(
              children: [
                _buildCircleButton(Icons.refresh, () => _fetchCenters(forceRefresh: true)),
                const SizedBox(height: 10),
                _buildCircleButton(Icons.add, _zoomIn),
                const SizedBox(height: 10),
                _buildCircleButton(Icons.remove, _zoomOut),
                const SizedBox(height: 20),
                _buildCircleButton(Icons.my_location, _moveToCurrentPosition),
              ],
            ),
          ),
          // Caricamento centri (solo al primo caricamento, quando non ci sono
          // ancora centri da mostrare: durante il refresh la mappa resta visibile)
          if (_isLoadingCenters && _centers.isEmpty)
            const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }

  Widget _buildCircleButton(IconData icon, VoidCallback? onTap) {
    return Container(
      width: 45,
      height: 45,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          )
        ],
      ),
      child: IconButton(
        icon: Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        onPressed: onTap,
      ),
    );
  }
}

class DermatologistPopup extends StatelessWidget {
  final String name;
  final String specialty;
  final String address;
  final String? phone;
  final String? email;

  const DermatologistPopup({
    super.key,
    required this.name,
    required this.specialty,
    required this.address,
    this.phone,
    this.email,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(25),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 20,
            offset: const Offset(0, -5),
          )
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                child: Icon(Icons.local_hospital, color: Theme.of(context).colorScheme.primary),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    if (specialty.isNotEmpty && specialty != 'null')
                      Text(
                        specialty,
                        style: TextStyle(color: Colors.grey[600], fontSize: 13),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 30),
          _buildInfoRow(Icons.location_on_outlined, address),
          if (phone != null && phone!.isNotEmpty) ...[
            const SizedBox(height: 10),
            _buildInfoRow(Icons.phone_outlined, phone!),
          ],
          if (email != null && email!.isNotEmpty) ...[
            const SizedBox(height: 10),
            _buildInfoRow(Icons.email_outlined, email!),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text("Chiudi"),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: Colors.grey),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 14),
          ),
        ),
      ],
    );
  }
}
