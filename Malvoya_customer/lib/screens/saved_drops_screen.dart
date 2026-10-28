import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:malvoya_core/malvoya_core.dart';
import 'package:malvoya_ui/malvoya_ui.dart';
import '../auth_service.dart';
import '../core/sign_in.dart';
import '../widgets/drop_grid.dart';
import 'drops_feed.dart';
import 'main_navigation.dart';

/// Drops the customer saved with the bookmark, newest saves first. Tapping one opens the reel over this list.
class SavedDropsScreen extends StatefulWidget {
  const SavedDropsScreen({super.key});

  @override
  State<SavedDropsScreen> createState() => _SavedDropsScreenState();
}

class _SavedDropsScreenState extends State<SavedDropsScreen> {
  /// Changes after signing in, so the grid starts again.
  int _generation = 0;

  Future<void> _openReel(List<Map<String, dynamic>> drops, String? cursor, int dropId) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DropsFeedScreen(
          saved: true,
          title: tr(context, 'Saved drops', 'Tallennetut dropit'),
          startDropId: dropId,
          initialDrops: drops,
          initialCursor: cursor,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = Provider.of<AuthService>(context).isAuthenticated;
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'Saved drops', 'Tallennetut dropit'))),
      body: !signedIn
          ? MStateMessage(
              icon: Icons.bookmark_border_rounded,
              message: tr(context, 'Sign in to save drops.', 'Kirjaudu sisään tallentaaksesi droppeja.'),
              actionLabel: tr(context, 'Sign in / Create account', 'Kirjaudu / Luo tili'),
              onAction: () async {
                if (await openSignIn(context) && mounted) setState(() => _generation++);
              },
            )
          : PagedDropGrid(
              key: ValueKey(_generation),
              path: '/me/saved-drops',
              onOpen: _openReel,
              // Drops unsaved or hidden in the reel leave the grid
              reloadOnReturn: true,
              header: const [SliverToBoxAdapter(child: SizedBox(height: MSpace.lg))],
              empty: MStateMessage(
                icon: Icons.bookmark_border_rounded,
                scrollable: false,
                top: MSpace.xl,
                title: tr(context, 'No saved drops yet', 'Ei vielä tallennettuja droppeja'),
                message: tr(context, 'Tap the bookmark on a drop to keep it here.', 'Tallenna droppi kirjanmerkillä, niin se löytyy täältä.'),
                actionLabel: tr(context, 'Watch drops', 'Katso droppeja'),
                actionIcon: Icons.play_circle_outline_rounded,
                onAction: () => openMainTab(context, MainTab.drops),
              ),
            ),
    );
  }
}
