import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../auth_service.dart';
import '../config/theme.dart';
import '../core/delete_account_tile.dart';
import '../core/strings.dart';
import '../screens/chatbot.dart';

/// Help, sign out and delete account, for screens shown before the store exists (the dashboard has
/// the same entries in its Store tab). Google Play requires account deletion to be reachable in the app.
Future<void> showAccountSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Text(tr(ctx, 'Account', 'Tili'), style: AppTheme.display(size: 20)),
          ),
          ListTile(
            leading: const CircleAvatar(backgroundColor: AppTheme.primaryLight, child: Icon(Icons.help_outline_rounded, color: AppTheme.primary)),
            title: Text(tr(ctx, 'Help', 'Apua'), style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(tr(ctx, 'Answers for sellers and a message to the Malvoya team', 'Vastauksia myyjille ja viesti Malvoyan tiimille')),
            onTap: () {
              Navigator.pop(ctx);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const ChatbotScreen()));
            },
          ),
          ListTile(
            leading: const CircleAvatar(backgroundColor: AppTheme.sand, child: Icon(Icons.logout_rounded, color: AppTheme.textPrimary)),
            title: Text(tr(ctx, 'Sign out', 'Kirjaudu ulos'), style: const TextStyle(fontWeight: FontWeight.w600)),
            onTap: () {
              Navigator.pop(ctx);
              Provider.of<AuthService>(context, listen: false).logout();
            },
          ),
          const DeleteAccountTile(leading: CircleAvatar(backgroundColor: Color(0xFFFDECEA), child: Icon(Icons.delete_forever_rounded, color: Color(0xFFD93025)))),
        ]),
      ),
    ),
  );
}
