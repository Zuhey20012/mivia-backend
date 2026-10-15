import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../screens/login.dart';
import 'strings.dart';

/// Opens sign-in over the current screen. Returns true once the customer is signed in (the sign-in
/// screen closes itself); the bag and the screen underneath are kept.
Future<bool> openSignIn(BuildContext context) async {
  final ok = await Navigator.of(context).push<bool>(
    MaterialPageRoute(builder: (_) => const LoginScreen(returnAfterSignIn: true)),
  );
  return ok == true;
}

/// "Sign in / Create account" card for guests: shown where an account is needed (profile, orders,
/// favourites).
class SignInCard extends StatelessWidget {
  final String title;
  final String message;
  const SignInCard({super.key, required this.title, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.pastel(context, AppTheme.sunshineLight, AppTheme.sunshine),
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.person_outline_rounded, color: Color(0xFF8A5A00)),
              const SizedBox(width: 10),
              Expanded(child: Text(title, style: AppTheme.display(context, size: 18))),
            ],
          ),
          const SizedBox(height: 6),
          Text(message, style: TextStyle(fontSize: 13.5, height: 1.35, color: AppTheme.primaryText(context))),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => openSignIn(context),
              child: Text(tr(context, 'Sign in / Create account', 'Kirjaudu / Luo tili')),
            ),
          ),
        ],
      ),
    );
  }
}
