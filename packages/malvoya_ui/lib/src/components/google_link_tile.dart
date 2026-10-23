import 'package:flutter/material.dart';
import 'package:malvoya_core/malvoya_core.dart';
import '../tokens/tokens.dart';
import 'snack.dart';

/// What [GoogleLinkTile] needs from an app's sign-in state (each app's `AuthService`).
abstract interface class GoogleLinkAccount implements Listenable {
  /// "Sign in with Google" opens this account.
  bool get googleLinked;

  /// Links the Google account; null when it worked, else a sentence to show.
  Future<String?> linkGoogle();

  /// Removes the link; null when it worked, else a sentence to show.
  Future<String?> unlinkGoogle();
}

/// Account setting: link a Google account so "Sign in with Google" opens this account, or unlink it
/// (asks first). Shows a spinner while it works and a snack with the result.
class GoogleLinkTile extends StatefulWidget {
  /// Creates the row for [account].
  const GoogleLinkTile({super.key, required this.account, this.leading});

  /// The signed-in account.
  final GoogleLinkAccount account;

  /// Leading widget (default: a link icon in the brand colour).
  final Widget? leading;

  @override
  State<GoogleLinkTile> createState() => _GoogleLinkTileState();
}

class _GoogleLinkTileState extends State<GoogleLinkTile> {
  bool _busy = false;

  Future<void> _toggle() async {
    final account = widget.account;
    final linked = account.googleLinked;
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
    final error = linked ? await account.unlinkGoogle() : await account.linkGoogle();
    if (!mounted) return;
    setState(() => _busy = false);
    final done = linked
        ? tr(context, 'Google unlinked', 'Google-yhteys poistettu')
        : tr(context, 'Google linked. You can now sign in with Google.', 'Google yhdistetty. Voit nyt kirjautua Googlella.');
    MSnack.show(context, error ?? done, kind: error == null ? MSnackKind.success : MSnackKind.error);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: widget.account,
        builder: (context, _) {
          final linked = widget.account.googleLinked;
          return ListTile(
            leading: widget.leading ?? Icon(Icons.link_rounded, color: context.mColors.primary),
            title: Text(tr(context, 'Google account', 'Google-tili'), style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(linked
                ? tr(context, 'Linked: you can sign in with Google', 'Yhdistetty: voit kirjautua Googlella')
                : tr(context, 'Link it to sign in with Google', 'Yhdistä, niin voit kirjautua Googlella')),
            trailing: _busy
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : TextButton(
                    onPressed: _toggle,
                    child: Text(linked ? tr(context, 'Unlink', 'Poista') : tr(context, 'Link', 'Yhdistä')),
                  ),
          );
        },
      );
}
