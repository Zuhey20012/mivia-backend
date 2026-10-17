import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/theme.dart';
import 'haptics.dart';
import 'strings.dart';

/// The navigation app the courier hands a route to.
enum NavApp { googleMaps, waze, system }

/// Hands a destination to a navigation app with turn-by-turn directions. The courier picks Google
/// Maps, Waze or the phone's default maps app once; the choice is remembered on this phone and can
/// be changed from the account sheet or by long-pressing "Navigate".
class NavApps {
  NavApps._();
  static const _key = 'navApp';

  static Future<NavApp?> saved() async {
    try {
      final name = (await SharedPreferences.getInstance()).getString(_key);
      return NavApp.values.where((a) => a.name == name).firstOrNull;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _save(NavApp? app) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      app == null ? await prefs.remove(_key) : await prefs.setString(_key, app.name);
    } catch (_) {}
  }

  static String label(BuildContext context, NavApp app) => switch (app) {
        NavApp.googleMaps => 'Google Maps',
        NavApp.waze => 'Waze',
        NavApp.system => Platform.isIOS ? 'Apple Maps' : tr(context, 'Phone\'s maps app', 'Puhelimen karttasovellus'),
      };

  /// Asks which app to use (and whether to remember it). Null = cancelled.
  static Future<NavApp?> choose(BuildContext context, {bool offerRemember = true}) async {
    Haptics.select();
    var remember = true;
    final current = await saved();
    if (!context.mounted) return null;
    final picked = await showModalBottomSheet<NavApp>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(tr(ctx, 'Navigate with', 'Navigoi sovelluksella'), style: AppTheme.display(size: 20)),
            ),
            for (final app in NavApp.values)
              ListTile(
                minTileHeight: 56,
                contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                leading: Icon(switch (app) {
                  NavApp.googleMaps => Icons.map_outlined,
                  NavApp.waze => Icons.directions_car_outlined,
                  NavApp.system => Icons.explore_outlined,
                }),
                title: Text(label(ctx, app), style: const TextStyle(fontWeight: FontWeight.w700)),
                trailing: current == app ? const Icon(Icons.check_rounded, color: AppTheme.success) : null,
                onTap: () => Navigator.pop(ctx, app),
              ),
            if (offerRemember)
              CheckboxListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                value: remember,
                onChanged: (v) => setSheet(() => remember = v ?? true),
                title: Text(tr(ctx, 'Remember my choice', 'Muista valintani')),
                subtitle: Text(tr(ctx, 'Change it any time in your account, or long-press Navigate.', 'Voit vaihtaa sen milloin vain tililtäsi tai painamalla Navigoi-painiketta pitkään.')),
                controlAffinity: ListTileControlAffinity.leading,
              ),
            const SizedBox(height: 8),
          ]),
        ),
      ),
    );
    if (picked != null && (remember || !offerRemember)) await _save(picked);
    return picked;
  }

  /// Opens turn-by-turn directions to the point (or the address when there is no point), for a
  /// bicycle in Google Maps. Falls back to the next app if the chosen one is not installed.
  /// Returns false if no app could be opened.
  static Future<bool> navigate(BuildContext context, {double? lat, double? lng, String? address, bool ask = false}) async {
    final hasPoint = lat != null && lng != null;
    final text = (address ?? '').trim();
    if (!hasPoint && text.isEmpty) return false;
    var app = ask ? null : await saved();
    if (app == null) {
      if (!context.mounted) return false;
      app = await choose(context);
      if (app == null) return true; // cancelled: nothing to report
    }
    Haptics.select();
    final q = hasPoint ? '$lat,$lng' : Uri.encodeComponent(text);
    final google = <Uri>[
      if (Platform.isAndroid) Uri.parse('google.navigation:q=$q&mode=b'),
      if (Platform.isIOS) Uri.parse('comgooglemaps://?daddr=$q&directionsmode=bicycling'),
      Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$q&travelmode=bicycling&dir_action=navigate'),
    ];
    final waze = <Uri>[
      Uri.parse(hasPoint ? 'https://waze.com/ul?ll=$q&navigate=yes' : 'https://waze.com/ul?q=$q&navigate=yes'),
    ];
    final system = <Uri>[
      if (Platform.isIOS) Uri.parse('https://maps.apple.com/?daddr=$q&dirflg=d'),
      if (Platform.isAndroid) Uri.parse(hasPoint ? 'geo:$lat,$lng?q=$lat,$lng' : 'geo:0,0?q=$q'),
    ];
    final order = switch (app) {
      NavApp.googleMaps => [...google, ...system],
      NavApp.waze => [...waze, ...google, ...system],
      NavApp.system => [...system, ...google],
    };
    for (final uri in order) {
      try {
        if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return true;
      } catch (_) {}
    }
    return false;
  }
}
