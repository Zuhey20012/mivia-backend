import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../auth_service.dart';
import '../config/theme.dart';
import '../core/strings.dart';
import '../widgets/loading_states.dart';
import 'pending_approval.dart';
import 'store_setup.dart';
import 'vendor_dashboard.dart';

/// The signed-in home. Decides from the server's answer (GET /stores/my) what to show, so no screen
/// has to push or replace routes when the account changes: welcome → store setup → dashboard.
class VendorHome extends StatefulWidget {
  const VendorHome({super.key});

  @override
  State<VendorHome> createState() => _VendorHomeState();
}

class _VendorHomeState extends State<VendorHome> {
  /// The welcome screen's "Set up my store" was tapped.
  bool _setupStarted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = Provider.of<AuthService>(context, listen: false);
      if (auth.storeState == StoreState.unknown) auth.checkStore();
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    switch (auth.storeState) {
      case StoreState.unknown:
        return const Scaffold(backgroundColor: AppTheme.background, body: SafeArea(child: SkeletonList(button: true)));
      case StoreState.error:
        return Scaffold(
          backgroundColor: AppTheme.background,
          body: SafeArea(
            child: ListView(children: [
              ErrorState(message: auth.storeError, onRetry: auth.checkStore),
              Center(
                child: TextButton(
                  onPressed: auth.logout,
                  child: Text(tr(context, 'Sign out', 'Kirjaudu ulos'), style: const TextStyle(color: AppTheme.textSecondary)),
                ),
              ),
            ]),
          ),
        );
      case StoreState.none:
        return _setupStarted
            ? const StoreSetupScreen()
            : PendingApprovalScreen(onStart: () => setState(() => _setupStarted = true));
      case StoreState.inReview:
      case StoreState.approved:
        return const VendorDashboard();
    }
  }
}
