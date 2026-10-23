import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'package:malvoya_core/malvoya_core.dart';
import 'package:malvoya_ui/malvoya_ui.dart';
import '../config/theme.dart';
import '../core/current_position.dart';
import '../local_notification_service.dart';


class AddressResult {
  final String street;
  final String houseNumber;
  final String postalCode;
  final String city;
  final String fullAddress;
  final double latitude;
  final double longitude;

  AddressResult({
    required this.street,
    required this.houseNumber,
    required this.postalCode,
    required this.city,
    required this.fullAddress,
    required this.latitude,
    required this.longitude,
  });

  String get formattedAddress => fullAddress;
}

class MapAddressPickerScreen extends StatefulWidget {
  final double? initialLat;
  final double? initialLng;
  final String? initialAddress;

  /// Start from the phone's position ("Use my location") instead of the given/default spot.
  final bool locateOnOpen;

  const MapAddressPickerScreen({
    super.key,
    this.initialLat,
    this.initialLng,
    this.initialAddress,
    this.locateOnOpen = false,
  });

  @override
  State<MapAddressPickerScreen> createState() => _MapAddressPickerScreenState();
}

class _MapAddressPickerScreenState extends State<MapAddressPickerScreen> {
  late final MapController _mapController;
  late LatLng _currentCenter;
  bool _isGeocoding = false;
  Timer? _debounceTimer;


  // OpenStreetMap tiles (licensed for use with attribution). Google's tile servers may not be
  // used directly outside the official Maps SDK, so there is no satellite layer.
  String get _currentTileUrl => 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  // Filled in from OpenStreetMap's reverse geocoding of the pin
  String _street = '';
  String _houseNumber = '';
  String _postalCode = '';
  String _city = 'Helsinki';
  String _fullAddress = '';
  bool _locating = false;

  final TextEditingController _searchCtrl = TextEditingController();
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _currentCenter = LatLng(
      widget.initialLat ?? 60.1699,
      widget.initialLng ?? 24.9384,
    );
    if (widget.initialAddress != null && widget.initialAddress!.isNotEmpty) {
      _fullAddress = widget.initialAddress!;
    }
    // Reverse geocode the initial center, or first find the phone's position
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.locateOnOpen) {
        _locate();
      } else {
        _reverseGeocode(_currentCenter);
      }
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onPositionChanged(MapCamera camera, bool hasGesture) {
    _currentCenter = camera.center;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 550), () {
      if (mounted) {
        _reverseGeocode(_currentCenter);
      }
    });
  }

  /// Centres the map on the phone's real position. If location is off or not allowed, the map stays
  /// where it is and the customer drags it instead.
  Future<void> _locate() async {
    if (_locating) return;
    setState(() => _locating = true);
    final (pos, problem) = await CurrentPosition.read();
    if (!mounted) return;
    setState(() => _locating = false);
    if (pos != null) {
      _mapController.move(pos, 17.0);
      _currentCenter = pos;
      _reverseGeocode(pos);
      return;
    }
    if (_fullAddress.isEmpty) _reverseGeocode(_currentCenter);
    final canFix = problem == LocateProblem.deniedForever || problem == LocateProblem.serviceOff;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(CurrentPosition.message(context, problem!)),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 6),
      action: canFix ? SnackBarAction(label: tr(context, 'Settings', 'Asetukset'), onPressed: () => CurrentPosition.openSettings(problem)) : null,
    ));
  }

  Future<void> _reverseGeocode(LatLng point) async {
    if (!mounted) return;
    setState(() => _isGeocoding = true);

    try {
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?format=json&lat=${point.latitude}&lon=${point.longitude}&zoom=18&addressdetails=1',
      );
      final res = await http.get(url, headers: {
        'User-Agent': 'MalvoyaConsumerApp/1.0',
        'Accept': 'application/json',
      }).timeout(const Duration(seconds: 6));

      if (res.statusCode == 200 && mounted) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final address = data['address'] as Map<String, dynamic>? ?? {};

        final road = address['road'] ?? address['pedestrian'] ?? address['footway'] ?? address['suburb'] ?? '';
        final houseNo = address['house_number'] ?? '';
        final post = address['postcode'] ?? '';
        final town = address['city'] ?? address['town'] ?? address['village'] ?? address['municipality'] ?? 'Helsinki';

        setState(() {
          _street = road.toString();
          _houseNumber = houseNo.toString();
          _postalCode = post.toString();
          _city = town.toString();

          final parts = <String>[];
          if (houseNo.isNotEmpty) {
            parts.add('$_street $_houseNumber');
          } else if (_street.isNotEmpty) {
            parts.add(_street);
          }
          if (_postalCode.isNotEmpty) parts.add(_postalCode);
          if (_city.isNotEmpty) parts.add(_city);

          _fullAddress = parts.isNotEmpty ? parts.join(', ') : (data['display_name'] ?? 'Selected Location');
          _isGeocoding = false;
        });
        return;
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        _isGeocoding = false;
        if (_street.isEmpty) _fullAddress = _coordinates(point);
      });
    }
  }

  Future<void> _searchAddress(String query) async {
    if (query.trim().isEmpty) return;
    setState(() => _isSearching = true);
    FocusScope.of(context).unfocus();

    try {
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/search?format=json&q=${Uri.encodeComponent(query)}&limit=1&addressdetails=1',
      );
      final res = await http.get(url, headers: {
        'User-Agent': 'MalvoyaConsumerApp/1.0',
        'Accept': 'application/json',
      }).timeout(const Duration(seconds: 6));

      if (res.statusCode == 200 && mounted) {
        final list = jsonDecode(res.body) as List;
        if (list.isNotEmpty) {
          final first = list.first as Map<String, dynamic>;
          final lat = double.parse(first['lat'].toString());
          final lon = double.parse(first['lon'].toString());
          final target = LatLng(lat, lon);
          _mapController.move(target, 16.0);
          _currentCenter = target;
          _reverseGeocode(target);
        } else {
          MSnack.show(context, tr(context, 'Address not found. Drag the map so the pin is on your door.',
                  'Osoitetta ei löytynyt. Vedä karttaa, kunnes merkki on ovesi kohdalla.'));
        }
      }
    } catch (_) {
      if (mounted) {
        MSnack.show(context, tr(context, 'The search did not answer. Drag the map to your door instead.',
                'Haku ei vastannut. Vedä kartta ovesi kohdalle.'));
      }
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  void _confirmAndReturn() {
    Haptics.medium();
    final result = AddressResult(
      street: _street,
      houseNumber: _houseNumber,
      postalCode: _postalCode,
      city: _city,
      fullAddress: _fullAddress.isNotEmpty ? _fullAddress : _coordinates(_currentCenter),
      latitude: _currentCenter.latitude,
      longitude: _currentCenter.longitude,
    );
    Navigator.pop(context, result);
  }

  String _coordinates(LatLng p) => '${p.latitude.toStringAsFixed(4)}° N, ${p.longitude.toStringAsFixed(4)}° E';

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = AppTheme.cardBackground(context);
    final textPrimary = AppTheme.primaryText(context);
    final textSecondary = AppTheme.secondaryText(context);
    final borderColor = AppTheme.cardBorder(context);

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _currentCenter,
              initialZoom: 16.0,
              maxZoom: 20.0,
              minZoom: 4.0,
              onPositionChanged: _onPositionChanged,
            ),
            children: [
              TileLayer(
                urlTemplate: _currentTileUrl,
                userAgentPackageName: 'com.malvoya.customer',
                maxZoom: 20,
              ),
            ],
          ),

          // 2. Fixed Center Pin with Target Ring
          Center(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 42),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Speech bubble showing 'Deliver here'
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: MSpace.md, vertical: 6),
                    decoration: BoxDecoration(
                      color: MPalette.night,
                      borderRadius: BorderRadius.circular(MRadius.md),
                      boxShadow: [
                        BoxShadow(color: MPalette.night.withValues(alpha: 0.35), blurRadius: 10, offset: const Offset(0, 4)),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_isGeocoding)
                          const SizedBox(
                            width: 12, height: 12,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.onBrand),
                          )
                        else
                          const Icon(Icons.touch_app_rounded, color: AppTheme.onBrand, size: 14),
                        const SizedBox(width: 6),
                        Text(
                          tr(context, 'Deliver here', 'Toimitus tähän'),
                          style: const TextStyle(color: AppTheme.onBrand, fontSize: MTextSize.caption, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: MSpace.xs),
                  // Pin Marker
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppTheme.primary,
                      shape: BoxShape.circle,
                      border: Border.all(color: MPalette.white, width: 3),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.primary.withValues(alpha: 0.55),
                          blurRadius: 14,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.location_on_rounded, color: AppTheme.onBrand, size: 24),
                  ),
                  // Pin Point Stem Shadow
                  Container(
                    width: 10,
                    height: 5,
                    decoration: BoxDecoration(
                      color: MPalette.night.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 3. Top Floating Search & Back Header
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(MSpace.lg, MSpace.md, MSpace.lg, 0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: cardBg,
                            borderRadius: BorderRadius.circular(MRadius.md),
                            border: Border.all(color: borderColor),
                            boxShadow: [
                              BoxShadow(color: MPalette.night.withValues(alpha: 0.12), blurRadius: 12, offset: const Offset(0, 4)),
                            ],
                          ),
                          child: Icon(Icons.arrow_back_rounded, color: textPrimary, size: 20),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Container(
                          height: 46,
                          decoration: BoxDecoration(
                            color: cardBg,
                            borderRadius: BorderRadius.circular(MRadius.md),
                            border: Border.all(color: borderColor),
                            boxShadow: [
                              BoxShadow(color: MPalette.night.withValues(alpha: 0.12), blurRadius: 12, offset: const Offset(0, 4)),
                            ],
                          ),
                          child: Row(
                            children: [
                              const SizedBox(width: 14),
                              const Icon(Icons.search_rounded, color: AppTheme.primary, size: 20),
                              const SizedBox(width: MSpace.sm),
                              Expanded(
                                child: TextField(
                                  controller: _searchCtrl,
                                  textInputAction: TextInputAction.search,
                                  onSubmitted: _searchAddress,
                                  style: TextStyle(fontSize: MTextSize.label, fontWeight: FontWeight.w600, color: textPrimary),
                                  decoration: InputDecoration(
                                    hintText: tr(context, 'Search street, building, city…', 'Hae katu, rakennus, kaupunki…'),
                                    hintStyle: TextStyle(fontSize: MTextSize.label, color: textSecondary),
                                    border: InputBorder.none,
                                    enabledBorder: InputBorder.none,
                                    focusedBorder: InputBorder.none,
                                    isDense: true,
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                ),
                              ),
                              if (_isSearching)
                                const Padding(
                                  padding: EdgeInsets.only(right: MSpace.md),
                                  child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                                )
                              else if (_searchCtrl.text.isNotEmpty)
                                IconButton(
                                  tooltip: tr(context, 'Clear', 'Tyhjennä'),
                                  icon: Icon(Icons.clear_rounded, size: 16, color: AppTheme.secondaryText(context)),
                                  onPressed: () {
                                    _searchCtrl.clear();
                                    setState(() {});
                                  },
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  Text('© OpenStreetMap contributors', style: TextStyle(fontSize: MTextSize.caption, color: AppTheme.secondaryText(context))),
                ],
              ),
            ),
          ),

          // 4. Floating Action Controls on Right Side (Zoom In, Zoom Out, Recenter, 3D Google Maps)
          Positioned(
            right: 16,
            bottom: 245,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Open the spot in the phone's maps app
                GestureDetector(
                  onTap: () {
                    Haptics.light();
                    LocalNotificationService.openGoogleMaps(
                      lat: _currentCenter.latitude,
                      lng: _currentCenter.longitude,
                      label: _street,
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: MSpace.sm),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(MRadius.md),
                      border: Border.all(color: borderColor),
                      boxShadow: [
                        BoxShadow(color: MPalette.night.withValues(alpha: 0.15), blurRadius: 10, offset: const Offset(0, 3)),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.travel_explore_rounded, color: AppTheme.primary, size: 16),
                        const SizedBox(width: 5),
                        Text(tr(context, 'Open in Maps', 'Avaa kartat'), style: TextStyle(fontSize: MTextSize.caption, fontWeight: FontWeight.w800, color: textPrimary)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                // Zoom In (+)
                GestureDetector(
                  onTap: () {
                    Haptics.light();
                    final newZoom = (_mapController.camera.zoom + 1.0).clamp(4.0, 20.0);
                    _mapController.move(_currentCenter, newZoom);
                  },
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                      border: Border.all(color: borderColor),
                      boxShadow: [
                        BoxShadow(color: MPalette.night.withValues(alpha: 0.1), blurRadius: 8, offset: const Offset(0, 2)),
                      ],
                    ),
                    child: Icon(Icons.add_rounded, color: textPrimary, size: 20),
                  ),
                ),
                // Zoom Out (-)
                GestureDetector(
                  onTap: () {
                    Haptics.light();
                    final newZoom = (_mapController.camera.zoom - 1.0).clamp(4.0, 20.0);
                    _mapController.move(_currentCenter, newZoom);
                  },
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14)),
                      border: Border(
                        left: BorderSide(color: borderColor),
                        right: BorderSide(color: borderColor),
                        bottom: BorderSide(color: borderColor),
                      ),
                      boxShadow: [
                        BoxShadow(color: MPalette.night.withValues(alpha: 0.1), blurRadius: 8, offset: const Offset(0, 2)),
                      ],
                    ),
                    child: Icon(Icons.remove_rounded, color: textPrimary, size: 20),
                  ),
                ),
                const SizedBox(height: 10),

                // GPS Re-Center Floating Button
                GestureDetector(
                  onTap: () {
                    Haptics.light();
                    _locate();
                  },
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: cardBg,
                      shape: BoxShape.circle,
                      border: Border.all(color: borderColor),
                      boxShadow: [
                        BoxShadow(color: MPalette.night.withValues(alpha: 0.14), blurRadius: 10, offset: const Offset(0, 3)),
                      ],
                    ),
                    child: _locating
                        ? const Padding(padding: EdgeInsets.all(14), child: CircularProgressIndicator(strokeWidth: 2))
                        : Icon(Icons.my_location_rounded, color: AppTheme.primary, size: 20, semanticLabel: tr(context, 'Use my location', 'Käytä sijaintiani')),
                  ),
                ),
              ],
            ),
          ),

          // 5. Bottom Verified Delivery Address Confirmation Card
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(MRadius.lg),
                border: Border.all(color: borderColor, width: 1.2),
                boxShadow: [
                  BoxShadow(color: MPalette.night.withValues(alpha: 0.15), blurRadius: 24, offset: const Offset(0, 8)),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(MSpace.sm),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(MRadius.sm),
                        ),
                        child: const Icon(Icons.location_on_rounded, color: AppTheme.primary, size: 20),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _street.isNotEmpty
                                  ? (_houseNumber.isNotEmpty ? '$_street $_houseNumber' : _street)
                                  : (_isGeocoding || _locating ? tr(context, 'Finding the address…', 'Haetaan osoitetta…') : tr(context, 'Pinned spot', 'Merkitty kohta')),
                              style: TextStyle(fontWeight: FontWeight.w800, fontSize: MTextSize.bodyL, color: textPrimary),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${_currentCenter.latitude.toStringAsFixed(4)}° N, ${_currentCenter.longitude.toStringAsFixed(4)}° E',
                              style: TextStyle(fontSize: MTextSize.caption, color: textSecondary, fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ),
                      if (_isGeocoding)
                        const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                    ],
                  ),
                  const SizedBox(height: MSpace.md),
                  Container(
                    padding: const EdgeInsets.all(MSpace.md),
                    decoration: BoxDecoration(
                      color: isDark ? MPalette.nightSurfaceVariant : MPalette.birch,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: isDark ? MPalette.nightRaised : AppTheme.primary.withValues(alpha: 0.12)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.home_outlined, color: AppTheme.primary, size: 16),
                        const SizedBox(width: MSpace.sm),
                        Expanded(
                          child: Text(
                            _fullAddress.isNotEmpty ? _fullAddress : tr(context, 'Drag the map so the pin is on your door', 'Vedä karttaa, kunnes merkki on ovesi kohdalla'),
                            style: TextStyle(fontSize: MTextSize.caption, fontWeight: FontWeight.w600, color: textPrimary),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: MSpace.lg),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: AppTheme.onBrand,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                        elevation: 2,
                      ),
                      onPressed: _confirmAndReturn,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.check_circle_rounded, color: AppTheme.onBrand, size: 18),
                          const SizedBox(width: MSpace.sm),
                          Flexible(
                            child: Text(tr(context, 'Confirm this spot', 'Vahvista tämä kohta'),
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: MTextSize.bodyL, fontWeight: FontWeight.w800, color: AppTheme.onBrand)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
