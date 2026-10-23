import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:malvoya_core/malvoya_core.dart';
import 'package:malvoya_ui/malvoya_ui.dart';
import '../config/theme.dart';
import '../l10n.dart';

/// Finnish or English for the whole app. A signed-in account also gets its push notifications and
/// emails in the chosen language (LocaleProvider tells the server).
Future<void> showLanguageSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: false, // the sheet draws its own handle
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(MRadius.lg)),
    ),
    builder: (ctx) {
      return Consumer<LocaleProvider>(
        builder: (context, provider, _) {
          return Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.75,
            ),
            padding: const EdgeInsets.fromLTRB(MSpace.xl, MSpace.lg, MSpace.xl, MSpace.xxl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40, height: 4,
                    decoration: BoxDecoration(color: AppTheme.divider, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: MSpace.lg),
                Text(tr(context, 'Choose language', 'Valitse kieli'), style: const TextStyle(fontSize: MTextSize.displayS, fontWeight: FontWeight.bold)),
                const SizedBox(height: MSpace.md),
                const Divider(height: 1),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    physics: const BouncingScrollPhysics(),
                    children: AppLocalizations.languages.entries.map((entry) {
                      final isSelected = provider.locale.languageCode == entry.key;
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: MSpace.md, vertical: 2),
                        title: Text(
                          entry.value,
                          style: TextStyle(
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                            fontSize: MTextSize.bodyL,
                            color: isSelected ? Theme.of(context).primaryColor : AppTheme.textPrimary,
                          ),
                        ),
                        trailing: isSelected ? Icon(Icons.check_circle_rounded, color: Theme.of(context).primaryColor) : null,
                        onTap: () {
                          provider.setLocale(Locale(entry.key));
                          Navigator.pop(ctx);
                        },
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}
