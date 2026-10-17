import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../auth_service.dart';
import '../config/theme.dart';
import '../core/delete_account_tile.dart';
import '../core/legal_links.dart';
import '../core/push_service.dart';
import '../core/strings.dart';
import 'help_screen.dart';

/// Shown until an admin approves the courier on the server.
/// Identity and right-to-work documents are checked by the Malvoya team, never collected in this app.
/// This screen checks the status itself: when the app comes back to the foreground, when a push
/// arrives while it is open, and every minute while it is on screen. Once approved, the app's home
/// switches to the dashboard on its own.
class PendingApprovalScreen extends StatefulWidget {
  const PendingApprovalScreen({super.key});

  @override
  State<PendingApprovalScreen> createState() => _PendingApprovalScreenState();
}

class _PendingApprovalScreenState extends State<PendingApprovalScreen> with WidgetsBindingObserver {
  bool _checking = false;
  DateTime? _lastChecked;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startTimer();
    // A notification while this screen is open (such as the approval) checks the status at once
    PushService.instance.onReceive = (_) {
      if (mounted) _check(silent: true);
    };
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    PushService.instance.onReceive = null;
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _check(silent: true);
      _startTimer();
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _timer?.cancel();
      _timer = null;
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 60), (_) => _check(silent: true));
  }

  Future<void> _check({bool silent = false}) async {
    if (_checking) return;
    setState(() => _checking = true);
    final approved = await Provider.of<AuthService>(context, listen: false).refreshApprovalStatus();
    if (!mounted) return;
    setState(() {
      _checking = false;
      _lastChecked = DateTime.now();
    });
    if (!approved && !silent) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(context, 'Still under review. This screen keeps checking for you.', 'Vielä tarkistettavana. Tämä näkymä tarkistaa tilanteen puolestasi.'))),
      );
    }
  }

  String _time(DateTime t) => '${t.hour.toString().padLeft(2, '0')}.${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthService>(context);
    final name = (auth.currentUser?.name ?? '').split(' ').first;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 12),
              Center(
                child: Container(
                  width: 88,
                  height: 88,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: AppTheme.primaryLight, borderRadius: BorderRadius.circular(28)),
                  child: const Icon(Icons.hourglass_top_rounded, size: 40, color: AppTheme.primary),
                ),
              ),
              const SizedBox(height: 28),
              Text(
                name.isEmpty ? tr(context, 'Hi', 'Hei') : '${tr(context, 'Hi', 'Hei')} $name',
                textAlign: TextAlign.center,
                style: AppTheme.display(size: 28),
              ),
              const SizedBox(height: 10),
              Text(
                tr(context, 'Your courier application is being reviewed.', 'Lähettihakemuksesi on tarkistettavana.'),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, height: 1.4, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 32),
              _step(Icons.person_search_outlined, tr(context, 'A person reviews it', 'Hakemuksen käsittelee ihminen'),
                  tr(context,
                      'Approval is done by hand by the Malvoya team, not automatically. They check your identity, that you are at least 18 and your right to work in Finland. No documents are uploaded in this app; if the team needs something from you, they use the contact details you signed up with.',
                      'Malvoyan tiimi hyväksyy hakemukset käsin, ei automaattisesti. Tiimi tarkistaa henkilöllisyytesi, että olet vähintään 18-vuotias, ja oikeutesi tehdä työtä Suomessa. Asiakirjoja ei ladata tähän sovellukseen; jos tiimi tarvitsee sinulta jotain, se käyttää yhteystietoja, jotka annoit rekisteröityessäsi.')),
              _step(Icons.sync_rounded, tr(context, 'Check your status here', 'Tarkista tilanne täältä'),
                  tr(context,
                      'This screen checks your status by itself every minute while it is open, and whenever you come back to the app. When you are approved, the app opens your courier view here.',
                      'Tämä näkymä tarkistaa tilanteesi itse minuutin välein, kun se on auki, ja aina kun palaat sovellukseen. Kun hakemuksesi on hyväksytty, sovellus avaa lähettinäkymän tähän.')),
              _step(Icons.description_outlined, tr(context, 'Courier agreement', 'Lähettisopimus'),
                  tr(context, 'You deliver as an independent entrepreneur under the courier agreement. Please read it before your first delivery.',
                      'Toimitat itsenäisenä yrittäjänä lähettisopimuksen mukaisesti. Lue se ennen ensimmäistä toimitusta.')),
              _step(Icons.check_circle_outline, tr(context, 'Then: start delivering', 'Sitten: aloita toimitukset'),
                  tr(context, 'Once approved, go online when it suits you and accept the jobs you want. Malvoya is just starting, so jobs may be rare at first.',
                      'Hyväksynnän jälkeen mene linjoille silloin kun sinulle sopii ja ota haluamasi keikat. Malvoya on vasta aloittamassa, joten keikkoja voi aluksi olla harvoin.')),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => openLegal('couriers'),
                  icon: const Icon(Icons.gavel_rounded),
                  label: Text(tr(context, 'Read the courier agreement', 'Lue lähettisopimus')),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _checking ? null : () => _check(),
                  child: _checking
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(tr(context, 'Check status now', 'Tarkista tilanne nyt')),
                ),
              ),
              if (_lastChecked != null) ...[
                const SizedBox(height: 8),
                Text(
                  tr(context, 'Last checked at ${_time(_lastChecked!)}', 'Tarkistettu viimeksi klo ${_time(_lastChecked!)}'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12.5, color: AppTheme.textSecondary),
                ),
              ],
              const SizedBox(height: 20),
              Container(
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppTheme.divider)),
                child: Column(children: [
                  ListTile(
                    leading: const Icon(Icons.support_agent_rounded),
                    title: Text(tr(context, 'Help and contact', 'Apua ja yhteydenotto'), style: const TextStyle(fontWeight: FontWeight.w600)),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HelpScreen())),
                  ),
                  const Divider(height: 1),
                  const DeleteAccountTile(),
                ]),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => auth.logout(),
                  icon: const Icon(Icons.logout_rounded),
                  label: Text(tr(context, 'Sign out', 'Kirjaudu ulos')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _step(IconData icon, String title, String body) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppTheme.primary, size: 24),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                const SizedBox(height: 2),
                Text(body, style: const TextStyle(fontSize: 14, height: 1.35, color: AppTheme.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
