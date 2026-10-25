import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerMalvoyaFontLicenses();
  ApiConfig.baseUrl = AppConstants.apiBase;

  // Lock to portrait
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Local Notifications Engine
  try {
    await LocalNotificationService.initialize();
  } catch (e) {
    debugPrint('Local notifications init: $e');
  }

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

  // Firebase. On iOS it needs GoogleService-Info.plist (added on the Mac, never committed);
  // without it the app runs without push, phone and Apple sign-in.
  await SignInSetup.loadIos();
  try {
    final app = await Firebase.initializeApp();
    SignInSetup.firebaseInitialised(appId: app.options.appId, iosClientId: app.options.iosClientId);
  } catch (e) {
    debugPrint('Firebase init error: $e');
  }

  // The app version (X-App-Version) and the saved language, before the first request goes out
  await AppLanguage.loadAppVersion();
  AppLanguage.code = await LocaleProvider.savedCode() ?? AppLanguage.code;
  await Onboarding.load();
  await DeliveryLocation.instance.load();
  unawaited(NetworkStatus.instance.start());
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

  // Verified https links to drops, stores and invites (Android App Links)
  DeepLinks.instance.start(navigatorKey);

  runApp(const MalvoyaApp());
}

class MalvoyaApp extends StatelessWidget {
  const MalvoyaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) {
          final auth = AuthService();
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
