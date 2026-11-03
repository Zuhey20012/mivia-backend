import 'dart:async';
import 'dart:ui' show PlatformDispatcher;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:malvoya_core/malvoya_core.dart';
import 'package:malvoya_ui/malvoya_ui.dart';
import 'config/constants.dart';
import 'core/account_language.dart';
import 'core/agreements.dart';
import 'core/blocked_users.dart';
import 'screens/main_navigation.dart';
import 'screens/login.dart';
import 'screens/onboarding.dart';
import 'cart.dart';
import 'auth_service.dart';
import 'l10n.dart';
import 'theme_provider.dart';
import 'local_notification_service.dart';
import 'core/deep_links.dart';
import 'core/delivery_location.dart';
import 'core/network_status.dart';
import 'core/push_service.dart';
import 'screens/order_detail.dart';
import 'screens/store_detail.dart';
import 'services/socket_service.dart';
import 'widgets/offline_banner.dart';

/// Lets a tapped push notification open the right screen from anywhere.
final navigatorKey = GlobalKey<NavigatorState>();

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  registerMalvoyaFontLicenses();
  ApiConfig.baseUrl = AppConstants.apiBase;

  // Stripe — initialize only if a real key is set. Only checkout needs it, so the first frame
  // does not wait for it.
  try {
    if (!AppConstants.stripePublishableKey.contains('REPLACE')) {
      Stripe.publishableKey = AppConstants.stripePublishableKey;
      unawaited(Stripe.instance.applySettings().catchError((Object e) => debugPrint('Stripe init skipped: $e')));
    }
  } catch (e) {
    debugPrint('Stripe init skipped: $e');
  }

  // Live order updates belong to the signed-in account; close the connection on sign-out
  AuthService.beforeLogout.add((_) async => CustomerSocketService().disconnect());
  // Saved and active delivery addresses belong to the account holder, not to the next person
  AuthService.beforeLogout.add((_) => DeliveryLocation.instance.clear());
  AuthService.beforeLogout.add((_) async => BlockedUsers.instance.clear());

  PushService.instance.onOpen = (data) {
    final orderId = asInt(data['orderId']);
    if (data['type'] == 'order' && orderId != null) {
      navigatorKey.currentState?.push(MaterialPageRoute(builder: (_) => OrderDetailScreen(orderId: orderId)));
    }
    // "Malvoya is open near you" opens the new store
    final storeId = asInt(data['storeId']);
    if (data['type'] == 'store' && storeId != null) {
      navigatorKey.currentState?.push(MaterialPageRoute(builder: (_) => StoreDetailScreen(store: {'id': storeId})));
    }
  };

  // An order refused with 428 AGREEMENT_REQUIRED opens the agreement sheet, then is sent again
  ApiConfig.onAgreementRequired = Agreements.instance.handleRequired;

  // Verified https links to drops, stores and invites (Android App Links); a link waits until the
  // main screen is up
  DeepLinks.instance.start(navigatorKey);

  // The welcome animation plays while the services start (together, not one by one); the app opens
  // as soon as both are done
  runApp(MalvoyaIntro(
    brand: MalvoyaBrand.malva,
    appName: 'Malvoya',
    tagline: (context) => tr(context, 'Local fashion and beauty', 'Lähikauppojen muoti ja kauneus'),
    ready: _start(),
    builder: (_) => const MalvoyaApp(),
  ));
}

/// Everything the app needs before its first screen, started in parallel.
Future<void> _start() async {
  // The app version (X-App-Version) and the saved language, before the first request goes out
  final version = AppLanguage.loadAppVersion();
  await Future.wait<void>([
    // Lock to portrait
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]),
    // Local Notifications Engine
    LocalNotificationService.initialize().catchError((Object e) => debugPrint('Local notifications init: $e')),
    LocaleProvider.savedCode().then((code) => AppLanguage.code = code ?? AppLanguage.code),
    Onboarding.load(),
    DeliveryLocation.instance.load(),
    version,
    () async {
      // Firebase. On iOS it needs GoogleService-Info.plist (added on the Mac, never committed);
      // without it the app runs without push, phone and Apple sign-in.
      await SignInSetup.loadIos();
      try {
        final app = await Firebase.initializeApp();
        SignInSetup.firebaseInitialised(appId: app.options.appId, iosClientId: app.options.iosClientId);
      } catch (e) {
        debugPrint('Firebase init error: $e');
      }
      // Crash reports (Firebase Crashlytics, docs/release/crashlytics.md): sent from release builds
      // only, and only when Firebase started (an iPhone build without GoogleService-Info.plist skips
      // them). Only the numeric user id, the app version and the role go with them.
      await version;
      await CrashReporting.instance.init(backend: SignInSetup.firebaseReady ? _crashlyticsBackend() : null, role: 'customer');
      FlutterError.onError = CrashReporting.instance.recordFlutterFatalError;
      PlatformDispatcher.instance.onError = CrashReporting.instance.recordPlatformError;
    }(),
  ]);
  unawaited(NetworkStatus.instance.start());
}

// Firebase Crashlytics behind the shared [CrashReporting] (built only when Firebase started).
CrashBackend _crashlyticsBackend() {
  final c = FirebaseCrashlytics.instance;
  return CallbackCrashBackend(
    setCollectionEnabled: c.setCrashlyticsCollectionEnabled,
    setUserIdentifier: c.setUserIdentifier,
    setCustomKey: c.setCustomKey,
    recordError: (e, s, {reason, fatal = false}) => c.recordError(e, s, reason: reason, fatal: fatal),
    recordFlutterFatalError: c.recordFlutterFatalError,
  );
}

class MalvoyaApp extends StatelessWidget {
  const MalvoyaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) {
          final auth = AuthService();
          // Crash reports carry the signed-in account's numeric id; cleared on sign-out
          CrashReporting.instance.followUser(auth, () => auth.isAuthenticated ? auth.currentUser?.id : null);
          PushService.instance.attach(auth);
          // The account's language for pushes and emails, saved after each sign-in
          AccountLanguage.attach(auth);
          // People this customer blocked: their comments and reviews stay hidden
          auth.addListener(() => BlockedUsers.instance.load(auth));
          // Terms not accepted (e.g. Google, phone or Apple accounts): ask once after sign-in
          Agreements.instance.attach(auth, navigatorKey);
          return auth;
        }),
        ChangeNotifierProvider(create: (_) => CartService()),
        // A new language is saved on the account too (pushes and emails follow it)
        ChangeNotifierProvider(create: (_) => LocaleProvider()..onUserChange = (_) => AccountLanguage.sync()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      child: Consumer2<LocaleProvider, ThemeProvider>(
        builder: (context, localeProvider, themeProvider, child) {
          return MaterialApp(
            navigatorKey: navigatorKey,
            navigatorObservers: [mainRouteObserver],
            title: 'Malvoya',
            debugShowCheckedModeBanner: false,
            theme: themeProvider.currentTheme,
            darkTheme: themeProvider.currentTheme,
            themeMode: themeProvider.themeMode,
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
            builder: (context, child) => AppGate(
              app: 'customer',
              // A slim "no internet" notice above every screen while the phone is offline
              child: OfflineBanner(child: child ?? const SizedBox.shrink()),
            ),
            home: ValueListenableBuilder<bool>(
              valueListenable: Onboarding.seen,
              builder: (context, seen, _) => Consumer<AuthService>(
                builder: (context, auth, child) {
                  if (!seen) {
                    // Someone already signed in has used the app before: no intro for them
                    if (auth.isAuthenticated) {
                      WidgetsBinding.instance.addPostFrameCallback((_) => Onboarding.markSeen());
                    } else {
                      // A plain screen for the moment the saved session is read, so nothing flashes
                      return auth.isReady ? const OnboardingScreen() : const Scaffold();
                    }
                  }
                  final screen = !auth.canBrowse ? const LoginScreen() : const MainNavigation();
                  return screen;
                },
              ),
            ),
          );
        },
      ),
    );
  }
}
