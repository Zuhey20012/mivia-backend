import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../auth_service.dart';
import '../config/theme.dart';
import '../core/agreements.dart';
import '../core/api_client.dart';
import '../core/location_disclosure.dart';
import '../core/strings.dart';
import '../screens/payouts_screen.dart';
import 'courier_profile_sheets.dart';

/// The server's onboarding checklist (`GET /courier/me/onboarding`, API 2.11): progress and one
/// row per step; each open step opens the screen that completes it. Approval itself is always a
/// person's decision on the server; nothing here approves anyone.
///
/// [compact] (dashboard): a collapsible card, hidden once everything is done.
/// Full (pending-approval screen): the whole list, and [fallback] when the server has no
/// checklist (404: an older API) or the first load fails.
class OnboardingChecklist extends StatefulWidget {
  final bool compact;
  final Widget? fallback;
  /// Hidden while true without losing what was loaded (e.g. during a delivery).
  final bool suppressed;
  /// Called after each load with the server's answer (null when there is none).
  final ValueChanged<Map<String, dynamic>?>? onLoaded;

  const OnboardingChecklist({super.key, this.compact = false, this.fallback, this.suppressed = false, this.onLoaded});

  @override
  State<OnboardingChecklist> createState() => OnboardingChecklistState();
}

class OnboardingChecklistState extends State<OnboardingChecklist> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  bool _unsupported = false;
  String? _error;
  bool _expanded = false;
  String? _busy;

  AuthService get _auth => Provider.of<AuthService>(context, listen: false);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => reload());
  }

  Future<void> reload({bool synced = false}) async {
    if (!mounted) return;
    final res = await ApiClient(_auth).get('/courier/me/onboarding');
    if (!mounted) return;
    if (res.ok) {
      final courier = res.data['courier'] is Map ? res.data['courier'] as Map : null;
      // Accepted the disclosure on this phone before the server recorded it: send it once
      if (!synced && await LocationDisclosure.syncIfMissing(courier)) return reload(synced: true);
      if (!mounted) return;
    }
    setState(() {
      _loading = false;
      _unsupported = res.status == 404;
      if (res.ok) {
        _data = res.data;
        _error = null;
      } else if (_data == null) {
        _error = res.error;
      }
    });
    widget.onLoaded?.call(res.ok ? res.data : null);
  }

  List<Map<String, dynamic>> get _steps =>
      ((_data?['steps'] as List?) ?? const []).whereType<Map>().map((s) => Map<String, dynamic>.from(s)).toList();

  bool get _approved => _data?['approved'] == true;
  bool get _complete => _approved && _steps.every((s) => s['done'] == true);

  Future<void> _run(Map<String, dynamic> step) async {
    final action = '${step['action'] ?? ''}';
    if (_busy != null) return;
    HapticFeedback.selectionClick();
    setState(() => _busy = '${step['key']}');
    var changed = false;
    switch (action) {
      case 'edit_profile':
        changed = await showCourierProfileSheet(context);
      case 'set_vehicle':
        final current = _data?['courier'] is Map ? (_data!['courier'] as Map)['vehicleType'] as String? : null;
        changed = await showVehiclePicker(context, current: current) != null;
      case 'connect_payouts':
        await Navigator.push(context, MaterialPageRoute(builder: (_) => const PayoutsScreen()));
        changed = true;
      case 'accept_agreement':
        changed = await Agreements.reviewDoc(context, _auth, Agreements.courierAgreement);
      case 'location_disclosure':
        // Recorded on the server before the list reloads
        changed = await LocationDisclosure.show(context, awaitReport: true);
      default:
        break;
    }
    if (!mounted) return;
    setState(() => _busy = null);
    if (changed) await reload();
  }

  bool _actionable(Map<String, dynamic> step) {
    final action = step['action'];
    if (step['done'] == true) return action == 'edit_profile' || action == 'set_vehicle' || action == 'connect_payouts';
    return const ['edit_profile', 'set_vehicle', 'connect_payouts', 'accept_agreement', 'location_disclosure'].contains(action);
  }

  (IconData, String?) _stepCopy(Map<String, dynamic> step) {
    final done = step['done'] == true;
    return switch (step['key']) {
      'profile' => (Icons.badge_outlined, tr(context, 'So the Malvoya team can reach you.', 'Jotta Malvoyan tiimi tavoittaa sinut.')),
      'vehicle' => (
          vehicleIcon(_data?['courier'] is Map ? (_data!['courier'] as Map)['vehicleType'] as String? : null),
          done && _data?['courier'] is Map && (_data!['courier'] as Map)['vehicleType'] is String
              ? vehicleLabel(context, (_data!['courier'] as Map)['vehicleType'] as String)
              : tr(context, 'Bicycle, e-bike, moped, scooter, car or on foot.', 'Pyörä, sähköpyörä, mopo, potkulauta, auto tai kävellen.'),
        ),
      'payouts' => (
          Icons.account_balance_outlined,
          done
              ? tr(context, 'Your pay goes to your own Stripe account.', 'Palkkiosi menee omalle Stripe-tilillesi.')
              : tr(context, 'Stripe checks your identity and bank account on its own pages.', 'Stripe tarkistaa henkilöllisyytesi ja pankkitilisi omilla sivuillaan.'),
        ),
      'agreement' => (Icons.gavel_rounded, done ? null : tr(context, 'Read the summary and accept it in the app.', 'Lue tiivistelmä ja hyväksy se sovelluksessa.')),
      'location_disclosure' => (
          Icons.location_on_outlined,
          done ? null : tr(context, 'Read how your location is used while you are online.', 'Lue, miten sijaintiasi käytetään, kun olet linjoilla.'),
        ),
      'approved' => (
          Icons.person_search_outlined,
          done ? null : tr(context, 'A person at Malvoya reviews your application.', 'Malvoyan työntekijä käsittelee hakemuksesi.'),
        ),
      _ => (Icons.radio_button_unchecked_rounded, null),
    };
  }

  @override
  Widget build(BuildContext context) {
    if (widget.suppressed) return const SizedBox.shrink();
    if (_loading) {
      return widget.compact ? const SizedBox.shrink() : const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
    }
    if (_data == null) {
      // An older server, or the first load failed: the screen's own text, or nothing on the dashboard
      if (widget.compact) return const SizedBox.shrink();
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (!_unsupported && _error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(children: [
              Expanded(child: Text(_error!, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13))),
              TextButton(style: TextButton.styleFrom(minimumSize: const Size(48, 48)), onPressed: reload, child: Text(tr(context, 'Try again', 'Yritä uudelleen'))),
            ]),
          ),
        if (widget.fallback != null) widget.fallback!,
      ]);
    }
    if (widget.compact && _complete) return const SizedBox.shrink();

    final steps = _steps;
    final done = steps.where((s) => s['done'] == true).length;
    final percent = (asInt(_data?['percent']) ?? (steps.isEmpty ? 0 : (done * 100 / steps.length).round())).clamp(0, 100);
    final ready = _data?['readyForApproval'] == true && !_approved;
    final showSteps = !widget.compact || _expanded;

    final header = Row(children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            _approved ? tr(context, 'Finish your courier profile', 'Viimeistele lähettiprofiilisi') : tr(context, 'Your steps to approval', 'Vaiheesi hyväksyntään'),
            style: AppTheme.display(size: widget.compact ? 17 : 20),
          ),
          const SizedBox(height: 2),
          Text(tr(context, '$done of ${steps.length} done', '$done/${steps.length} tehty'),
              style: const TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600, fontSize: 13)),
        ]),
      ),
      Text('$percent %', style: AppTheme.display(size: widget.compact ? 18 : 22, color: AppTheme.primary)),
      if (widget.compact) ...[
        const SizedBox(width: 4),
        Icon(_expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded),
      ],
    ]);

    final body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      widget.compact
          ? InkWell(
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              onTap: () => setState(() => _expanded = !_expanded),
              child: ConstrainedBox(constraints: const BoxConstraints(minHeight: 48), child: Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: header)),
            )
          : header,
      const SizedBox(height: 10),
      Semantics(
        label: tr(context, '$percent percent done', '$percent prosenttia tehty'),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(value: percent / 100, minHeight: 8, backgroundColor: AppTheme.sand, color: AppTheme.success),
        ),
      ),
      if (ready) ...[
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: AppTheme.lilac, borderRadius: BorderRadius.circular(AppTheme.radiusMd)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.how_to_reg_outlined, color: AppTheme.malva),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                tr(context,
                    'Everything on your side is done. The Malvoya team reviews your application next. A person checks it by hand, so it is not instant; you get a notification and an email when you are approved.',
                    'Kaikki sinun osaltasi on tehty. Seuraavaksi Malvoyan tiimi käsittelee hakemuksesi. Ihminen tarkistaa sen käsin, joten se ei tapahdu heti; saat ilmoituksen ja sähköpostin, kun sinut on hyväksytty.'),
                style: const TextStyle(color: AppTheme.malva, height: 1.4, fontWeight: FontWeight.w600),
              ),
            ),
          ]),
        ),
      ],
      if (showSteps) ...[
        const SizedBox(height: 6),
        for (final s in steps) _row(s),
      ],
    ]);

    return Container(
      margin: widget.compact ? const EdgeInsets.fromLTRB(16, 8, 16, 0) : EdgeInsets.zero,
      padding: EdgeInsets.fromLTRB(16, widget.compact ? 6 : 16, 12, widget.compact ? 10 : 8),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(AppTheme.radiusLg), border: Border.all(color: AppTheme.divider)),
      child: body,
    );
  }

  Widget _row(Map<String, dynamic> step) {
    final done = step['done'] == true;
    final (icon, hint) = _stepCopy(step);
    final title = localizedText(context, step['title']) ?? '${step['key'] ?? ''}';
    final tappable = _actionable(step);
    final busy = _busy == '${step['key']}';
    return Semantics(
      button: tappable,
      label: '$title, ${done ? tr(context, 'done', 'tehty') : tr(context, 'not done yet', 'ei vielä tehty')}',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        onTap: tappable && _busy == null ? () => _run(step) : null,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(color: done ? AppTheme.success : AppTheme.primaryLight, shape: BoxShape.circle),
                child: Icon(done ? Icons.check_rounded : icon, size: 20, color: done ? Colors.white : AppTheme.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title,
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: done ? AppTheme.textSecondary : AppTheme.textPrimary)),
                  if (hint != null)
                    Text(hint, style: const TextStyle(fontSize: 13, height: 1.3, color: AppTheme.textSecondary)),
                ]),
              ),
              if (busy)
                const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
              else if (tappable)
                const Padding(padding: EdgeInsets.all(8), child: Icon(Icons.chevron_right_rounded, color: AppTheme.textSecondary)),
            ]),
          ),
        ),
      ),
    );
  }
}
