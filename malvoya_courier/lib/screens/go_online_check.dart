import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import '../config/theme.dart';
import '../core/location_disclosure.dart';
import '../core/strings.dart';

/// Something on the phone that gets in the way of delivering while online.
enum GoOnlineIssue { locationService, locationPermission, preciseLocation, notifications, battery }

/// Checks before going online: the location disclosure and permission first, then a short list
/// of anything else that would stop jobs or tracking from working, each with a "Fix" button.
///
/// Location (on and allowed) is required. Precise location, notifications and battery
/// optimisation are warnings: the courier may go online anyway.
/// Background location ("All the time") is not needed: `CourierTelemetryService` runs as a
/// visible foreground service and the manifest has no ACCESS_BACKGROUND_LOCATION.
class GoOnlineCheck {
  GoOnlineCheck._();

  static const _battery = MethodChannel('com.malvoya.courier/battery');

  static bool isCritical(GoOnlineIssue i) => i == GoOnlineIssue.locationService || i == GoOnlineIssue.locationPermission;

  /// True when the caller may go online now.
  static Future<bool> run(BuildContext context) async {
    if (!await LocationDisclosure.prepare(context)) return false;
    final issues = await problems();
    if (issues.isEmpty) return true;
    if (!context.mounted) return false;
    final go = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _GoOnlineSheet(initial: issues),
    );
    return go == true;
  }

  /// What is wrong right now. Anything this phone cannot check is skipped.
  static Future<List<GoOnlineIssue>> problems() async {
    final found = <GoOnlineIssue>[];
    try {
      if (!await Geolocator.isLocationServiceEnabled()) found.add(GoOnlineIssue.locationService);
    } catch (_) {}
    try {
      final permission = await Geolocator.checkPermission();
      if (!LocationDisclosure.isGranted(permission)) {
        found.add(GoOnlineIssue.locationPermission);
      } else if (await Geolocator.getLocationAccuracy() == LocationAccuracyStatus.reduced) {
        found.add(GoOnlineIssue.preciseLocation);
      }
    } catch (_) {}
    try {
      final settings = await FirebaseMessaging.instance.getNotificationSettings();
      if (settings.authorizationStatus == AuthorizationStatus.denied) found.add(GoOnlineIssue.notifications);
    } catch (_) {}
    if (Platform.isAndroid) {
      try {
        if (await _battery.invokeMethod<bool>('isIgnoringBatteryOptimizations') == false) found.add(GoOnlineIssue.battery);
      } catch (_) {}
    }
    return found;
  }

  /// Opens whatever fixes [issue]. The sheet checks again when the courier comes back.
  static Future<void> fix(BuildContext context, GoOnlineIssue issue) async {
    switch (issue) {
      case GoOnlineIssue.locationService:
        await Geolocator.openLocationSettings();
      case GoOnlineIssue.locationPermission:
        if (await Geolocator.checkPermission() == LocationPermission.deniedForever) {
          await Geolocator.openAppSettings();
        } else if (context.mounted) {
          // The disclosure always comes right before Android's prompt
          await LocationDisclosure.prepare(context);
        }
      case GoOnlineIssue.preciseLocation:
        await Geolocator.openAppSettings();
      case GoOnlineIssue.notifications:
        try {
          final s = await FirebaseMessaging.instance.requestPermission();
          if (s.authorizationStatus != AuthorizationStatus.denied) return;
        } catch (_) {}
        await Geolocator.openAppSettings();
      case GoOnlineIssue.battery:
        var opened = false;
        try {
          opened = await _battery.invokeMethod<bool>('openBatteryOptimizationSettings') ?? false;
        } catch (_) {}
        if (!opened) await Geolocator.openAppSettings();
    }
  }
}

class _GoOnlineSheet extends StatefulWidget {
  final List<GoOnlineIssue> initial;

  const _GoOnlineSheet({required this.initial});

  @override
  State<_GoOnlineSheet> createState() => _GoOnlineSheetState();
}

class _GoOnlineSheetState extends State<_GoOnlineSheet> with WidgetsBindingObserver {
  late List<GoOnlineIssue> _issues = widget.initial;
  GoOnlineIssue? _fixing;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Back from the phone's settings: check again
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _recheck();
  }

  Future<void> _recheck() async {
    final issues = await GoOnlineCheck.problems();
    if (mounted) setState(() => _issues = issues);
  }

  Future<void> _fix(GoOnlineIssue issue) async {
    HapticFeedback.selectionClick();
    setState(() => _fixing = issue);
    await GoOnlineCheck.fix(context, issue);
    if (!mounted) return;
    setState(() => _fixing = null);
    await _recheck();
  }

  (IconData, String, String) _copy(GoOnlineIssue i) => switch (i) {
        GoOnlineIssue.locationService => (
            Icons.location_off_outlined,
            tr(context, 'Location is off', 'Sijainti on pois päältä'),
            tr(context, 'Turn on location (GPS) on your phone. You need it to be online.',
                'Laita puhelimen sijainti (GPS) päälle. Sitä tarvitaan, kun olet linjoilla.'),
          ),
        GoOnlineIssue.locationPermission => (
            Icons.location_disabled_outlined,
            tr(context, 'Location is not allowed', 'Sijaintia ei ole sallittu'),
            tr(context,
                'Allow location for Malvoya Courier. Allowing it while the app is in use is enough: the "online" notification keeps sharing on while you are online, so "All the time" is not needed.',
                'Salli sijainti Malvoya Courierille. Riittää, että sallit sen sovelluksen ollessa käytössä: linjoilla-ilmoitus pitää jakamisen päällä, joten "Aina"-asetusta ei tarvita.'),
          ),
        GoOnlineIssue.preciseLocation => (
            Icons.my_location_outlined,
            tr(context, 'Precise location is off', 'Tarkka sijainti on pois päältä'),
            tr(context,
                'Checking in at the shop needs your position within 300 m, and the customer follows you on a map. Turn on precise location for Malvoya Courier.',
                'Kaupalle ilmoittautuminen vaatii sijaintisi 300 metrin tarkkuudella, ja asiakas seuraa sinua kartalla. Laita tarkka sijainti päälle Malvoya Courierille.'),
          ),
        GoOnlineIssue.notifications => (
            Icons.notifications_off_outlined,
            tr(context, 'Notifications are off', 'Ilmoitukset ovat pois päältä'),
            tr(context, 'You will not hear about new delivery jobs near you while the app is in the background.',
                'Et kuule uusista keikoista lähelläsi, kun sovellus on taustalla.'),
          ),
        GoOnlineIssue.battery => (
            Icons.battery_alert_outlined,
            tr(context, 'Battery saving may stop location sharing', 'Virransäästö voi katkaista sijainnin jakamisen'),
            tr(context,
                'Some phones stop background apps to save battery, and the customer could lose track of you. In the list that opens, find Malvoya Courier and turn battery optimisation off for it.',
                'Jotkin puhelimet pysäyttävät taustalla olevia sovelluksia virran säästämiseksi, jolloin asiakas ei ehkä enää näe sinua. Etsi avautuvasta listasta Malvoya Courier ja poista akun optimointi siltä.'),
          ),
      };

  @override
  Widget build(BuildContext context) {
    final blocked = _issues.any(GoOnlineCheck.isCritical);
    final String goLabel;
    if (blocked) {
      goLabel = tr(context, 'Fix location to go online', 'Korjaa sijainti mennäksesi linjoille');
    } else if (_issues.isEmpty) {
      goLabel = tr(context, 'Go online', 'Mene linjoille');
    } else {
      goLabel = tr(context, 'Go online anyway', 'Mene linjoille silti');
    }
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr(context, 'Before you go online', 'Ennen kuin menet linjoille'), style: AppTheme.display(size: 22)),
          const SizedBox(height: 6),
          Text(
            _issues.isEmpty
                ? tr(context, 'All set.', 'Kaikki kunnossa.')
                : blocked
                    ? tr(context, 'Location must be on and allowed to go online.', 'Sijainnin pitää olla päällä ja sallittu, jotta voit mennä linjoille.')
                    : tr(context, 'You can go online, but these may cause problems during deliveries.',
                        'Voit mennä linjoille, mutta nämä voivat aiheuttaa ongelmia toimitusten aikana.'),
            style: const TextStyle(color: AppTheme.textSecondary, height: 1.4),
          ),
          const SizedBox(height: 8),
          for (final issue in _issues) _row(issue),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: blocked ? null : () => Navigator.pop(context, true),
              child: Text(goLabel, textAlign: TextAlign.center),
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: TextButton(
              style: TextButton.styleFrom(minimumSize: const Size(64, 48)),
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr(context, 'Cancel', 'Peruuta')),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _row(GoOnlineIssue issue) {
    final (icon, title, body) = _copy(issue);
    final critical = GoOnlineCheck.isCritical(issue);
    final color = critical ? const Color(0xFFD93025) : const Color(0xFF8A5A00);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: critical ? const Color(0xFFFDECEA) : AppTheme.sunshineLight,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(fontWeight: FontWeight.w800, color: color)),
              const SizedBox(height: 2),
              Text(body, style: const TextStyle(fontSize: 13, height: 1.4, color: AppTheme.textPrimary)),
            ]),
          ),
        ]),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(minimumSize: const Size(96, 48)),
            onPressed: _fixing == null ? () => _fix(issue) : null,
            child: _fixing == issue
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(tr(context, 'Fix', 'Korjaa')),
          ),
        ),
      ]),
    );
  }
}
