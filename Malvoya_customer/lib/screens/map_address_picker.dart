import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import '../config/theme.dart';
import '../local_notification_service.dart';

enum GoogleMapLayer {
  hybrid,
  satellite,
  roadmap,
  terrain,
}

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

  const MapAddressPickerScreen({
    super.key,
    this.initialLat,
    this.initialLng,
    this.initialAddress,
  });

  @override
  State<MapAddressPickerScreen> createState() => _MapAddressPickerScreenState();
}

class _MapAddressPickerScreenState extends State<MapAddressPickerScreen> {
  late final MapController _mapController;
  late LatLng _currentCenter;
  bool _isGeocoding = false;
  Timer? _debounceTimer;

  GoogleMapLayer _selectedLayer = GoogleMapLayer.hybrid;

  String get _currentTileUrl {
    switch (_selectedLayer) {
      case GoogleMapLayer.satellite:
        return 'https://mt1.google.com/vt/lyrs=s&x={x}&y={y}&z={z}';
      case GoogleMapLayer.hybrid:
        return 'https://mt1.google.com/vt/lyrs=y&x={x}&y={y}&z={z}';
      case GoogleMapLayer.terrain:
        return 'https://mt1.google.com/vt/lyrs=p&x={x}&y={y}&z={z}';
      case GoogleMapLayer.roadmap:
      default:
        return 'https://mt1.google.com/vt/lyrs=m&x={x}&y={y}&z={z}';
    }
  }

  String _street = 'Scanning map...';
  String _houseNumber = '';
  String _postalCode = '';
  String _city = 'Helsinki';
  String _fullAddress = 'Drag map to pin your exact entrance';

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
    // Reverse geocode the initial center
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reverseGeocode(_currentCenter);
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onPositionChanged(MapPosition position, bool hasGesture) {
    if (position.center != null) {
      _currentCenter = position.center!;
      _debounceTimer?.cancel();
      _debounceTimer = Timer(const Duration(milliseconds: 550), () {
        if (mounted) {
          _reverseGeocode(_currentCenter);
        }
      });
    }
  }

  Future<void> _reverseGeocode(LatLng point) async {
    if (!mounted) return;
    setState(() => _isGeocoding = true);

    try {
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?format=json&lat=${point.latitude}&lon=${point.longitude}&zoom=18&addressdetails=1',
      );
      final res = await http.get(url, headers: {
        'User-Agent': 'MalvoyaConsumerApp/1.0 (support@malvoya.com)',
        'Accept': 'application/json',
      }).timeout(const Duration(seconds: 6));

      if (res.statusCode == 200 && mounted) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final address = data['address'] as Map<String, dynamic>? ?? {};

        final road = address['road'] ?? address['pedestrian'] ?? address['footway'] ?? address['suburb'] ?? 'Street';
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
          } else {
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
        if (_street == 'Scanning map...') {
          _fullAddress = '${point.latitude.toStringAsFixed(4)}° N, ${point.longitude.toStringAsFixed(4)}° E, Helsinki';
        }
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
        'User-Agent': 'MalvoyaConsumerApp/1.0 (support@malvoya.com)',
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
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Address not found. Please drag map to pin location.'), behavior: SnackBarBehavior.floating),
          );
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Network timeout. Drag pin directly on map.'), behavior: SnackBarBehavior.floating),
        );
      }
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  void _confirmAndReturn() {
    HapticFeedback.mediumImpact();
    final result = AddressResult(
      street: _street,
      houseNumber: _houseNumber,
      postalCode: _postalCode,
      city: _city,
      fullAddress: _fullAddress,
      latitude: _currentCenter.latitude,
      longitude: _currentCenter.longitude,
    );
    Navigator.pop(context, result);
  }

  Widget _buildLayerChip(String label, GoogleMapLayer layer, Color cardBg, Color textPrimary, Color borderColor) {
    final isSelected = _selectedLayer == layer;
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        setState(() => _selectedLayer = layer);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primary : cardBg.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppTheme.primary : borderColor,
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
            color: isSelected ? Colors.white : textPrimary,
          ),
        ),
      ),
    );
  }

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
          // 1. Google Maps Multi-Layer Engine (Satellite / Hybrid / Roads / 3D Terrain)
          FlutterMap(
            key: ValueKey(_selectedLayer),
            mapController: _mapController,
            options: MapOptions(
              center: _currentCenter,
              zoom: 16.0,
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
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF17131C),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 10, offset: const Offset(0, 4)),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_isGeocoding)
                          const SizedBox(
                            width: 12, height: 12,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        else
                          const Icon(Icons.touch_app_rounded, color: Colors.white, size: 14),
                        const SizedBox(width: 6),
                        const Text(
                          'Deliver Here',
                          style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  // Pin Marker
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: AppTheme.primaryGradient,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.primary.withValues(alpha: 0.55),
                          blurRadius: 14,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.location_on_rounded, color: Colors.white, size: 24),
                  ),
                  // Pin Point Stem Shadow
                  Container(
                    width: 10,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
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
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: cardBg,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: borderColor),
                            boxShadow: [
                              BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 12, offset: const Offset(0, 4)),
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
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: borderColor),
                            boxShadow: [
                              BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 12, offset: const Offset(0, 4)),
                            ],
                          ),
                          child: Row(
                            children: [
                              const SizedBox(width: 14),
                              const Icon(Icons.search_rounded, color: AppTheme.primary, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  controller: _searchCtrl,
                                  textInputAction: TextInputAction.search,
                                  onSubmitted: _searchAddress,
                                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textPrimary),
                                  decoration: InputDecoration(
                                    hintText: 'Search street, building, city...',
                                    hintStyle: TextStyle(fontSize: 13, color: textSecondary),
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
                                  padding: EdgeInsets.only(right: 12),
                                  child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                                )
                              else if (_searchCtrl.text.isNotEmpty)
                                IconButton(
                                  icon: const Icon(Icons.clear_rounded, size: 16, color: Colors.grey),
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

                  // Google Maps Layer Switcher Pill Row
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    child: Row(
                      children: [
                        _buildLayerChip('🗺️ Hybrid', GoogleMapLayer.hybrid, cardBg, textPrimary, borderColor),
                        const SizedBox(width: 8),
                        _buildLayerChip('🛰️ Satellite', GoogleMapLayer.satellite, cardBg, textPrimary, borderColor),
                        const SizedBox(width: 8),
                        _buildLayerChip('🛣️ Roads', GoogleMapLayer.roadmap, cardBg, textPrimary, borderColor),
                        const SizedBox(width: 8),
                        _buildLayerChip('⛰️ 3D Terrain', GoogleMapLayer.terrain, cardBg, textPrimary, borderColor),
                      ],
                    ),
                  ),
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
                // Open in Native 3D Google Maps / Street View
                GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    LocalNotificationService.openGoogleMaps(
                      lat: _currentCenter.latitude,
                      lng: _currentCenter.longitude,
                      label: _street,
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: borderColor),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 10, offset: const Offset(0, 3)),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.travel_explore_rounded, color: AppTheme.primary, size: 16),
                        const SizedBox(width: 5),
                        Text('3D View', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: textPrimary)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                // Zoom In (+)
                GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    final newZoom = (_mapController.zoom + 1.0).clamp(4.0, 20.0);
                    _mapController.move(_currentCenter, newZoom);
                  },
                  child: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                      border: Border.all(color: borderColor),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 8, offset: const Offset(0, 2)),
                      ],
                    ),
                    child: Icon(Icons.add_rounded, color: textPrimary, size: 20),
                  ),
                ),
                // Zoom Out (-)
                GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    final newZoom = (_mapController.zoom - 1.0).clamp(4.0, 20.0);
                    _mapController.move(_currentCenter, newZoom);
                  },
                  child: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14)),
                      border: Border(
                        left: BorderSide(color: borderColor),
                        right: BorderSide(color: borderColor),
                        bottom: BorderSide(color: borderColor),
                      ),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 8, offset: const Offset(0, 2)),
                      ],
                    ),
                    child: Icon(Icons.remove_rounded, color: textPrimary, size: 20),
                  ),
                ),
                const SizedBox(height: 10),

                // GPS Re-Center Floating Button
                GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    final helsinkiCenter = LatLng(60.1699, 24.9384);
                    _mapController.move(helsinkiCenter, 16.0);
                    _currentCenter = helsinkiCenter;
                    _reverseGeocode(helsinkiCenter);
                  },
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: cardBg,
                      shape: BoxShape.circle,
                      border: Border.all(color: borderColor),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withValues(alpha: 0.14), blurRadius: 10, offset: const Offset(0, 3)),
                      ],
                    ),
                    child: const Icon(Icons.my_location_rounded, color: AppTheme.primary, size: 20),
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
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: borderColor, width: 1.2),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 24, offset: const Offset(0, 8)),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.location_on_rounded, color: AppTheme.primary, size: 20),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _street.isNotEmpty ? _street : 'Pinpoint Location',
                              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: textPrimary),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${_currentCenter.latitude.toStringAsFixed(4)}° N, ${_currentCenter.longitude.toStringAsFixed(4)}° E',
                              style: TextStyle(fontSize: 11, color: textSecondary, fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ),
                      if (_isGeocoding)
                        const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      else
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF248A52).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text('GOOGLE MAPS LIVE', style: TextStyle(color: Color(0xFF248A52), fontSize: 9, fontWeight: FontWeight.w900)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1C1333) : const Color(0xFFF6F3EE),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: isDark ? const Color(0xFF3A3242) : AppTheme.glassBorder),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.home_outlined, color: AppTheme.primary, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _fullAddress,
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: textPrimary),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                        elevation: 2,
                      ),
                      onPressed: _confirmAndReturn,
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
                          SizedBox(width: 8),
                          Text('Confirm Pin Location', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white)),
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
