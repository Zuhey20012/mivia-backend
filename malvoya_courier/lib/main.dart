import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'config/theme.dart';
import 'core/font_licenses.dart';
import 'core/app_gate.dart';
import 'core/connectivity.dart';
import 'screens/courier_welcome.dart';
import 'screens/courier_dashboard.dart';
import 'screens/pending_approval.dart';
import 'core/push_service.dart';
import 'services/courier_telemetry_service.dart';
import 'services/socket_service.dart';
import 'auth_service.dart';
import 'l10n.dart';
import 'locale_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerFontLicenses();
  // Shows a "No internet" strip and lets screens refresh when the connection comes back
  ConnectivityService.instance.start();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
  try { await Firebase.initializeApp(); } catch (e) { debugPrint('Firebase: $e'); }
  // Location sharing ends with the session, however it ends (sign-out, account deletion, expiry)
  AuthService.beforeLogout.add((_) async {
    CourierTelemetryService().stop();
    CourierSocketService().disconnect();
  });
  runApp(const MalvoyaCourierApp());
}

/// The app's navigator. When the session changes (signed in, approved, signed out or deleted),
/// every screen pushed on top is closed so the home screen below decides what is shown: no
/// sign-in or register screen stays open over the dashboard, and no account sheet over the
/// welcome screen.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

String _gateOf(AuthService auth) {
  if (!auth.isAuthenticated) return 'out';
  return auth.currentUser?.role == 'COURIER' && !auth.isPendingApproval ? 'courier' : 'pending';
}

class MalvoyaCourierApp extends StatelessWidget {
  const MalvoyaCourierApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) {
          final auth = AuthService();
          // Job offers and payouts arrive as notifications when the app is in the background
          PushService.instance.attach(auth);
          // The location fallback over HTTP needs the current access token, which is refreshed every 15 min
          auth.addListener(() => CourierTelemetryService().updateToken(auth.accessToken));
          var gate = _gateOf(auth);
          auth.addListener(() {
            final next = _gateOf(auth);
            if (next == gate) return;
            gate = next;
            appNavigatorKey.currentState?.popUntil((route) => route.isFirst);
          });
          return auth;
        }),
        ChangeNotifierProvider(create: (_) => LocaleProvider()),
      ],
      child: Consumer<LocaleProvider>(
        builder: (context, localeProvider, child) => MaterialApp(
          title: 'Malvoya Courier',
          navigatorKey: appNavigatorKey,
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          locale: localeProvider.locale,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [
            Locale('en', ''),
            Locale('fi', ''),
          ],
          // Asks the server whether this build is still supported or Malvoya is in maintenance
          builder: (context, child) => OfflineBanner(child: AppGate(app: 'courier', child: child ?? const SizedBox.shrink())),
          home: Consumer<AuthService>(
            builder: (context, auth, child) {
              if (!auth.isAuthenticated) return const CourierWelcomeScreen();
              if (auth.currentUser?.role == 'COURIER' && !auth.isPendingApproval) {
                return const CourierDashboard();
              }
              // Any logged-in user can sign agreement and onboard as courier
              return const PendingApprovalScreen();
            },
          ),
        ),
      ),
    );
  }
}
