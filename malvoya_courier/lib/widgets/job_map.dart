import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:malvoya_core/malvoya_core.dart';
import 'package:malvoya_ui/malvoya_ui.dart';
import '../config/theme.dart';
import '../services/courier_telemetry_service.dart';

/// A small OpenStreetMap view of the active job: the shop, the drop-off and the courier's own
/// position, which glides to each new GPS fix instead of jumping. At night (the phone in dark mode)
/// the tiles are darkened with a colour filter so the screen does not glare. Navigation itself is
/// handed to Google Maps or Waze; this map is only for orientation.
class JobMap extends StatefulWidget {
  final LatLng store;
  final LatLng? dropOff;

  /// Before pickup the shop is the target, afterwards the drop-off.
  final bool towardsDropOff;
  final double height;
  const JobMap({super.key, required this.store, this.dropOff, this.towardsDropOff = false, this.height = 190});

  @override
  State<JobMap> createState() => _JobMapState();
}

class _JobMapState extends State<JobMap> {
  final _map = MapController();
  final _telemetry = CourierTelemetryService();
  bool _ready = false;

  LatLng? get _me {
    final p = _telemetry.lastPosition;
    return p == null ? null : LatLng(p.latitude, p.longitude);
  }

  List<LatLng> get _points => [widget.store, if (widget.dropOff != null) widget.dropOff!, if (_me != null) _me!];

  CameraFit get _fit => _points.length == 1
      ? CameraFit.coordinates(coordinates: [widget.store, LatLng(widget.store.latitude + 0.004, widget.store.longitude + 0.004)], padding: const EdgeInsets.all(MSpace.x4l))
      : CameraFit.coordinates(coordinates: _points, padding: const EdgeInsets.all(MSpace.x4l), maxZoom: 17);

  void _recentre() {
    if (_ready) _map.fitCamera(_fit);
  }

  @override
  void didUpdateWidget(JobMap old) {
    super.didUpdateWidget(old);
    if (old.dropOff != widget.dropOff || old.store != widget.store || old.towardsDropOff != widget.towardsDropOff) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _recentre());
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    return Semantics(
      label: tr(context, 'Map with the shop, the drop-off and your position', 'Kartta, jossa kauppa, toimituskohde ja sijaintisi'),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        child: SizedBox(
          height: widget.height,
          child: Stack(children: [
            FlutterMap(
              mapController: _map,
              options: MapOptions(
                initialCameraFit: _fit,
                onMapReady: () => _ready = true,
                // Pinch and double-tap only, so the delivery screen still scrolls with one finger
                interactionOptions: const InteractionOptions(flags: InteractiveFlag.pinchZoom | InteractiveFlag.doubleTapZoom),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.malvoya.courier',
                  maxZoom: 19,
                  tileBuilder: dark ? darkModeTileBuilder : null,
                ),
                MarkerLayer(markers: [
                  Marker(point: widget.store, width: 36, height: 36, child: _pin(Icons.storefront_rounded, AppTheme.textPrimary, !widget.towardsDropOff)),
                  if (widget.dropOff != null)
                    Marker(point: widget.dropOff!, width: 36, height: 36, child: _pin(Icons.location_on_rounded, AppTheme.primary, widget.towardsDropOff)),
                ]),
                // The courier's own position, animated between GPS fixes
                ListenableBuilder(
                  listenable: _telemetry,
                  builder: (context, _) {
                    final me = _me;
                    if (me == null) return const SizedBox.shrink();
                    return TweenAnimationBuilder<LatLng>(
                      tween: _LatLngTween(begin: me, end: me),
                      duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 900),
                      curve: Curves.easeInOut,
                      builder: (context, at, _) => MarkerLayer(markers: [Marker(point: at, width: 28, height: 28, child: const _MeDot())]),
                    );
                  },
                ),
                const SimpleAttributionWidget(source: Text('OpenStreetMap contributors')),
              ],
            ),
            Positioned(
              top: 8,
              right: 8,
              child: Material(
                color: AppTheme.surface,
                shape: const CircleBorder(),
                elevation: 2,
                child: IconButton(
                  tooltip: tr(context, 'Show the whole route', 'Näytä koko reitti'),
                  constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                  onPressed: _recentre,
                  icon: const Icon(Icons.center_focus_strong_rounded, color: AppTheme.textPrimary),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _pin(IconData icon, Color color, bool target) => Container(
        decoration: BoxDecoration(color: color, shape: BoxShape.circle, border: Border.all(color: target ? AppTheme.sunshine : AppTheme.surface, width: 3)),
        child: Icon(icon, color: AppTheme.onPrimary, size: 18),
      );
}

class _MeDot extends StatelessWidget {
  const _MeDot();

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: MPalette.locationBlue,
          shape: BoxShape.circle,
          border: Border.all(color: AppTheme.surface, width: 3),
          boxShadow: [BoxShadow(color: MPalette.locationBlue.withValues(alpha: 0.33), blurRadius: 10, spreadRadius: 4)],
        ),
      );
}

/// TweenAnimationBuilder starts each new animation from the value currently shown, so giving it
/// the new fix as both ends makes the dot glide from where it is to the new position.
class _LatLngTween extends Tween<LatLng> {
  _LatLngTween({required LatLng begin, required LatLng end}) : super(begin: begin, end: end);

  @override
  LatLng lerp(double t) => LatLng(
        begin!.latitude + (end!.latitude - begin!.latitude) * t,
        begin!.longitude + (end!.longitude - begin!.longitude) * t,
      );
}
