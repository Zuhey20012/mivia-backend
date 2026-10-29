import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:malvoya_core/malvoya_core.dart';
import 'package:malvoya_ui/malvoya_ui.dart';
import '../auth_service.dart';
import '../config/theme.dart';

/// "How results are sorted" (DSA Art. 27, Omnibus): the server's own description of the search
/// order (`GET /products/ranking`), shown as it is written. Nothing is invented here: when the
/// server has no description, the sheet says it could not be loaded.
Future<void> showSearchRankingSheet(BuildContext context) async {
  Haptics.selection();
  final res = await ApiClient(Provider.of<AuthService>(context, listen: false)).get('/products/ranking');
  if (!context.mounted) return;
  if (!res.ok) {
    MSnack.error(context, res.status == 404
        ? tr(context, 'The description of the search order is not available yet.', 'Hakujärjestyksen kuvaus ei ole vielä saatavilla.')
        : (res.errorText(context) ?? tr(context, 'Could not load it. Try again.', 'Lataus ei onnistunut. Yritä uudelleen.')));
    return;
  }
  final sections = _sectionsOf(context, res.data['ranking'] ?? res.data);
  final profiling = res.data['personalProfiling'] ?? (res.data['ranking'] is Map ? res.data['ranking']['personalProfiling'] : null);
  final note = localized(context, res.data['note'] ?? (res.data['ranking'] is Map ? res.data['ranking']['note'] : null));
  await showMSheet<void>(context, builder: (ctx) {
    final muted = AppTheme.secondaryText(ctx);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.8),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(MSpace.xl, MSpace.sm, MSpace.xl, MSpace.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(tr(ctx, 'How results are sorted', 'Miten tulokset järjestetään'), style: AppTheme.display(ctx, size: 20)),
              const SizedBox(height: MSpace.md),
              if (sections.isEmpty)
                Text(tr(ctx, 'The description could not be read. Try again later.', 'Kuvausta ei voitu lukea. Yritä myöhemmin uudelleen.'),
                    style: TextStyle(color: muted)),
              for (final (title, lines) in sections) ...[
                if (title != null)
                  Padding(
                    padding: const EdgeInsets.only(top: MSpace.sm, bottom: MSpace.xs),
                    child: Text(title, style: TextStyle(fontWeight: FontWeight.w800, color: AppTheme.primaryText(ctx))),
                  ),
                for (final line in lines)
                  Padding(
                    padding: const EdgeInsets.only(bottom: MSpace.xs),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 7, right: 10),
                          child: Container(width: 6, height: 6, decoration: BoxDecoration(color: muted, shape: BoxShape.circle)),
                        ),
                        Expanded(child: Text(line, style: TextStyle(fontSize: MTextSize.bodyM, height: 1.4, color: AppTheme.primaryText(ctx)))),
                      ],
                    ),
                  ),
              ],
              if (profiling == false) ...[
                const SizedBox(height: MSpace.md),
                Text(
                  tr(ctx, 'Results are not personalised: no profile of you is used.', 'Tuloksia ei personoida: sinusta ei käytetä profiilia.'),
                  style: TextStyle(fontSize: MTextSize.label, color: muted, height: 1.4),
                ),
              ],
              if (note != null) ...[
                const SizedBox(height: MSpace.md),
                Text(note, style: TextStyle(fontSize: MTextSize.label, color: muted, height: 1.4)),
              ],
            ],
          ),
        ),
      ),
    );
  }, isScrollControlled: true, useSafeArea: true);
}

/// Sort keys the search uses, with the app's own names for them.
String? _sortTitle(BuildContext context, String key) => switch (key) {
      'relevance' || 'recommended' => tr(context, 'Recommended', 'Suositellut'),
      'newest' || 'latest' => tr(context, 'Newest', 'Uusimmat'),
      'price_asc' => tr(context, 'Price: low to high', 'Hinta: halvin ensin'),
      'price_desc' => tr(context, 'Price: high to low', 'Hinta: kallein ensin'),
      'rating' => tr(context, 'Best rated stores', 'Parhaat arviot'),
      _ => null,
    };

/// Turns the server's description into titled lists of sentences. Accepts a string, a list of
/// strings ({en, fi} or plain), or a map of sort key → those.
List<(String?, List<String>)> _sectionsOf(BuildContext context, dynamic value) {
  List<String> lines(dynamic v) {
    if (v is List) return v.map((e) => localized(context, e)).whereType<String>().toList();
    final one = localized(context, v);
    return one == null ? const [] : [one];
  }

  if (value is Map) {
    // {en, fi} text, or {en: [...], fi: [...]}
    if (value.containsKey('en') || value.containsKey('fi')) {
      final picked = isFinnish(context) ? (value['fi'] ?? value['en']) : (value['en'] ?? value['fi']);
      return _sectionsOf(context, picked);
    }
    final out = <(String?, List<String>)>[];
    for (final e in value.entries) {
      final key = '${e.key}';
      if (key == 'personalProfiling' || key == 'note' || key == 'ok') continue;
      final l = lines(e.value);
      if (l.isEmpty) continue;
      out.add((_sortTitle(context, key) ?? key, l));
    }
    return out;
  }
  final l = lines(value);
  return l.isEmpty ? const [] : [(null, l)];
}
