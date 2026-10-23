import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:malvoya_core/malvoya_core.dart';
import 'package:malvoya_ui/malvoya_ui.dart';
import '../auth_service.dart';
import '../config/theme.dart';

import '../core/blocked_users.dart';

/// People this customer blocked (Profile → Blocked users). Unblocking shows their comments and
/// reviews again.
class BlockedUsersScreen extends StatefulWidget {
  const BlockedUsersScreen({super.key});

  @override
  State<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends State<BlockedUsersScreen> {
  bool _loading = true;
  String? _error;
  final Set<int> _busy = {};

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final auth = Provider.of<AuthService>(context, listen: false);
    await BlockedUsers.instance.load(auth);
    final error = await BlockedUsers.instance.refresh(auth);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _error = error;
    });
  }

  Future<void> _unblock(BlockedUser user) async {
    setState(() => _busy.add(user.id));
    final error = await BlockedUsers.instance.unblock(Provider.of<AuthService>(context, listen: false), user.id);
    if (!mounted) return;
    setState(() => _busy.remove(user.id));
    final name = user.name.isEmpty ? tr(context, 'The person', 'Henkilö') : user.name;
    MSnack.show(context, error == null
          ? tr(context, '$name is unblocked.', 'Henkilön $name esto on poistettu.')
          : tr(context, 'Could not unblock: ${localizeServerMessage(context, error)}', 'Eston poistaminen ei onnistunut: ${localizeServerMessage(context, error)}'));
  }

  @override
  Widget build(BuildContext context) {
    final muted = AppTheme.secondaryText(context);
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'Blocked users', 'Estetyt käyttäjät'))),
      body: ListenableBuilder(
        listenable: BlockedUsers.instance,
        builder: (context, _) {
          final blocks = BlockedUsers.instance;
          if (_loading && blocks.users.isEmpty) return const Center(child: CircularProgressIndicator());
          if (!blocks.available) {
            return _message(context, Icons.block_rounded,
                tr(context, 'Blocking is not available yet', 'Estäminen ei ole vielä käytössä'),
                tr(context, 'The Malvoya service does not support blocking yet. You can still report comments.', 'Malvoya-palvelu ei vielä tue estämistä. Voit silti ilmoittaa kommenteista.'));
          }
          final users = blocks.users;
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(MSpace.lg, MSpace.md, MSpace.lg, MSpace.x3l),
              children: [
                Text(
                  tr(context, 'You do not see comments or reviews from these people. They are not told that you blocked them.',
                      'Et näe näiden henkilöiden kommentteja etkä arvioita. Heille ei kerrota, että estit heidät.'),
                  style: TextStyle(fontSize: MTextSize.label, height: 1.4, color: muted),
                ),
                if (_error != null) ...[
                  const SizedBox(height: MSpace.md),
                  Text(localizeServerMessage(context, _error!), style: const TextStyle(color: MPalette.red, fontSize: MTextSize.label)),
                ],
                const SizedBox(height: MSpace.lg),
                if (users.isEmpty)
                  _message(context, Icons.check_circle_outline_rounded,
                      tr(context, 'You have not blocked anyone', 'Et ole estänyt ketään'),
                      tr(context, 'To block someone, press and hold their comment or review, or use its ⋮ menu.',
                          'Voit estää jonkun painamalla hänen kommenttiaan tai arviotaan pitkään tai sen ⋮-valikosta.'))
                else
                  Container(
                    decoration: BoxDecoration(
                      color: AppTheme.cardBackground(context),
                      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                      border: Border.all(color: AppTheme.cardBorder(context)),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        for (final u in users)
                          ListTile(
                            minTileHeight: 56,
                            leading: CircleAvatar(
                              backgroundColor: AppTheme.pastel(context, AppTheme.lilac, AppTheme.primary),
                              child: Text(u.name.isEmpty ? '?' : u.name.characters.first.toUpperCase(),
                                  style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w800)),
                            ),
                            title: Text(u.name.isEmpty ? tr(context, 'Customer', 'Asiakas') : u.name,
                                style: const TextStyle(fontWeight: FontWeight.w700)),
                            trailing: _busy.contains(u.id)
                                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                                : TextButton(
                                    onPressed: () => _unblock(u),
                                    style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                                    child: Text(tr(context, 'Unblock', 'Poista esto')),
                                  ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _message(BuildContext context, IconData icon, String title, String body) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: MSpace.xxl, vertical: MSpace.x4l),
        child: Column(
          children: [
            Icon(icon, size: 40, color: AppTheme.secondaryText(context)),
            const SizedBox(height: MSpace.md),
            Text(title, textAlign: TextAlign.center, style: AppTheme.display(context, size: 18)),
            const SizedBox(height: 6),
            Text(body, textAlign: TextAlign.center, style: TextStyle(fontSize: MTextSize.label, height: 1.4, color: AppTheme.secondaryText(context))),
          ],
        ),
      );
}
