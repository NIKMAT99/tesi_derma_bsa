import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:http/http.dart' as http;

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
  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;
  List<dynamic> _suggestions = [];
  Timer? _debounce;

  String _selectedDisease = 'Dermatite Atopica';
  List<dynamic> _centers = [];
  bool _isLoadingCenters = false;
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
    _fetchCenters();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.currentPosition == null) {
        _showPositionWarning();
      }
    });
  }

  Future<void> _fetchCenters({bool forceRefresh = false}) async {
    if (!forceRefresh && _centersCache.containsKey(_selectedDisease)) {
      setState(() {
        _centers = _centersCache[_selectedDisease]!;
      });
      return;
    }

    setState(() {
      _isLoadingCenters = true;
      if (forceRefresh) {
        _centers = [];
      }
    });

    try {
      if (_selectedDisease == 'Psoriasi') {
        final response = await http.get(Uri.parse('https://www.vicinidipelle.it/wp-json/wpgmza/v1/markers?map_id=4'));
        if (response.statusCode == 200) {
          final List<dynamic> allMarkers = json.decode(response.body);
          final filtered = allMarkers.where((m) {
            final mapId = m['map_id']?.toString();
            final category = m['category']?.toString() ?? '';
            final categories = category.split(',').map((e) => e.trim()).toList();
            return mapId == '4' && categories.contains('4');
          }).map((m) {
            final desc = m['description']?.toString() ?? '';
            if (desc.isNotEmpty) {
              m['phone'] = _extractPhone(desc);
              m['email'] = _extractEmail(desc);
            }
            return m;
          }).toList();

          _centersCache['Psoriasi'] = filtered;
          setState(() {
            _centers = filtered;
          });
        }
      } else {
        // Dermatite Atopica
        final response = await http.get(Uri.parse('https://centri.dermatopia.it/public-center'));
        if (response.statusCode == 200) {
          final decoded = json.decode(response.body);
          if (decoded['data'] is List) {
            final data = List<dynamic>.from(decoded['data']);
            _centersCache['Dermatite Atopica'] = data;
            setState(() {
              _centers = data;
            });
          }
        }
      }
    } catch (e) {
      debugPrint("Error fetching centers: $e");
    } finally {
      if (mounted) setState(() => _isLoadingCenters = false);
    }
  }

  String? _extractEmail(String html) {
    final emailRegex = RegExp(r'mailto:([a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,})');
    final match = emailRegex.firstMatch(html);
    return match?.group(1);
  }

  String? _extractPhone(String html) {
    final cleanText = html.replaceAll(RegExp(r'<[^>]*>'), ' ').trim();
    final phoneRegex = RegExp(r'(\+?\d[\d\s\/\-]{7,})');
    final match = phoneRegex.firstMatch(cleanText);
    return match?.group(1)?.trim();
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
    FocusScope.of(context).unfocus();
  }

  void _zoomIn() {
    _mapController.move(_mapController.camera.center, _mapController.camera.zoom + 1);
  }

  void _zoomOut() {
    _mapController.move(_mapController.camera.center, _mapController.camera.zoom - 1);
  }

  void _moveToCurrentPosition() {
    if (widget.currentPosition != null) {
      _mapController.move(
        LatLng(widget.currentPosition!.latitude, widget.currentPosition!.longitude),
        15.0,
      );
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
              initialZoom: widget.currentPosition != null ? 13.0 : 6.0,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.tesi_derma_bsa',
              ),
              MarkerLayer(
                markers: _centers.map((derm) {
                  double? lat = double.tryParse(derm['lat']?.toString() ?? '');
                  double? lon = double.tryParse(derm['lon']?.toString() ?? derm['lng']?.toString() ?? '');

                  if (lat == null || lon == null) return const Marker(point: LatLng(0,0), child: SizedBox());

                  return Marker(
                    point: LatLng(lat, lon),
                    width: 50,
                    height: 50,
                    child: GestureDetector(
                      onTap: () => _showDermatologistPopup(derm),
                      child: const Icon(
                        Icons.location_on,
                        color: Colors.redAccent,
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
                          decoration: InputDecoration(
                            hintText: "Cerca indirizzo...",
                            border: InputBorder.none,
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
          // Caricamento centri
          if (_isLoadingCenters)
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
