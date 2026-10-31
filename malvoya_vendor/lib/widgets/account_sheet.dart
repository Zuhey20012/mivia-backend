import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:malvoya_core/malvoya_core.dart';
import 'package:malvoya_ui/malvoya_ui.dart';
import '../auth_service.dart';
import '../config/theme.dart';
import '../core/delete_account_tile.dart';
import '../core/download_data_tile.dart';
import '../screens/chatbot.dart';

/// Help, sign out, your data (the plain-language page and a download) and delete account, for screens shown before the store exists (the dashboard has
/// the same entries in its Store tab). Google Play requires account deletion to be reachable in the app.
Future<void> showAccountSheet(BuildContext context) {
  return showMSheet<void>(context, builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(MSpace.md, 0, MSpace.md, MSpace.md),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(MSpace.md, 0, MSpace.md, MSpace.sm),
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
          ListTile(
            leading: const CircleAvatar(backgroundColor: AppTheme.primaryLight, child: Icon(Icons.menu_book_outlined, color: AppTheme.primary)),
            title: Text(tr(ctx, 'Your data', 'Tietosi'), style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(tr(ctx, 'Shops: what we keep about you and your customers', 'Kaupoille: mitä säilytämme sinusta ja asiakkaistasi')),
            trailing: const Icon(Icons.open_in_new_rounded, size: 18),
            onTap: () => openLegal('data-explained'),
          ),
          const DownloadDataTile(leading: CircleAvatar(backgroundColor: AppTheme.primaryLight, child: Icon(Icons.download_rounded, color: AppTheme.primary))),
          const DeleteAccountTile(leading: CircleAvatar(backgroundColor: MPalette.redLight, child: Icon(Icons.delete_forever_rounded, color: MPalette.red))),
        ]),
      ),
    ), isScrollControlled: true, useSafeArea: false);
}
