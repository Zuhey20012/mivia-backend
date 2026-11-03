import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:malvoya_core/malvoya_core.dart';
import 'package:malvoya_ui/malvoya_ui.dart';
import '../config/theme.dart';
import '../core/route_path.dart';

/// The live delivery map: shop and home pins, the street route of the current stage split at the
/// courier into the part already travelled (solid Malva) and the part ahead (dotted), and the
/// courier marker moving along the street between position updates, turned to its heading. The
/// camera eases along with the courier until the user moves the map themselves.
///
/// Performance: one [AnimationController] drives every frame (marker, travelled line, pulses and
/// camera), only while something moves; only the route, pulse and courier layers rebuild on a
/// frame. With "remove animations" on the marker jumps, nothing pulses and the camera cuts.
///
/// Without a [route] (an older server, or a 404) it behaves as before 2.17: a dashed line from
/// the courier to home and a straight glide between positions.
class LiveRouteMap extends StatefulWidget {
  final LatLng? shop;
  final LatLng? home;

  /// The courier's latest reported position (null while unknown).
  final LatLng? courier;

  /// The current stage's street route, or null when there is none.
  final RoutePath? route;

  /// How far along [route] the courier is (metres), or null when the courier is not on it
  /// (no courier yet, a preview route, or more than ~80 m off the street).
  final double? courierAlong;

  /// How long the marker takes to reach a new position: about the time between two updates, so
  /// it keeps moving instead of hopping and waiting.
  final Duration moveDuration;
  final bool pulseShop;
  final bool pulseHome;
  final IconData courierIcon;

  /// Space the camera keeps clear around the route (e.g. the bottom sheet covering the map).
  final EdgeInsets cameraPadding;

  /// Space for the map's own button at the top (e.g. under a transparent app bar).
  final double topInset;

  const LiveRouteMap({
    super.key,
    required this.shop,
    required this.home,
    required this.courier,
    required this.route,
    required this.courierAlong,
    required this.courierIcon,
    this.moveDuration = const Duration(milliseconds: 1400),
    this.pulseShop = false,
    this.pulseHome = false,
    this.cameraPadding = const EdgeInsets.all(56),
    this.topInset = 0,
  });

  @override
  State<LiveRouteMap> createState() => _LiveRouteMapState();
}

class _LiveRouteMapState extends State<LiveRouteMap> with SingleTickerProviderStateMixin {
  final _map = MapController();
  bool _ready = false;

  /// The one frame driver. Its value is not used: every motion is timed against [_sw], so the
  /// marker, camera and pulses share one ticker and it can stop as soon as everything is still.
  late final _frames = AnimationController(vsync: this, duration: const Duration(seconds: 1))..addListener(_onFrame);
  final _sw = Stopwatch()..start();

  // Marker motion: along the route ([_fromAlong] → [_toAlong]) or, off the route, in a straight line
  double? _fromAlong, _toAlong;
  LatLng? _fromPos, _toPos;
  int _moveStartMs = 0;
  int _moveMs = 1;

  // Camera easing
  bool _follow = true;
  LatLng? _camFrom, _camTo;
  double _zoomFrom = 0, _zoomTo = 0;
  int _camStartMs = 0;
  static const _camMs = 900;
  bool _fittedWithCourier = false;

  double _heading = 0;

  bool get _still => reduceMotion(context);
  int get _now => _sw.elapsedMilliseconds;
  bool get _snapped => widget.route != null && widget.courierAlong != null;

  @override
  void initState() {
    super.initState();
    _toAlong = _fromAlong = widget.courierAlong;
    _toPos = _fromPos = widget.courier;
    final r = widget.route;
    if (r != null && widget.courierAlong != null) _heading = r.headingAt(widget.courierAlong!);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _kick();
  }

  @override
  void didUpdateWidget(LiveRouteMap old) {
    super.didUpdateWidget(old);
    final routeChanged = !identical(old.route, widget.route);
    final along = widget.courierAlong;
    var moved = false;
    if (_snapped) {
      if (routeChanged || _toAlong == null || old.courierAlong == null) {
        // A new stage's route (or the first fix on it): start there instead of sliding along a line
        // that no longer exists
        _fromAlong = _toAlong = along;
        if (!routeChanged && _follow) WidgetsBinding.instance.addPostFrameCallback((_) => _followCourier());
      } else if (along != old.courierAlong) {
        _fromAlong = _shownAlong;
        _toAlong = along;
        moved = true;
      }
      _fromPos = _toPos = widget.courier;
    } else {
      _fromAlong = _toAlong = null;
      if (widget.courier != null && widget.courier != old.courier) {
        final from = _shownPos ?? widget.courier;
        final b = from == null ? null : RoutePath.bearing(from, widget.courier!);
        if (b != null && RoutePath.metres(from!, widget.courier!) > 3) _heading = b;
        _fromPos = from;
        _toPos = widget.courier;
        moved = true;
      } else if (widget.courier == null) {
        _fromPos = _toPos = null;
      }
    }
    if (moved) {
      _moveStartMs = _now;
      _moveMs = _still ? 1 : widget.moveDuration.inMilliseconds.clamp(300, 15000);
      if (_still) {
        _fromAlong = _toAlong;
        _fromPos = _toPos;
      }
      final firstFix = old.courier == null && widget.courier != null;
      if (firstFix && !_fittedWithCourier) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _fitAll());
      } else if (_follow) {
        _followCourier();
      }
    } else if (routeChanged && _follow) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _fitAll(keepFollow: true));
    }
    _kick();
  }

  @override
  void dispose() {
    _frames.dispose();
    _map.dispose();
    super.dispose();
  }

  // ── Frame clock ───────────────────────────────────────────────────────────

  double get _moveT => ((_now - _moveStartMs) / _moveMs).clamp(0.0, 1.0);

  /// Long glides run at an even speed (as a courier rides); short ones ease in and out.
  double get _moveEased => _moveMs > 2000 ? _moveT : Curves.easeInOut.transform(_moveT);

  bool get _moving => _moveT < 1;
  bool get _camMoving => _camTo != null && _now - _camStartMs < _camMs;
  bool get _pulsing => !_still && ((widget.pulseShop && widget.shop != null) || (widget.pulseHome && widget.home != null));

  void _kick() {
    if (!mounted) return;
    if ((_moving || _camMoving || _pulsing) && !_frames.isAnimating) _frames.repeat();
  }

  void _onFrame() {
    if (_camTo != null && _ready) {
      final t = Curves.easeInOutCubic.transform(((_now - _camStartMs) / _camMs).clamp(0.0, 1.0));
      final a = _camFrom!, b = _camTo!;
      _map.move(LatLng(a.latitude + (b.latitude - a.latitude) * t, a.longitude + (b.longitude - a.longitude) * t), _zoomFrom + (_zoomTo - _zoomFrom) * t);
      if (t >= 1) _camTo = null;
    }
    if (!_moving && !_camMoving && !_pulsing) _frames.stop();
  }

  // ── Where things are drawn now ────────────────────────────────────────────

  double? get _shownAlong {
    final a = _fromAlong, b = _toAlong;
    if (a == null || b == null) return b;
    return a + (b - a) * _moveEased;
  }

  LatLng? get _shownPos {
    final r = widget.route;
    final along = _shownAlong;
    if (_snapped && r != null && along != null) return r.pointAt(along);
    final a = _fromPos, b = _toPos;
    if (a == null || b == null) return b;
    final t = _moveEased;
    return LatLng(a.latitude + (b.latitude - a.latitude) * t, a.longitude + (b.longitude - a.longitude) * t);
  }

  double get _shownHeading {
    final r = widget.route;
    final along = _shownAlong;
    if (_snapped && r != null && along != null) _heading = r.headingAt(along);
    return _heading;
  }

  // ── Camera ────────────────────────────────────────────────────────────────

  LatLng? get _destination => widget.route?.end ?? widget.home;

  List<LatLng> get _allPoints => [
        if (widget.shop != null) widget.shop!,
        if (widget.home != null) widget.home!,
        if (widget.courier != null) widget.courier!,
        ...?widget.route?.points,
      ];

  MapCamera? _fitted(List<LatLng> points) {
    if (!_ready || points.isEmpty) return null;
    try {
      return CameraFit.bounds(bounds: LatLngBounds.fromPoints(points), padding: widget.cameraPadding, maxZoom: 16.5).fit(_map.camera);
    } catch (_) {
      return null;
    }
  }

  void _easeTo(MapCamera? target) {
    if (target == null) return;
    if (_still) {
      _camTo = null;
      _map.move(target.center, target.zoom);
      return;
    }
    _camFrom = _map.camera.center;
    _zoomFrom = _map.camera.zoom;
    _camTo = target.center;
    _zoomTo = target.zoom;
    _camStartMs = _now;
    _kick();
  }

  /// Keeps the courier and where it is heading in view.
  void _followCourier() {
    final to = _snapped ? widget.route!.pointAt(_toAlong ?? 0) : _toPos;
    final dest = _destination;
    if (to == null) return;
    _easeTo(_fitted([to, if (dest != null) dest]));
  }

  void _fitAll({bool keepFollow = false}) {
    if (!mounted) return;
    if (!keepFollow) _follow = true;
    if (widget.courier != null) _fittedWithCourier = true;
    _easeTo(_fitted(_allPoints));
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  Widget _pin(IconData icon, Color color, String label) => Semantics(
        label: label,
        child: Container(
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: MPalette.white, width: 3),
            boxShadow: [BoxShadow(color: MPalette.night.withValues(alpha: 0.26), blurRadius: 6)],
          ),
          child: Icon(icon, color: AppTheme.onBrand, size: 18),
        ),
      );

  Widget _courierMarker(double heading) => Semantics(
        label: tr(context, 'Courier', 'Kuriiri'),
        child: Stack(alignment: Alignment.center, children: [
          // The heading: a small arrow on the rim, turned with the direction of travel
          Transform.rotate(angle: heading, child: const CustomPaint(size: Size(60, 60), painter: _HeadingPainter(AppTheme.lingon))),
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppTheme.lingon,
              shape: BoxShape.circle,
              border: Border.all(color: MPalette.white, width: 3),
              boxShadow: [BoxShadow(color: MPalette.night.withValues(alpha: 0.3), blurRadius: 8)],
            ),
            child: Icon(widget.courierIcon, color: AppTheme.onBrand, size: 20),
          ),
        ]),
      );

  List<Polyline> _routeLines(LatLng? courier) {
    const brand = AppTheme.primary;
    final r = widget.route;
    final along = _shownAlong;
    if (r == null) {
      // Before 2.17 (or no route): a dashed line from the courier to home
      if (courier == null || widget.home == null) return const [];
      return [
        Polyline(
          points: [courier, widget.home!],
          strokeWidth: 4,
          color: brand.withValues(alpha: 0.6),
          pattern: StrokePattern.dashed(segments: const [10, 8]),
        ),
      ];
    }
    final ahead = Polyline(
      points: _snapped && along != null ? r.slice(along, r.length) : r.points,
      strokeWidth: 5,
      color: brand.withValues(alpha: 0.7),
      pattern: const StrokePattern.dotted(spacingFactor: 1.8),
    );
    if (!_snapped || along == null || along <= 0) return [ahead];
    return [
      ahead,
      Polyline(
        points: r.slice(0, along),
        strokeWidth: 5,
        color: brand,
        borderStrokeWidth: 1.5,
        borderColor: MPalette.white,
        strokeCap: StrokeCap.round,
        strokeJoin: StrokeJoin.round,
      ),
    ];
  }

  Marker _pulse(LatLng at, Color color, double phase) {
    final eased = Curves.easeOut.transform(phase);
    return Marker(
      point: at,
      width: 96,
      height: 96,
      child: IgnorePointer(
        child: Center(
          child: Container(
            width: 30 + 66 * eased,
            height: 30 + 66 * eased,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.22 * (1 - eased)),
              border: Border.all(color: color.withValues(alpha: 0.5 * (1 - eased)), width: 2),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final points = _allPoints;
    final start = points.isEmpty ? const LatLng(60.1699, 24.9384) : points.first;
    return Stack(children: [
      FlutterMap(
        mapController: _map,
        options: MapOptions(
          initialCenter: start,
          initialZoom: 14,
          maxZoom: 18,
          // North stays up, so the courier's heading arrow reads like a compass
          interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
          initialCameraFit: points.length > 1
              ? CameraFit.bounds(bounds: LatLngBounds.fromPoints(points), padding: widget.cameraPadding, maxZoom: 16.5)
              : null,
          onMapReady: () {
            _ready = true;
            if (widget.courier != null) _fittedWithCourier = true;
          },
          onPositionChanged: (camera, hasGesture) {
            // The user looks around: stop following until they ask for the whole route again
            if (hasGesture && _follow) {
              _follow = false;
              _camTo = null;
            }
          },
        ),
        children: [
          TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.malvoya.customer'),
          // Only these layers repaint on a frame
          AnimatedBuilder(
            animation: _frames,
            builder: (context, _) => PolylineLayer(polylines: _routeLines(_shownPos)),
          ),
          if (_pulsing)
            AnimatedBuilder(
              animation: _frames,
              builder: (context, _) {
                final phase = (_now % 1800) / 1800;
                return MarkerLayer(markers: [
                  if (widget.pulseShop && widget.shop != null) _pulse(widget.shop!, AppTheme.primary, phase),
                  if (widget.pulseHome && widget.home != null) _pulse(widget.home!, AppTheme.success, phase),
                ]);
              },
            ),
          MarkerLayer(markers: [
            if (widget.shop != null)
              Marker(point: widget.shop!, width: 38, height: 38, child: _pin(Icons.storefront_rounded, AppTheme.primary, tr(context, 'Shop', 'Kauppa'))),
            if (widget.home != null)
              Marker(point: widget.home!, width: 38, height: 38, child: _pin(Icons.home_rounded, AppTheme.success, tr(context, 'Your address', 'Osoitteesi'))),
          ]),
          AnimatedBuilder(
            animation: _frames,
            builder: (context, _) {
              final courier = _shownPos;
              if (courier == null) return const SizedBox.shrink();
              return MarkerLayer(markers: [Marker(point: courier, width: 60, height: 60, child: _courierMarker(_shownHeading))]);
            },
          ),
          // Top left, so a bottom sheet over the map never hides the attribution
          Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: EdgeInsets.fromLTRB(MSpace.sm, MSpace.sm + widget.topInset, MSpace.sm, MSpace.sm),
              child: const Text('© OpenStreetMap', style: TextStyle(fontSize: MTextSize.caption, color: AppTheme.ink)),
            ),
          ),
        ],
      ),
      if (points.length > 1)
        Positioned(
          top: MSpace.sm + widget.topInset,
          right: MSpace.sm,
          child: Material(
            color: MPalette.white,
            shape: const CircleBorder(),
            elevation: 2,
            child: IconButton(
              tooltip: tr(context, 'Show the whole route', 'Näytä koko reitti'),
              icon: const Icon(Icons.center_focus_strong_rounded, color: AppTheme.ink),
              onPressed: () {
                Haptics.selection();
                _fitAll();
              },
            ),
          ),
        ),
    ]);
  }
}

/// A small arrow pointing up from the rim of the courier marker (rotated by the caller).
class _HeadingPainter extends CustomPainter {
  final Color color;
  const _HeadingPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final tip = c.dy - size.height / 2 + 1;
    final path = Path()
      ..moveTo(c.dx, tip)
      ..lineTo(c.dx + 7, tip + 10)
      ..lineTo(c.dx - 7, tip + 10)
      ..close();
    canvas.drawPath(path, Paint()..color = MPalette.white);
    canvas.drawPath(path.shift(const Offset(0, 1.5)), Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _HeadingPainter old) => old.color != color;
}
