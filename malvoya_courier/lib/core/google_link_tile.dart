import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../auth_service.dart';
import '../config/theme.dart';
import 'strings.dart';

/// Account setting: link a Google account so "Sign in with Google" opens this account, or unlink it.
class GoogleLinkTile extends StatefulWidget {
  final Widget? leading;

  const GoogleLinkTile({super.key, this.leading});

  @override
  State<GoogleLinkTile> createState() => _GoogleLinkTileState();
}

class _GoogleLinkTileState extends State<GoogleLinkTile> {
  bool _busy = false;

  Future<void> _toggle(AuthService auth) async {
    final linked = auth.googleLinked;
    if (linked) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(tr(ctx, 'Unlink Google?', 'Poistetaanko Google-yhteys?')),
          content: Text(tr(ctx, 'You will sign in with your password instead.', 'Kirjaudut jatkossa salasanallasi.')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr(ctx, 'Cancel', 'Peruuta'))),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr(ctx, 'Unlink', 'Poista yhteys'))),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    setState(() => _busy = true);
    final error = linked ? await auth.unlinkGoogle() : await auth.linkGoogle();
    if (!mounted) return;
    setState(() => _busy = false);
    final done = linked
        ? tr(context, 'Google unlinked', 'Google-yhteys poistettu')
        : tr(context, 'Google linked. You can now sign in with Google.', 'Google yhdistetty. Voit nyt kirjautua Googlella.');
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error ?? done), behavior: SnackBarBehavior.floating));
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthService>(context);
    final linked = auth.googleLinked;
    return ListTile(
      leading: widget.leading ?? const Icon(Icons.link_rounded, color: AppTheme.primary),
      title: Text(tr(context, 'Google account', 'Google-tili'), style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(linked
          ? tr(context, 'Linked: you can sign in with Google', 'Yhdistetty: voit kirjautua Googlella')
          : tr(context, 'Link it to sign in with Google', 'Yhdistä, niin voit kirjautua Googlella')),
      trailing: _busy
          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
          : TextButton(
              onPressed: () => _toggle(auth),
              child: Text(linked ? tr(context, 'Unlink', 'Poista') : tr(context, 'Link', 'Yhdistä')),
            ),
    );
  }
}
