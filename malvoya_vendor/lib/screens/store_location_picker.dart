import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:malvoya_core/malvoya_core.dart';
import 'package:malvoya_ui/malvoya_ui.dart';
import '../config/theme.dart';

/// Where couriers pick up: the owner moves the map under the pin (or taps a spot) until the pin is on
/// the shop's door. It starts at the saved pin, else at the typed address (found with OpenStreetMap's
/// Nominatim), else at the phone's position if location is already allowed, else in central Helsinki.
/// Returns the chosen [LatLng], or null when cancelled.
class StoreLocationPicker extends StatefulWidget {
  final double? initialLat;
  final double? initialLng;
  final String? address;
  const StoreLocationPicker({super.key, this.initialLat, this.initialLng, this.address});

  @override
  State<StoreLocationPicker> createState() => _StoreLocationPickerState();
}

class _StoreLocationPickerState extends State<StoreLocationPicker> {
  static const _helsinki = LatLng(60.1699, 24.9384);
  final _map = MapController();
  late final _search = TextEditingController(text: widget.address ?? '');
  LatLng _center = _helsinki;
  bool _ready = false;
  bool _busy = false;
  String? _note;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    LatLng? start;
    if (widget.initialLat != null && widget.initialLng != null) {
      start = LatLng(widget.initialLat!, widget.initialLng!);
    } else {
      if ((widget.address ?? '').trim().length >= 5) start = await _geocode(widget.address!);
      start ??= await _lastKnownIfAllowed();
    }
    if (!mounted) return;
    setState(() {
      _center = start ?? _helsinki;
      _ready = true;
      if (start == null) {
        _note = tr(context, 'Move the map so the pin is on your shop.', 'Siirrä karttaa niin, että neula on kauppasi kohdalla.');
      }
    });
  }

  /// The first OpenStreetMap match for an address (one request, only when asked: Nominatim's usage policy).
  Future<LatLng?> _geocode(String query) async {
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/search', {'format': 'json', 'q': query, 'limit': '1', 'countrycodes': 'fi'});
      final res = await http.get(uri, headers: {'User-Agent': 'MalvoyaStore/1.0 (com.malvoya.vendor)', 'Accept': 'application/json'}).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      final list = jsonDecode(res.body);
      if (list is! List || list.isEmpty || list.first is! Map) return null;
      final first = list.first as Map;
      final lat = double.tryParse('${first['lat']}');
      final lon = double.tryParse('${first['lon']}');
      return lat == null || lon == null ? null : LatLng(lat, lon);
    } catch (_) {
      return null;
    }
  }

  /// The phone's position without asking for permission (asking happens only on "Use my current location").
  Future<LatLng?> _lastKnownIfAllowed() async {
    try {
      final p = await Geolocator.checkPermission();
      if (p != LocationPermission.always && p != LocationPermission.whileInUse) return null;
      final pos = await Geolocator.getLastKnownPosition();
      return pos == null ? null : LatLng(pos.latitude, pos.longitude);
    } catch (_) {
      return null;
    }
  }

  void _moveTo(LatLng target, {double zoom = 17}) {
    setState(() => _center = target);
    _map.move(target, zoom);
  }

  Future<void> _findAddress() async {
    final q = _search.text.trim();
    if (q.length < 3) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _note = null;
    });
    final found = await _geocode(q);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (found == null) {
        _note = tr(context, 'Address not found. Move the map to your shop instead.', 'Osoitetta ei löytynyt. Siirrä karttaa kauppasi kohdalle.');
      }
    });
    if (found != null) _moveTo(found);
  }

  Future<void> _useCurrentLocation() async {
    HapticFeedback.selectionClick();
    setState(() {
      _busy = true;
      _note = null;
    });
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        if (mounted) setState(() => _note = tr(context, 'Location permission is off. Move the map to your shop instead.', 'Sijaintilupa on pois päältä. Siirrä karttaa kauppasi kohdalle.'));
        return;
      }
      final pos = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high));
      if (mounted) _moveTo(LatLng(pos.latitude, pos.longitude));
    } catch (_) {
      if (mounted) setState(() => _note = tr(context, 'Could not get your location. Check that location is on.', 'Sijaintia ei saatu. Tarkista, että sijainti on päällä.'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _zoom(double by) {
    final z = (_map.camera.zoom + by).clamp(4.0, 19.0);
    _map.move(_map.camera.center, z);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: Text(tr(context, 'Pin your shop', 'Merkitse kauppasi kartalle'))),
      body: !_ready
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(MSpace.lg, MSpace.xs, MSpace.lg, MSpace.sm),
                child: TextField(
                  controller: _search,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _findAddress(),
                  decoration: InputDecoration(
                    labelText: tr(context, 'Find an address', 'Hae osoitetta'),
                    suffixIcon: IconButton(
                      tooltip: tr(context, 'Find', 'Hae'),
                      onPressed: _busy ? null : _findAddress,
                      icon: const Icon(Icons.search_rounded),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Stack(children: [
                  FlutterMap(
                    mapController: _map,
                    options: MapOptions(
                      initialCenter: _center,
                      initialZoom: 17,
                      minZoom: 4,
                      maxZoom: 19,
                      onPositionChanged: (camera, _) => _center = camera.center,
                      onTap: (_, point) => _moveTo(point, zoom: _map.camera.zoom),
                    ),
                    children: [
                      TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.malvoya.vendor', maxZoom: 19),
                    ],
                  ),
                  // The pin stays in the middle; its tip marks the spot
                  const IgnorePointer(
                    child: Center(
                      child: Padding(
                        padding: EdgeInsets.only(bottom: 44),
                        child: Icon(Icons.location_on_rounded, size: 48, color: AppTheme.primary),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 12,
                    top: 12,
                    child: Column(children: [
                      _mapButton(Icons.add_rounded, tr(context, 'Zoom in', 'Lähennä'), () => _zoom(1)),
                      const SizedBox(height: MSpace.sm),
                      _mapButton(Icons.remove_rounded, tr(context, 'Zoom out', 'Loitonna'), () => _zoom(-1)),
                    ]),
                  ),
                  Positioned(
                    left: 8,
                    bottom: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      color: AppTheme.surface.withValues(alpha: 0.85),
                      child: const Text('© OpenStreetMap contributors', style: TextStyle(fontSize: MTextSize.caption, color: AppTheme.textPrimary)),
                    ),
                  ),
                ]),
              ),
            ]),
      bottomNavigationBar: !_ready
          ? null
          : SafeArea(
              minimum: const EdgeInsets.fromLTRB(MSpace.lg, 10, MSpace.lg, MSpace.lg),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(
                  _note ?? tr(context, 'Drag the map or tap a spot so the pin is on your shop\'s door. Couriers come here.',
                      'Vedä karttaa tai napauta kohtaa niin, että neula on kauppasi ovella. Kuriirit tulevat tähän.'),
                  style: const TextStyle(fontSize: MTextSize.label, color: AppTheme.textSecondary, height: 1.35),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _useCurrentLocation,
                  icon: _busy
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.my_location_rounded),
                  label: Text(tr(context, 'Use my current location', 'Käytä nykyistä sijaintia')),
                ),
                const SizedBox(height: MSpace.sm),
                FilledButton.icon(
                  onPressed: () => Navigator.pop(context, _center),
                  icon: const Icon(Icons.check_rounded),
                  label: Text(tr(context, 'Pin is on my shop', 'Neula on kauppani kohdalla')),
                ),
              ]),
            ),
    );
  }

  Widget _mapButton(IconData icon, String label, VoidCallback onTap) => Material(
        color: AppTheme.surface,
        shape: const CircleBorder(),
        elevation: 2,
        child: IconButton(tooltip: label, onPressed: onTap, icon: Icon(icon, color: AppTheme.textPrimary), constraints: const BoxConstraints(minWidth: 48, minHeight: 48)),
      );
}
