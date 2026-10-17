import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/theme.dart';
import 'haptics.dart';
import 'push_service.dart';
import 'strings.dart';

/// Why the app is about to ask for notifications; each moment gets its own words.
enum PrimerReason { order, storeAlert }

/// Explains what notifications are for before the phone's own permission dialog appears, at a
/// moment where they make sense (right after the first order, or when asking for a store alert).
/// Never at launch. After "Not now" it does not ask again by itself.
class NotificationPrimer {
  const NotificationPrimer._();

  static const _askedKey = 'push_primer_shown';

  /// Shows the priming sheet unless notifications are already on, or (for the automatic moments)
  /// it was already shown once. Returns whether notifications are on afterwards.
  static Future<bool> maybeAsk(BuildContext context, {PrimerReason reason = PrimerReason.order, bool force = false}) async {
    final push = PushService.instance;
    if (await push.allowed) return true;
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
      if (!force && (prefs.getBool(_askedKey) ?? false)) return false;
    } catch (_) {}
    if (!context.mounted) return false;
    final yes = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _PrimerSheet(reason: reason),
    );
    try {
      await prefs?.setBool(_askedKey, true);
    } catch (_) {}
    if (yes != true) return false;
    final on = await push.enable();
    if (!on && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(tr(context, 'Notifications are off for Malvoya. You can turn them on in your phone’s settings.',
            'Malvoyan ilmoitukset ovat pois päältä. Voit laittaa ne päälle puhelimen asetuksista.')),
      ));
    }
    return on;
  }
}

class _PrimerSheet extends StatelessWidget {
  final PrimerReason reason;
  const _PrimerSheet({required this.reason});

  @override
  Widget build(BuildContext context) {
    final order = reason == PrimerReason.order;
    final muted = AppTheme.secondaryText(context);
    Widget point(IconData icon, String text) => Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Row(children: [
            Icon(icon, size: 20, color: AppTheme.isDarkMode(context) ? const Color(0xFFC9A3DD) : AppTheme.primary),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: TextStyle(fontSize: 14.5, color: AppTheme.primaryText(context)))),
          ]),
        );

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(color: AppTheme.pastel(context, AppTheme.sunshineLight, AppTheme.sunshine), shape: BoxShape.circle),
                child: const Icon(Icons.notifications_active_rounded, size: 36, color: Color(0xFF8A5A00)),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              order
                  ? tr(context, 'Get updates when your order is on its way', 'Saat tiedon, kun tilauksesi on matkalla')
                  : tr(context, 'Hear when a shop opens near you', 'Kuule, kun lähellesi avautuu kauppa'),
              style: AppTheme.display(context, size: 22),
            ),
            const SizedBox(height: 6),
            Text(
              tr(context, 'Only about your orders and stores you ask about. No ads.', 'Vain tilauksistasi ja kaupoista, joista kysyit. Ei mainoksia.'),
              style: TextStyle(fontSize: 14, color: muted, height: 1.4),
            ),
            if (order) ...[
              point(Icons.storefront_rounded, tr(context, 'The shop accepted your order', 'Kauppa hyväksyi tilauksesi')),
              point(Icons.pedal_bike_rounded, tr(context, 'Your courier is on the way or at the door', 'Kuriiri on matkalla tai ovellasi')),
              point(Icons.chat_bubble_outline_rounded, tr(context, 'A message from your courier', 'Viesti kuriiriltasi')),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
                onPressed: () {
                  Haptics.medium();
                  Navigator.pop(context, true);
                },
                child: Text(tr(context, 'Turn on notifications', 'Laita ilmoitukset päälle')),
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                style: TextButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                onPressed: () => Navigator.pop(context, false),
                child: Text(tr(context, 'Not now', 'Ei nyt')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
