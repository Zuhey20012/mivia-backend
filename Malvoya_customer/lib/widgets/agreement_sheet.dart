import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../auth_service.dart';
import '../config/theme.dart';
import '../core/agreements.dart';
import '../core/api_client.dart';
import '../core/haptics.dart';
import '../core/legal_links.dart';
import '../core/strings.dart';

/// "Agreement update": what the document is, what changes (for an update), a link to the full
/// text, a required checkbox and Accept (`POST /me/agreements/accept`). Returns true once the
/// server recorded the acceptance. The customer can always close it ("Not now").
Future<bool> showAgreementSheet(BuildContext context, AgreementPrompt prompt) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final result = await showModalBottomSheet<_Accepted>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: false,
    backgroundColor: Colors.transparent,
    builder: (_) => _AgreementSheet(prompt: prompt),
  );
  if (result == null) return false;
  if (result.emailed && result.message != null) {
    messenger?.showSnackBar(SnackBar(content: Text(result.message!), behavior: SnackBarBehavior.floating));
  }
  return true;
}

class _Accepted {
  final bool emailed;
  final String? message;
  const _Accepted(this.emailed, this.message);
}

class _AgreementSheet extends StatefulWidget {
  final AgreementPrompt prompt;
  const _AgreementSheet({required this.prompt});

  @override
  State<_AgreementSheet> createState() => _AgreementSheetState();
}

class _AgreementSheetState extends State<_AgreementSheet> {
  late AgreementPrompt _prompt = widget.prompt;
  bool _checked = false;
  bool _busy = false;
  bool _retried = false;
  String? _error;
  String? _notice;
  /// The change summary of the version in force, read from the public version list when the
  /// prompt came without one (an update shown after it took effect).
  dynamic _loadedSummary;

  @override
  void initState() {
    super.initState();
    if (_prompt.isUpdate && !_hasText(_prompt.summary)) _loadSummary();
  }

  static bool _hasText(dynamic value) =>
      value is String ? value.trim().isNotEmpty : value is Map && value.values.any((v) => v is String && v.trim().isNotEmpty);

  Future<void> _loadSummary() async {
    final version = _prompt.version;
    final res = await const ApiClient().get('/legal/${_prompt.doc}/versions');
    if (!mounted || !res.ok || version != _prompt.version) return;
    final versions = res.data['versions'];
    if (versions is! List) return;
    for (final v in versions) {
      if (v is Map && v['version'] == version) {
        setState(() => _loadedSummary = v['summary']);
        return;
      }
    }
  }

  String _title(BuildContext context) =>
      localized(context, _prompt.title) ?? (_prompt.isPrivacy ? tr(context, 'Privacy Policy', 'Tietosuojaseloste') : tr(context, 'Terms of Service', 'Käyttöehdot'));

  Future<void> _openText() async {
    Haptics.light();
    final url = _prompt.url;
    final uri = url == null || url.isEmpty ? legalUrl(_prompt.doc == 'privacy' ? 'privacy' : 'terms') : Uri.parse(url);
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
      if (!ok) await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) setState(() => _error = tr(context, 'The text could not be opened. Please try again.', 'Tekstiä ei voitu avata. Yritä uudelleen.'));
    }
  }

  Future<void> _accept() async {
    if (!_checked || _busy) return;
    Haptics.medium();
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    final auth = context.read<AuthService>();
    final res = await ApiClient(auth).post('/me/agreements/accept', {'doc': _prompt.doc, 'version': _prompt.version});
    if (!mounted) return;
    if (res.ok) {
      final emailed = res.data['emailed'] == true;
      final message = emailed ? tr(context, 'A copy has been emailed to you.', 'Kopio on lähetetty sähköpostiisi.') : null;
      // The list (Profile banner, Agreements screen) follows the new state
      await Agreements.instance.load(auth);
      if (mounted) Navigator.pop(context, _Accepted(emailed, message));
      return;
    }
    if (res.status == 409 && !_retried) {
      // The version changed meanwhile: read the list again and take the version the server expects
      _retried = true;
      await Agreements.instance.load(auth);
      if (!mounted) return;
      final item = Agreements.instance.itemFor(_prompt.doc);
      if (item != null) {
        final wantsPending = _prompt.pending && item['pendingVersion'] != null;
        if (wantsPending ? item['pendingAccepted'] == true : item['accepted'] == true) {
          Navigator.pop(context, const _Accepted(false, null));
          return;
        }
        final fresh = Agreements.instance.promptFor(item, pending: wantsPending);
        if (fresh.version == _prompt.version) {
          setState(() => _busy = false);
          return _accept();
        }
        // A different text than the one shown: the customer reads and ticks it again
        setState(() {
          _prompt = fresh;
          _loadedSummary = null;
          _checked = false;
          _busy = false;
          _notice = tr(context, 'The text was just updated. Please read the new version and accept it.',
              'Teksti päivittyi juuri. Lue uusi versio ja hyväksy se.');
        });
        if (_prompt.isUpdate && !_hasText(_prompt.summary)) _loadSummary();
        return;
      }
    }
    setState(() {
      _busy = false;
      _error = res.errorText(context) ?? tr(context, 'Could not save. Please try again.', 'Tallennus ei onnistunut. Yritä uudelleen.');
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = _prompt;
    final textPrimary = AppTheme.primaryText(context);
    final textSecondary = AppTheme.secondaryText(context);
    final title = _title(context);
    final summary = localized(context, p.summary) ?? localized(context, _loadedSummary);
    final date = p.effectiveAt == null ? null : agreementDate(context, p.effectiveAt);

    final String eyebrow;
    final String explanation;
    if (p.isPrivacy) {
      eyebrow = p.pending && date != null
          ? tr(context, 'Changes on $date', 'Muuttuu $date')
          : tr(context, 'For your information', 'Tiedoksi');
      explanation = tr(context,
          'The Privacy Policy explains what data Malvoya uses and why. Reading it is for your information: there is nothing to consent to here.',
          'Tietosuojaselosteessa kerrotaan, mitä tietoja Malvoya käyttää ja miksi. Se on sinulle tiedoksi: tässä ei pyydetä suostumusta mihinkään.');
    } else if (p.pending) {
      eyebrow = date != null ? tr(context, 'Agreement update on $date', 'Sopimuspäivitys $date') : tr(context, 'Agreement update', 'Sopimuspäivitys');
      explanation = date != null
          ? tr(context,
              'Our $title change on $date. Nothing changes for you before then. You can read and accept the new version now; otherwise we will ask you before your first order after that date.',
              '$title muuttuvat $date. Siihen asti sinulle ei muutu mitään. Voit lukea ja hyväksyä uuden version jo nyt, tai kysymme sitä ensimmäisen tilauksesi yhteydessä tuon päivän jälkeen.')
          : tr(context, 'Our $title are changing. You can read and accept the new version now.',
              '$title muuttuvat. Voit lukea ja hyväksyä uuden version jo nyt.');
    } else if (p.isUpdate) {
      eyebrow = tr(context, 'Agreement update', 'Sopimuspäivitys');
      explanation = tr(context,
          'We have updated our $title. Please read the new version and accept it to keep ordering. Your bag stays as it is.',
          'Olemme päivittäneet ${title.toLowerCase()}. Lue uusi versio ja hyväksy se, niin voit jatkaa tilaamista. Ostoskassisi säilyy ennallaan.');
    } else {
      eyebrow = tr(context, 'Before your first order', 'Ennen ensimmäistä tilausta');
      explanation = tr(context,
          'To order on Malvoya, please read and accept our $title. They describe how buying, delivery and returns work between you, the shop and Malvoya.',
          'Jotta voit tilata Malvoyasta, lue ja hyväksy ${title.toLowerCase()}. Niissä kerrotaan, miten ostaminen, toimitus ja palautukset toimivat sinun, kaupan ja Malvoyan välillä.');
    }

    final checkboxText = p.isPrivacy
        ? tr(context, 'I have read the Privacy Policy', 'Olen lukenut tietosuojaselosteen')
        : p.doc == 'terms'
            ? tr(context, 'I have read and accept the Terms of Service', 'Olen lukenut ja hyväksyn käyttöehdot')
            : tr(context, 'I have read and accept the $title', 'Olen lukenut ja hyväksyn: ${title.toLowerCase()}');
    final readText = p.isPrivacy
        ? tr(context, 'Read the full privacy policy', 'Lue koko tietosuojaseloste')
        : p.doc == 'terms'
            ? tr(context, 'Read the full terms', 'Lue koko käyttöehdot')
            : tr(context, 'Read the full text', 'Lue koko teksti');
    final acceptText = p.isPrivacy ? tr(context, 'Mark as read', 'Merkitse luetuksi') : tr(context, 'Accept', 'Hyväksy');

    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.92),
      decoration: BoxDecoration(
        color: AppTheme.cardBackground(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 12, 20, 16 + MediaQuery.of(context).viewPadding.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: AppTheme.cardBorder(context), borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.pastel(context, AppTheme.sunshineLight, AppTheme.sunshine),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(eyebrow,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.isDarkMode(context) ? AppTheme.sunshine : const Color(0xFF8A5A00))),
            ),
            const SizedBox(height: 12),
            Semantics(header: true, child: Text(title, style: AppTheme.display(context, size: 24))),
            const SizedBox(height: 10),
            Text(explanation, style: TextStyle(fontSize: 14.5, height: 1.45, color: textPrimary)),
            if (p.isUpdate && summary != null) ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.pastel(context, AppTheme.lilac, AppTheme.primary),
                  borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr(context, 'What changes', 'Mitä muuttuu'),
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: textPrimary)),
                    const SizedBox(height: 6),
                    Text(summary, style: TextStyle(fontSize: 14, height: 1.45, color: textPrimary)),
                    const SizedBox(height: 8),
                    Text(
                      tr(context, 'This is Malvoya\'s short description of the change. The full text is what applies.',
                          'Tämä on Malvoyan lyhyt kuvaus muutoksesta. Voimassa on aina koko teksti.'),
                      style: TextStyle(fontSize: 12, height: 1.35, color: textSecondary),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: Text(readText),
                onPressed: _openText,
              ),
            ),
            const SizedBox(height: 10),
            Material(
              color: Colors.transparent,
              child: CheckboxListTile(
                value: _checked,
                onChanged: _busy
                    ? null
                    : (v) {
                        Haptics.selection();
                        setState(() {
                          _checked = v ?? false;
                          if (_checked) _error = null;
                        });
                      },
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                activeColor: AppTheme.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusSm)),
                title: Text(checkboxText, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: textPrimary)),
              ),
            ),
            if (_notice != null) ...[
              const SizedBox(height: 6),
              Text(_notice!, style: const TextStyle(fontSize: 13, height: 1.35, color: Color(0xFFB86E00))),
            ],
            if (_error != null) ...[
              const SizedBox(height: 6),
              Text(_error!, style: const TextStyle(fontSize: 13, height: 1.35, color: Color(0xFFD93025))),
            ],
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
                onPressed: _checked && !_busy ? _accept : null,
                child: _busy
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                    : Text(acceptText),
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                style: TextButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                onPressed: _busy ? null : () => Navigator.pop(context),
                child: Text(tr(context, 'Not now', 'Ei nyt')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
