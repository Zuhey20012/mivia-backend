import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:malvoya_core/malvoya_core.dart';
import 'package:malvoya_ui/malvoya_ui.dart';
import 'config/constants.dart';
import 'config/theme.dart';
import 'core/connectivity.dart';
import 'screens/login.dart';
import 'screens/returns_manager.dart';
import 'screens/vendor_home.dart';
import 'auth_service.dart';
import 'l10n.dart';
import 'core/push_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerMalvoyaFontLicenses();
  ApiConfig.baseUrl = AppConstants.apiBase;
  // A failed request lets the "No internet" strip appear even without a system network change
  ApiConfig.onNetworkError = ConnectivityService.instance.verify;
  // Sent as X-App-Version with every request (the server records it with agreement acceptances)
  await AppLanguage.loadAppVersion();
  // Shows a "No internet" strip and lets screens refresh when the connection comes back
  ConnectivityService.instance.start();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
  try { await Firebase.initializeApp(); } catch (e) { debugPrint('Firebase: $e'); }
  runApp(const MalvoyaVendorApp());
}

final _navigatorKey = GlobalKey<NavigatorState>();
final _messengerKey = GlobalKey<ScaffoldMessengerState>();

/// Signing in, out or deleting the account switches the home screen; screens pushed on top of the
/// old home (e.g. registration, a settings page) are closed so they never cover the new one.
void _closeStackOnAuthChange(AuthService auth) {
  bool? signedIn;
  auth.addListener(() {
    final now = auth.isAuthenticated;
    if (signedIn != null && signedIn != now) {
      _navigatorKey.currentState?.popUntil((r) => r.isFirst);
      // e.g. a "New return request" banner from the signed-out account
      _messengerKey.currentState?.clearMaterialBanners();
    }
    signedIn = now;
  });
}

/// A return notification opens the Returns screen on top of whatever is open (nothing is closed, so
/// unsaved edits stay). Other notifications just bring the app forward; the dashboard refreshes itself.
void _openFromNotification(AuthService auth, Map<String, dynamic> data) {
  final nav = _navigatorKey.currentState;
  if (nav == null || !auth.isAuthenticated) return;
  final type = '${data['type'] ?? ''}'.toLowerCase();
  final isReturn = type.contains('return') || data['returnId'] != null;
  if (isReturn && auth.storeState != StoreState.none) {
    nav.push(MaterialPageRoute(builder: (_) => const ReturnsManager()));
  }
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
          // Tapping a notification opens the matching screen
          PushService.instance.onOpen = (data) => _openFromNotification(auth, data);
          return auth;
        }),
        ChangeNotifierProvider(
          create: (ctx) => LocaleProvider(followSystem: false)
            // A new language also changes the language of the account's notifications and emails
            ..onUserChange = (_) => Provider.of<AuthService>(ctx, listen: false).syncLocale(),
        ),
      ],
      child: Consumer<LocaleProvider>(
        builder: (context, localeProvider, child) => MaterialApp(
          title: 'Malvoya Store',
          navigatorKey: _navigatorKey,
          scaffoldMessengerKey: _messengerKey,
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
