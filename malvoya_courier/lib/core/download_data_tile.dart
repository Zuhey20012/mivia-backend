import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:malvoya_core/malvoya_core.dart';
import 'package:malvoya_ui/malvoya_ui.dart';
import '../auth_service.dart';

/// Account setting: download a copy of everything the server holds about this account (GDPR Art. 15
/// and 20, `GET /auth/me/data`), as in the customer app's Privacy screen. The JSON file is shown in a
/// sheet, then shared or saved through the phone's share menu (Files, Drive, email…) or copied.
class DownloadDataTile extends StatefulWidget {
  final Widget? leading;

  const DownloadDataTile({super.key, this.leading});

  @override
  State<DownloadDataTile> createState() => _DownloadDataTileState();
}

class _DownloadDataTileState extends State<DownloadDataTile> {
  bool _busy = false;

  Future<void> _download() async {
    final auth = Provider.of<AuthService>(context, listen: false);
    Haptics.selection();
    setState(() => _busy = true);
    final res = await ApiClient(auth).get('/auth/me/data');
    if (!mounted) return;
    setState(() => _busy = false);
    if (!res.ok) {
      MSnack.error(context, res.errorText(context) ?? tr(context, 'Could not get your data. Please try again.', 'Tietojasi ei saatu. Yritä uudelleen.'));
      return;
    }
    final json = const JsonEncoder.withIndent('  ').convert(res.data);
    await showMSheet<void>(context, builder: (_) => _DataSheet(json: json));
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: widget.leading ?? const Icon(Icons.download_rounded),
      title: Text(tr(context, 'Download my data', 'Lataa tietoni'), style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(tr(context, 'A copy of your account data as a file', 'Kopio tilisi tiedoista tiedostona')),
      trailing: _busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : null,
      onTap: _busy ? null : _download,
    );
  }
}

class _DataSheet extends StatelessWidget {
  final String json;

  const _DataSheet({required this.json});

  String get _fileName {
    final d = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return 'malvoya-data-${d.year}-${two(d.month)}-${two(d.day)}.json';
  }

  Future<void> _share(BuildContext context, Rect? origin) async {
    Haptics.selection();
    final name = _fileName;
    try {
      final result = await SharePlus.instance.share(ShareParams(
        files: [XFile.fromData(utf8.encode(json), mimeType: 'application/json', name: name)],
        fileNameOverrides: [name],
        subject: tr(context, 'My Malvoya data', 'Malvoya-tietoni'),
        sharePositionOrigin: origin,
      ));
      if (result.status == ShareResultStatus.unavailable && context.mounted) await _copy(context);
    } catch (_) {
      // No share menu on this phone: the text can still be copied
      if (context.mounted) await _copy(context);
    }
  }

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: json));
    if (!context.mounted) return;
    MSnack.success(context, tr(context, 'Your data was copied. Paste it into a file or an email to keep it.',
        'Tietosi kopioitiin. Liitä ne tiedostoon tai sähköpostiin säilyttääksesi ne.'));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.mColors;
    final kb = (utf8.encode(json).length / 1024).ceil();
    return MSheet(
      title: tr(context, 'Your data', 'Tietosi'),
      subtitle: tr(context, 'Everything Malvoya holds about your account, in a machine-readable JSON file ($kb kB).',
          'Kaikki, mitä Malvoya säilyttää tilistäsi, koneluettavana JSON-tiedostona ($kb kt).'),
      actions: [
        Builder(
          builder: (btnContext) => MButton(
            label: tr(context, 'Save or share the file', 'Tallenna tai jaa tiedosto'),
            icon: Icons.ios_share_rounded,
            expand: true,
            onPressed: () {
              final box = btnContext.findRenderObject() as RenderBox?;
              final origin = box == null || !box.hasSize ? null : box.localToGlobal(Offset.zero) & box.size;
              _share(context, origin);
            },
          ),
        ),
        MButton(
          label: tr(context, 'Copy', 'Kopioi'),
          icon: Icons.copy_rounded,
          variant: MButtonVariant.outline,
          expand: true,
          onPressed: () => _copy(context),
        ),
        MButton(
          label: tr(context, 'Read what is in your download', 'Lue, mitä latauksesi sisältää'),
          variant: MButtonVariant.text,
          expand: true,
          onPressed: () => openLegal('data-explained'),
        ),
      ],
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.4),
        child: DecoratedBox(
          decoration: BoxDecoration(color: c.surfaceVariant, borderRadius: MRadius.brMd, border: Border.all(color: c.outline)),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(MSpace.md),
            child: SelectableText(json, style: MType.caption.copyWith(fontFamily: 'monospace', color: c.onSurface)),
          ),
        ),
      ),
    );
  }
}
