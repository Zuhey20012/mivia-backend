import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'config/constants.dart';
import 'screens/main_navigation.dart';
import 'screens/login.dart';
import 'cart.dart';
import 'auth_service.dart';
import 'admin_service.dart';
import 'l10n.dart';
import 'locale_provider.dart';
import 'theme_provider.dart';
import 'local_notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

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

  runApp(const MalvoyaApp());
}

class MalvoyaApp extends StatelessWidget {
  const MalvoyaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()),
        ChangeNotifierProxyProvider<AuthService, AdminService>(
          create: (ctx) => AdminService(Provider.of<AuthService>(ctx, listen: false)),
          update: (ctx, auth, _) => AdminService(auth),
        ),
        ChangeNotifierProvider(create: (_) => CartService()),
        ChangeNotifierProvider(create: (_) => LocaleProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      child: Consumer2<LocaleProvider, ThemeProvider>(
        builder: (context, localeProvider, themeProvider, child) {
          return MaterialApp(
            key: ValueKey('malvoya_app_${localeProvider.locale.languageCode}_${themeProvider.mode}'),
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
                if (!auth.isAuthenticated) return const LoginScreen();
                return const MainNavigation();
              },
            ),
          );
        },
      ),
    );
  }
}
