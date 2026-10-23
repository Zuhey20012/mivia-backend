import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../api/api_client.dart';
import '../i18n/app_language.dart';

/// Asks the server on start-up (and when the app comes back to the front after 5 minutes) whether
/// this build is still supported and whether Malvoya is in maintenance (`GET /app-config`).
///
/// If the server cannot be reached the app simply opens: the gate never locks anyone out by itself.
/// Wrap `MaterialApp.builder`'s child with it.
class AppGate extends StatefulWidget {
  /// Creates the gate for [app].
  const AppGate({super.key, required this.app, required this.child});

  /// "customer", "store" or "courier".
  final String app;

  /// The app shown while nothing blocks it.
  final Widget child;

  @override
  State<AppGate> createState() => _AppGateState();
}

class _AppGateState extends State<AppGate> with WidgetsBindingObserver {
  bool _updateRequired = false;
  String? _maintenance;
  String? _storeUrl;
  DateTime _lastCheck = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && DateTime.now().difference(_lastCheck) > const Duration(minutes: 5)) _check();
  }

  Future<void> _check() async {
    _lastCheck = DateTime.now();
    final client = ApiConfig.httpClient();
    try {
      final info = await PackageInfo.fromPlatform();
      final uri = Uri.parse('${ApiConfig.baseUrl}/app-config').replace(queryParameters: {'app': widget.app, 'build': info.buildNumber});
      final res = await client.get(uri, headers: AppLanguage.headers).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200 || !mounted) return;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final maintenance = data['maintenance'] as Map?;
      setState(() {
        _updateRequired = data['updateRequired'] == true;
        _maintenance = maintenance?['active'] == true ? (maintenance?['message'] as String?) : null;
        _storeUrl = data['storeUrl'] as String?;
      });
    } catch (_) {
      // Offline or the server is slow: let the app open; screens handle their own errors.
    } finally {
      client.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_updateRequired) {
      return _GateScreen(
        icon: Icons.system_update_rounded,
        title: tr(context, 'Time to update', 'Päivitä sovellus'),
        body: tr(context, 'This version of the app no longer works. Update it from Google Play to keep using Malvoya.',
            'Tämä sovellusversio ei enää toimi. Päivitä se Google Playsta jatkaaksesi Malvoyan käyttöä.'),
        action: tr(context, 'Update', 'Päivitä'),
        onAction: _storeUrl == null ? null : () => launchUrl(Uri.parse(_storeUrl!), mode: LaunchMode.externalApplication),
      );
    }
    if (_maintenance != null) {
      return _GateScreen(
        icon: Icons.construction_rounded,
        title: tr(context, 'Back soon', 'Palaamme pian'),
        body: _maintenance!,
        action: tr(context, 'Try again', 'Yritä uudelleen'),
        onAction: _check,
      );
    }
    return widget.child;
  }
}

class _GateScreen extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final String action;
  final VoidCallback? onAction;
  const _GateScreen({required this.icon, required this.title, required this.body, required this.action, this.onAction});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(color: theme.colorScheme.secondary, shape: BoxShape.circle),
                child: Icon(icon, size: 44, color: theme.colorScheme.onSecondary),
              ),
              const SizedBox(height: 24),
              Text(title, textAlign: TextAlign.center, style: theme.textTheme.headlineSmall),
              const SizedBox(height: 12),
              Text(body, textAlign: TextAlign.center, style: theme.textTheme.bodyLarge?.copyWith(height: 1.45)),
              const SizedBox(height: 28),
              SizedBox(width: double.infinity, height: 54, child: FilledButton(onPressed: onAction, child: Text(action))),
            ],
          ),
        ),
      ),
    );
  }
}
