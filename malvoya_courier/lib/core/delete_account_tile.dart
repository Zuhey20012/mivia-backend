import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../auth_service.dart';
import 'strings.dart';

/// Account setting: permanently delete the account on the server (GDPR Art. 17, required by Google Play).
class DeleteAccountTile extends StatefulWidget {
  final Widget? leading;

  const DeleteAccountTile({super.key, this.leading});

  @override
  State<DeleteAccountTile> createState() => _DeleteAccountTileState();
}

class _DeleteAccountTileState extends State<DeleteAccountTile> {
  static const _red = Color(0xFFD93025);
  bool _busy = false;

  Future<void> _confirm() async {
    final auth = Provider.of<AuthService>(context, listen: false);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(ctx, 'Delete your account?', 'Poistetaanko tilisi?')),
        content: Text(tr(
          ctx,
          'Your account and personal data are erased and you are signed out. Order records stay in anonymised form, as Finnish bookkeeping law requires. Orders in progress must be completed first.',
          'Tilisi ja henkilötietosi poistetaan ja sinut kirjataan ulos. Tilaustiedot säilyvät anonymisoituina kirjanpitolain vuoksi. Keskeneräiset tilaukset on saatava valmiiksi ensin.',
        )),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr(ctx, 'Cancel', 'Peruuta'))),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr(ctx, 'Delete account', 'Poista tili'), style: const TextStyle(color: _red, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    final error = await auth.deleteAccount();
    if (!mounted) return;
    setState(() => _busy = false);
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error), behavior: SnackBarBehavior.floating));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: widget.leading ?? const Icon(Icons.delete_forever_rounded, color: _red),
      title: Text(tr(context, 'Delete account', 'Poista tili'), style: const TextStyle(fontWeight: FontWeight.w600, color: _red)),
      subtitle: Text(tr(context, 'Erase your account and personal data', 'Poista tilisi ja henkilötietosi')),
      trailing: _busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : null,
      onTap: _busy ? null : _confirm,
    );
  }
}
