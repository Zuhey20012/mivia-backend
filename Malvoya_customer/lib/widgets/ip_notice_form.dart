import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:malvoya_core/malvoya_core.dart';
import 'package:malvoya_ui/malvoya_ui.dart';
import '../config/theme.dart';

/// Report keys that are copyright or trademark notices (API 2.16). Products use lower case, drops and
/// comments upper case.
bool isIpReportReason(String? reason) =>
    const {'copyright', 'trademark', 'COPYRIGHT', 'TRADEMARK'}.contains(reason);

/// The notice fields a copyright or trademark report must carry (DSA Art. 16(2)): name, email, the
/// work or mark, where it is used, and the good-faith statement. Returns the `ipNotice` object for
/// the API, or null when the person closed the form. How reports are handled: /legal/ip-notice.
Future<Map<String, dynamic>?> showIpNoticeForm(BuildContext context, {required String reason}) {
  return showMSheet<Map<String, dynamic>>(context, builder: (_) => _IpNoticeForm(trademark: reason.toLowerCase() == 'trademark'), isScrollControlled: true, useSafeArea: true);
}

class _IpNoticeForm extends StatefulWidget {
  final bool trademark;
  const _IpNoticeForm({required this.trademark});

  @override
  State<_IpNoticeForm> createState() => _IpNoticeFormState();
}

class _IpNoticeFormState extends State<_IpNoticeForm> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _work = TextEditingController();
  final _location = TextEditingController();
  final _onBehalfOf = TextEditingController();
  bool _goodFaith = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _email, _work, _location, _onBehalfOf]) {
      c.dispose();
    }
    super.dispose();
  }

  void _send() {
    final email = _email.text.trim();
    if (_name.text.trim().length < 2 || !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email) || _work.text.trim().length < 5 || _location.text.trim().length < 3) {
      setState(() => _error = tr(context, 'Fill in your name, a valid email, the work or mark and where it is used.',
          'Täytä nimesi, toimiva sähköpostiosoite, teos tai tavaramerkki ja sen käyttöpaikka.'));
      return;
    }
    if (!_goodFaith) {
      setState(() => _error = tr(context, 'Tick the good-faith statement to send the notice.', 'Rastita vilpittömän mielen vakuutus lähettääksesi ilmoituksen.'));
      return;
    }
    Navigator.pop(context, {
      'name': _name.text.trim(),
      'email': email,
      'work': _work.text.trim(),
      'location': _location.text.trim(),
      if (_onBehalfOf.text.trim().isNotEmpty) 'onBehalfOf': _onBehalfOf.text.trim(),
      'goodFaith': true,
    });
  }

  @override
  Widget build(BuildContext context) {
    final tm = widget.trademark;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: MSheet(
          title: tm ? tr(context, 'Trademark notice', 'Tavaramerkki-ilmoitus') : tr(context, 'Copyright notice', 'Tekijänoikeusilmoitus'),
          subtitle: tr(context, 'The law (EU Digital Services Act Art. 16) asks for these details. The seller is told what was reported, not your name or email.',
              'Laki (EU:n digipalvelusäädös, 16 artikla) edellyttää nämä tiedot. Myyjälle kerrotaan, mistä ilmoitettiin, mutta ei nimeäsi eikä sähköpostiasi.'),
          actions: [
            MButton(label: tr(context, 'Continue', 'Jatka'), expand: true, onPressed: _send),
            MButton(label: tr(context, 'Cancel', 'Peruuta'), variant: MButtonVariant.text, expand: true, onPressed: () => Navigator.pop(context)),
          ],
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            MTextField(controller: _name, label: tr(context, 'Your name', 'Nimesi'), textCapitalization: TextCapitalization.words, autofillHints: const [AutofillHints.name], maxLength: 120),
            const SizedBox(height: MSpace.sm),
            MTextField(controller: _email, label: tr(context, 'Your email', 'Sähköpostiosoitteesi'), keyboardType: TextInputType.emailAddress, autofillHints: const [AutofillHints.email], maxLength: 200),
            const SizedBox(height: MSpace.sm),
            MTextField(
              controller: _work,
              label: tm ? tr(context, 'The trademark', 'Tavaramerkki') : tr(context, 'Your work', 'Teoksesi'),
              hint: tm
                  ? tr(context, 'Name and registration number (e.g. EUIPO or PRH)', 'Nimi ja rekisterinumero (esim. EUIPO tai PRH)')
                  : tr(context, 'e.g. my photograph "Kallio at dusk" (2025)', 'esim. valokuvani "Kallio iltahämärässä" (2025)'),
              maxLines: 3,
              minLines: 1,
              maxLength: 500,
            ),
            const SizedBox(height: MSpace.sm),
            MTextField(
              controller: _location,
              label: tr(context, 'Where it is used', 'Missä sitä käytetään'),
              hint: tr(context, 'e.g. the second product photo, or the caption', 'esim. tuotteen toinen kuva tai kuvateksti'),
              maxLines: 2,
              minLines: 1,
              maxLength: 500,
            ),
            const SizedBox(height: MSpace.sm),
            MTextField(controller: _onBehalfOf, label: tr(context, 'Acting for (optional)', 'Kenen puolesta (valinnainen)'), maxLength: 200),
            Material(
              color: Colors.transparent,
              child: CheckboxListTile(
                value: _goodFaith,
                onChanged: (v) => setState(() {
                  _goodFaith = v ?? false;
                  if (_goodFaith) _error = null;
                }),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                activeColor: AppTheme.primary,
                title: Text(
                  tr(context, 'I believe in good faith that the information in this notice is accurate and complete.',
                      'Vakuutan vilpittömässä mielessä, että tämän ilmoituksen tiedot ovat oikeat ja täydelliset.'),
                  style: const TextStyle(fontSize: MTextSize.label, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => launchUrl(legalUrl('ip-notice'), mode: LaunchMode.inAppBrowserView),
                child: Text(tr(context, 'How we handle these notices', 'Miten käsittelemme ilmoitukset')),
              ),
            ),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: MPalette.red, fontSize: MTextSize.label, fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
    );
  }
}
