import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:malvoya_core/malvoya_core.dart';
import 'package:malvoya_ui/malvoya_ui.dart';
import 'config/constants.dart';
import 'config/theme.dart';
import 'core/account_security.dart';
import 'core/connectivity.dart';
import 'core/location_disclosure.dart';
import 'screens/courier_welcome.dart';
import 'screens/courier_dashboard.dart';
import 'screens/pending_approval.dart';
import 'core/push_service.dart';
import 'services/courier_telemetry_service.dart';
import 'services/socket_service.dart';
import 'auth_service.dart';
import 'l10n.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerMalvoyaFontLicenses();
  ApiConfig.baseUrl = AppConstants.apiBase;
  // A failed request lets the "No internet" strip appear even without a system network change
  ApiConfig.onNetworkError = ConnectivityService.instance.verify;
  // "1.7.0+9", sent as X-App-Version with every API request
  await AppLanguage.loadAppVersion();
  // Shows a "No internet" strip and lets screens refresh when the connection comes back
  ConnectivityService.instance.start();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
  // Firebase. On iOS it needs GoogleService-Info.plist (added on the Mac, never committed);
  // without it the app runs without push and phone sign-in.
  await SignInSetup.loadIos();
  try {
    final app = await Firebase.initializeApp();
    SignInSetup.firebaseInitialised(appId: app.options.appId, iosClientId: app.options.iosClientId);
  } catch (e) {
    debugPrint('Firebase: $e');
  }
  // Location sharing ends with the session, however it ends (sign-out, account deletion, expiry)
  AuthService.beforeLogout.add((_) async {
    CourierTelemetryService().stop();
    CourierSocketService().disconnect();
  });
  // Two-step sign-in (code from the authenticator app) and "I am 18 or older" for a new account
  // made with Google or a phone number are asked over whatever screen started the sign-in
  AuthService.askTwoStepCode = (auth, mfaToken) async {
    final context = appNavigatorKey.currentState?.overlay?.context;
    if (context == null) return 'Enter the code from your authenticator app to sign in.';
    return showTwoStepSignIn(context, auth, mfaToken);
  };
  AuthService.confirmAge = () async {
    final context = appNavigatorKey.currentState?.overlay?.context;
    return context != null && await showAgeConfirmation(context);
  };
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
          // Accepting the location disclosure is also recorded on the server (API 2.11 onboarding)
          LocationDisclosure.attach(auth);
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
        ChangeNotifierProvider(create: (ctx) {
          final locale = LocaleProvider(followSystem: false);
          // Push notifications and emails follow the app language
          locale.onUserChange = (_) => Provider.of<AuthService>(ctx, listen: false).syncLocale();
          return locale;
        }),
      ],
      child: Consumer<LocaleProvider>(
        builder: (context, localeProvider, child) => MaterialApp(
          title: 'Malvoya Courier',
          navigatorKey: appNavigatorKey,
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          highContrastTheme: AppTheme.highContrastTheme,
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
