import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../auth_service.dart';
import '../config/theme.dart';
import '../core/legal_links.dart';
import '../core/strings.dart';

/// Shown until an admin approves the courier on the server.
/// Identity and right-to-work documents are checked by the Malvoya team, never collected in this app.
/// The server sends no message on approval, so the courier checks the status here.
class PendingApprovalScreen extends StatefulWidget {
  const PendingApprovalScreen({super.key});

  @override
  State<PendingApprovalScreen> createState() => _PendingApprovalScreenState();
}

class _PendingApprovalScreenState extends State<PendingApprovalScreen> {
  bool _checking = false;

  Future<void> _checkStatus() async {
    setState(() => _checking = true);
    final approved = await Provider.of<AuthService>(context, listen: false).refreshApprovalStatus();
    if (!mounted) return;
    setState(() => _checking = false);
    if (!approved) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(context, 'Still under review. Please check again later.', 'Vielä tarkistettavana. Tarkista tilanne myöhemmin uudelleen.'))),
      );
    }
  }

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
                tr(context, 'Your courier account is being reviewed.', 'Lähettitilisi on tarkistettavana.'),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, height: 1.4, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 32),
              _step(Icons.badge_outlined, tr(context, 'Identity, age and right to work', 'Henkilöllisyys, ikä ja työnteko-oikeus'),
                  tr(context, 'The Malvoya team contacts you to check your identity, that you are at least 18 and your right to work in Finland. No documents are uploaded in this app.',
                      'Malvoyan tiimi ottaa sinuun yhteyttä tarkistaakseen henkilöllisyytesi, että olet vähintään 18-vuotias, ja oikeutesi tehdä työtä Suomessa. Asiakirjoja ei ladata tähän sovellukseen.')),
              _step(Icons.description_outlined, tr(context, 'Courier agreement', 'Lähettisopimus'),
                  tr(context, 'You deliver as an independent entrepreneur under the courier agreement. Please read it before your first delivery.',
                      'Toimitat itsenäisenä yrittäjänä lähettisopimuksen mukaisesti. Lue se ennen ensimmäistä toimitusta.')),
              _step(Icons.check_circle_outline, tr(context, 'Start delivering', 'Aloita toimitukset'),
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
                height: 52,
                child: ElevatedButton(
                  onPressed: _checking ? null : _checkStatus,
                  child: _checking
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(tr(context, 'Check status', 'Tarkista tilanne')),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => auth.logout(),
                child: Text(tr(context, 'Sign out', 'Kirjaudu ulos'), style: const TextStyle(color: AppTheme.textSecondary)),
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
