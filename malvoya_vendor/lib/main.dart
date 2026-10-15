import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'config/theme.dart';
import 'core/font_licenses.dart';
import 'core/app_gate.dart';
import 'core/connectivity.dart';
import 'screens/login.dart';
import 'screens/vendor_home.dart';
import 'auth_service.dart';
import 'l10n.dart';
import 'locale_provider.dart';
import 'core/push_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerFontLicenses();
  // Shows a "No internet" strip and lets screens refresh when the connection comes back
  ConnectivityService.instance.start();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
  try { await Firebase.initializeApp(); } catch (e) { debugPrint('Firebase: $e'); }
  runApp(const MalvoyaVendorApp());
}

final _navigatorKey = GlobalKey<NavigatorState>();

/// Signing in, out or deleting the account switches the home screen; screens pushed on top of the
/// old home (e.g. registration, a settings page) are closed so they never cover the new one.
void _closeStackOnAuthChange(AuthService auth) {
  bool? signedIn;
  auth.addListener(() {
    final now = auth.isAuthenticated;
    if (signedIn != null && signedIn != now) _navigatorKey.currentState?.popUntil((r) => r.isFirst);
    signedIn = now;
  });
}

class MalvoyaVendorApp extends StatelessWidget {
  const MalvoyaVendorApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) {
          final auth = AuthService();
          _closeStackOnAuthChange(auth);
          // New orders and payouts arrive as notifications even when the app is closed
          PushService.instance.attach(auth);
          return auth;
        }),
        ChangeNotifierProvider(create: (_) => LocaleProvider()),
      ],
      child: Consumer<LocaleProvider>(
        builder: (context, localeProvider, child) => MaterialApp(
          title: 'Malvoya Store',
          navigatorKey: _navigatorKey,
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          locale: localeProvider.locale,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('fi'), Locale('en')],
          // Asks the server whether this build is still supported or Malvoya is in maintenance
          builder: (context, child) => OfflineBanner(child: AppGate(app: 'store', child: child ?? const SizedBox.shrink())),
          home: Consumer<AuthService>(
            builder: (context, auth, child) {
              if (!auth.isAuthenticated) return const LoginScreen();
              // Welcome and store setup until the store exists, then the dashboard
              return const VendorHome();
            },
          ),
        ),
      ),
    );
  }
}
