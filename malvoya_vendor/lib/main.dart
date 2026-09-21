import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'config/theme.dart';
import 'screens/login.dart';
import 'screens/vendor_dashboard.dart';
import 'screens/pending_approval.dart';
import 'auth_service.dart';
import 'l10n.dart';
import 'locale_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
  try { await Firebase.initializeApp(); } catch (e) { debugPrint('Firebase: $e'); }
  runApp(const MalvoyaVendorApp());
}

class MalvoyaVendorApp extends StatelessWidget {
  const MalvoyaVendorApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()),
        ChangeNotifierProvider(create: (_) => LocaleProvider()),
      ],
      child: Consumer<LocaleProvider>(
        builder: (context, localeProvider, child) => MaterialApp(
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
              if (auth.currentUser?.role == 'VENDOR' && !auth.isPendingApproval) {
                return const VendorDashboard();
              }
              // Any logged-in user can sign agreement and onboard as vendor
              return const PendingApprovalScreen();
            },
          ),
        ),
      ),
    );
  }
}
