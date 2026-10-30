import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:malvoya_core/malvoya_core.dart';
import 'package:malvoya_ui/malvoya_ui.dart';
import '../auth_service.dart';
import '../config/theme.dart';

import '../core/blocked_users.dart';

/// The few reasons offered when reporting a comment or a review (keys of the API's REPORT_REASONS).
const _shortReasons = {
  'HARASSMENT': ['Harassment or bullying', 'Häirintä tai kiusaaminen'],
  'HATE': ['Hate speech', 'Vihapuhe'],
  'SCAM': ['Spam, scam or misleading', 'Roskaposti, huijaus tai harhaanjohtava'],
  'NUDITY': ['Sexual content', 'Seksuaalinen sisältö'],
  'VIOLENCE': ['Violence or threats', 'Väkivalta tai uhkailu'],
  'OTHER': ['Something else', 'Jokin muu'],
};

/// Copyright and trademark (comments only; they need the notice form, API 2.16)
const _ipReasons = {
  'COPYRIGHT': ['Copyright: uses my work', 'Tekijänoikeus: käyttää teostani'],
  'TRADEMARK': ['Trademark: uses my brand', 'Tavaramerkki: käyttää tavaramerkkiäni'],
};

/// Asks why the content is reported. Returns the reason key, or null if the customer cancelled.
/// [includeIp] adds copyright and trademark (drop comments).
Future<String?> pickReportReason(BuildContext context, {required String title, bool includeIp = false}) {
  return showMSheet<String>(context, builder: (ctx) {
      String? selected;
      return StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(MSpace.lg, 0, MSpace.lg, MSpace.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: MSpace.sm),
                  child: Text(title, style: AppTheme.display(ctx, size: 20)),
                ),
                const SizedBox(height: MSpace.xs),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: MSpace.sm),
                  child: Text(
                    tr(ctx, 'Our team reviews every report. The person is not told who reported them.',
                        'Tiimimme käy jokaisen ilmoituksen läpi. Henkilölle ei kerrota, kuka ilmoitti.'),
                    style: TextStyle(fontSize: MTextSize.label, color: AppTheme.secondaryText(ctx)),
                  ),
                ),
                const SizedBox(height: MSpace.sm),
                RadioGroup<String>(
                  groupValue: selected,
                  onChanged: (v) => setSheet(() => selected = v),
                  child: Column(
                    children: [
                      for (final e in {..._shortReasons, if (includeIp) ..._ipReasons}.entries)
                        RadioListTile<String>(
                          value: e.key,
                          title: Text(isFinnish(ctx) ? e.value[1] : e.value[0]),
                          contentPadding: const EdgeInsets.symmetric(horizontal: MSpace.xs),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: MSpace.sm),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: selected == null ? null : () => Navigator.pop(ctx, selected),
                    child: Text(tr(ctx, 'Send report', 'Lähetä ilmoitus')),
                  ),
                ),
                Center(
                  child: TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                    child: Text(tr(ctx, 'Cancel', 'Peruuta')),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }, isScrollControlled: true, useSafeArea: true);
}

/// Confirms and blocks [userId]. Their comments and reviews disappear at once. Returns true when
/// the server saved the block.
Future<bool> confirmAndBlock(BuildContext context, {required int userId, required String name}) async {
  final shown = name.trim().isEmpty ? tr(context, 'this person', 'tämä henkilö') : name.trim();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(tr(ctx, 'Block $shown?', 'Estetäänkö $shown?')),
      content: Text(tr(
        ctx,
        'You will no longer see their comments or reviews. They are not told. You can unblock them in Profile → Blocked users.',
        'Et enää näe hänen kommenttejaan etkä arvioitaan. Hänelle ei kerrota tästä. Voit poistaa eston kohdassa Profiili → Estetyt käyttäjät.',
      )),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr(ctx, 'Cancel', 'Peruuta'))),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: TextButton.styleFrom(foregroundColor: MPalette.red),
          child: Text(tr(ctx, 'Block', 'Estä')),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return false;
  final auth = Provider.of<AuthService>(context, listen: false);
  final error = await BlockedUsers.instance.block(auth, userId, name.trim());
  if (!context.mounted) return error == null;
  MSnack.show(context, error == null
        ? tr(context, '$shown is blocked.', '$shown on estetty.')
        : tr(context, 'Could not block: ${localizeServerMessage(context, error)}', 'Estäminen ei onnistunut: ${localizeServerMessage(context, error)}'));
  return error == null;
}

/// The actions offered on someone else's comment or review, as a bottom sheet (long-press) —
/// the same items as the ⋮ menu.
Future<String?> showUgcActions(BuildContext context, {required bool canReport, required bool canBlock, bool canDelete = false}) {
  return showMSheet<String>(context, builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (canDelete)
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded),
              title: Text(tr(ctx, 'Delete', 'Poista')),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
          if (canReport)
            ListTile(
              leading: const Icon(Icons.flag_outlined),
              title: Text(tr(ctx, 'Report', 'Ilmoita')),
              onTap: () => Navigator.pop(ctx, 'report'),
            ),
          if (canBlock)
            ListTile(
              leading: const Icon(Icons.block_rounded, color: MPalette.red),
              title: Text(tr(ctx, 'Block user', 'Estä käyttäjä'), style: const TextStyle(color: MPalette.red)),
              onTap: () => Navigator.pop(ctx, 'block'),
            ),
          const SizedBox(height: MSpace.sm),
        ],
      ),
    ), isScrollControlled: false, useSafeArea: true);
}

/// The public author id on a comment or review payload, when the server sends one.
int? authorIdOf(Map<String, dynamic> item) {
  final v = item['authorId'];
  return v is int ? v : int.tryParse('${v ?? ''}');
}
