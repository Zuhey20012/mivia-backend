import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'config/theme.dart';
import 'screens/main_navigation.dart';
import 'screens/login.dart';
import 'screens/courier_dashboard.dart';
import 'screens/vendor_dashboard.dart';
import 'cart.dart';
import 'auth_service.dart';
import 'l10n.dart';
import 'locale_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint('Firebase Initialization Error: $e');
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
        ChangeNotifierProvider(create: (_) => CartService()),
        ChangeNotifierProvider(create: (_) => LocaleProvider()),
      ],
      child: Consumer<LocaleProvider>(
        builder: (context, localeProvider, child) {
          return MaterialApp(
            title: 'Malvoya Vendor',
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
            home: Consumer<AuthService>(
              builder: (context, auth, child) {
                if (auth.isAuthenticated) {
                  if (auth.currentUser?.role == 'COURIER') {
                    return const CourierDashboard();
                  } else if (auth.currentUser?.role == 'VENDOR') {
                    return const VendorDashboard();
                  }
                  return const MainNavigation(); // Customer and Admin
                }
                return const LoginScreen();
              },
            ),
          );
        },
      ),
    );
  }
}
