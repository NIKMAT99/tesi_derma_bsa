import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:geocoding/geocoding.dart';

class DermatogistsMapWidget extends StatefulWidget {
  final List<Map<String, dynamic>> preloadedDermatologists;
  final geo.Position? currentPosition;
  const DermatogistsMapWidget(
      {super.key,
      required this.preloadedDermatologists,
      required this.currentPosition});

  @override
  DermatogistsMapWidgetState createState() => DermatogistsMapWidgetState();
}

class DermatogistsMapWidgetState extends State<DermatogistsMapWidget>
    with AutomaticKeepAliveClientMixin {
  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.currentPosition == null) {
        _showPositionWarning();
      }
    });
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
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      elevation: 5,
      barrierColor: Colors.black12,
      backgroundColor: Colors.transparent,
      builder: (_) => DermatologistPopup(
        name: derm['center_name'] ?? derm['name'] ?? 'N/A',
        specialty: derm['department'] ?? derm['specialty'] ?? 'Centro Dermatologico',
        address: '${derm['address'] ?? ''}, ${derm['city'] ?? ''} (${derm['district'] ?? ''})',
        phone: derm['phone'],
        email: derm['email'],
      ),
    );
  }

  Future<void> _searchAddress() async {
    final query = _searchController.text;
    if (query.isEmpty) return;

    setState(() => _isSearching = true);
    try {
      List<Location> locations = await locationFromAddress(query);
      if (locations.isNotEmpty) {
        final loc = locations.first;
        _mapController.move(LatLng(loc.latitude, loc.longitude), 14.0);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Indirizzo non trovato")),
          );
        }
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
                markers: widget.preloadedDermatologists.map((derm) {
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
                          onSubmitted: (_) => _searchAddress(),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // CONTROLLI ZOOM E POSIZIONE
          Positioned(
            bottom: 120,
            right: 20,
            child: Column(
              children: [
                _buildCircleButton(Icons.add, _zoomIn),
                const SizedBox(height: 10),
                _buildCircleButton(Icons.remove, _zoomOut),
                const SizedBox(height: 20),
                _buildCircleButton(Icons.my_location, _moveToCurrentPosition),
              ],
            ),
          ),
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
