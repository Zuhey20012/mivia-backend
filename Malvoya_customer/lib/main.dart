import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'config/constants.dart';
import 'core/font_licenses.dart';
import 'screens/main_navigation.dart';
import 'screens/login.dart';
import 'cart.dart';
import 'auth_service.dart';
import 'l10n.dart';
import 'locale_provider.dart';
import 'theme_provider.dart';
import 'local_notification_service.dart';
import 'core/delivery_location.dart';
import 'core/push_service.dart';
import 'core/strings.dart';
import 'screens/order_detail.dart';
import 'screens/store_detail.dart';

/// Lets a tapped push notification open the right screen from anywhere.
final navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerFontLicenses();

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

  // Stripe — initialize only if a real key is set
  try {
    if (!AppConstants.stripePublishableKey.contains('REPLACE')) {
      Stripe.publishableKey = AppConstants.stripePublishableKey;
      await Stripe.instance.applySettings();
    }
  } catch (e) {
    debugPrint('Stripe init skipped: $e');
  }

  // Firebase
  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint('Firebase init error: $e');
  }

  await DeliveryLocation.instance.load();

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
          return auth;
        }),
        ChangeNotifierProvider(create: (_) => CartService()),
        ChangeNotifierProvider(create: (_) => LocaleProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      child: Consumer2<LocaleProvider, ThemeProvider>(
        builder: (context, localeProvider, themeProvider, child) {
          return MaterialApp(
            key: ValueKey('malvoya_app_${localeProvider.locale.languageCode}_${themeProvider.mode}'),
            navigatorKey: navigatorKey,
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
              Locale('sv', ''),
              Locale('de', ''),
              Locale('fr', ''),
              Locale('nl', ''),
              Locale('it', ''),
              Locale('es', ''),
              Locale('pt', ''),
              Locale('pl', ''),
              Locale('ro', ''),
              Locale('cs', ''),
              Locale('hu', ''),
              Locale('el', ''),
              Locale('da', ''),
              Locale('sk', ''),
              Locale('bg', ''),
              Locale('hr', ''),
              Locale('no', ''),
              Locale('ru', ''),
              Locale('tr', ''),
              Locale('uk', ''),
              Locale('ar', ''),
              Locale('zh', ''),
              Locale('hi', ''),
            ],
            home: Consumer<AuthService>(
              builder: (context, auth, child) {
                final screen = !auth.canBrowse ? const LoginScreen() : const MainNavigation();
                return screen;
              },
            ),
          );
        },
      ),
    );
  }
}
