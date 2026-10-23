import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:malvoya_core/malvoya_core.dart';
import 'package:malvoya_ui/malvoya_ui.dart';
import '../auth_service.dart';
import '../config/theme.dart';
import '../screens/drops_feed.dart';
import '../screens/store_detail.dart';
import 'pending_promo.dart';

/// Android App Links (verified https links on the API host, see AndroidManifest.xml):
///   /d/<dropId>  → that drop in its store's drops
///   /s/<storeId> → the store
///   /r/<code>    → a friend's invite code, kept and filled in at the next checkout
/// Links that arrive before the app is signed in wait until the main screen is shown.
class DeepLinks {
  DeepLinks._();
  static final instance = DeepLinks._();

  static const host = 'malvoya-api-eu.onrender.com';

  GlobalKey<NavigatorState>? _navigator;
  StreamSubscription<Uri>? _sub;
  Uri? _pending;

  /// Main screens currently mounted (a language or theme switch briefly mounts two).
  int _screens = 0;
  bool get _ready => _screens > 0;
  String? _lastHandled;
  DateTime? _lastHandledAt;

  /// Starts listening; the stream also delivers the link that opened the app.
  void start(GlobalKey<NavigatorState> navigator) {
    _navigator = navigator;
    _sub ??= AppLinks().uriLinkStream.listen(_receive, onError: (_) {});
  }

  /// The main screen is up (signed in or browsing as a guest): handle any waiting link.
  void attach() {
    _screens++;
    final uri = _pending;
    _pending = null;
    if (uri != null) WidgetsBinding.instance.addPostFrameCallback((_) => _open(uri));
  }

  void detach() => _screens = _screens > 0 ? _screens - 1 : 0;

  void _receive(Uri uri) {
    if (uri.host != host || uri.pathSegments.length < 2) return;
    // The same link can be delivered twice (cold start + resume); open it once
    final now = DateTime.now();
    if (_lastHandled == uri.toString() && _lastHandledAt != null && now.difference(_lastHandledAt!) < const Duration(seconds: 3)) return;
    _lastHandled = uri.toString();
    _lastHandledAt = now;

    // An invite code is kept straight away, even before sign-in
    final code = _inviteCode(uri);
    if (code != null) unawaited(PendingPromo.instance.save(code));

    if (_ready && _navigator?.currentState != null) {
      _open(uri);
    } else {
      _pending = uri;
    }
  }

  String? _inviteCode(Uri uri) {
    if (uri.pathSegments.first != 'r') return null;
    final code = uri.pathSegments[1].trim().toUpperCase();
    return RegExp(r'^[A-Z0-9_-]{3,40}$').hasMatch(code) ? code : null;
  }

  Future<void> _open(Uri uri) async {
    final nav = _navigator?.currentState;
    final context = _navigator?.currentContext;
    if (nav == null || context == null) {
      _pending = uri;
      return;
    }
    final kind = uri.pathSegments.first;
    final id = int.tryParse(uri.pathSegments[1]);
    switch (kind) {
      case 's':
        if (id != null) nav.push(MaterialPageRoute(builder: (_) => StoreDetailScreen(store: {'id': id})));
      case 'd':
        if (id != null) await _openDrop(context, nav, id);
      case 'r':
        final code = _inviteCode(uri);
        if (code != null) _showInvite(context, code);
    }
  }

  Future<void> _openDrop(BuildContext context, NavigatorState nav, int dropId) async {
    final auth = Provider.of<AuthService>(context, listen: false);
    final res = await ApiClient(auth).get('/drops/$dropId');
    if (!context.mounted) return;
    final drop = res.data['drop'];
    final store = drop is Map ? drop['store'] : null;
    final storeId = store is Map ? asInt(store['id']) : null;
    if (!res.ok || storeId == null) {
      MSnack.show(context, res.status == 404
            ? tr(context, 'This drop is no longer available.', 'Tämä drop ei ole enää saatavilla.')
            : (res.errorText(context) ?? tr(context, 'The drop could not be opened.', 'Droppia ei voitu avata.')));
      return;
    }
    nav.push(MaterialPageRoute(
      builder: (_) => DropsFeedScreen(storeId: storeId, storeName: store['name']?.toString(), startDropId: dropId),
    ));
  }

  void _showInvite(BuildContext context, String code) {
    Haptics.light();
    showMSheet(context, builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(MSpace.xxl, 0, MSpace.xxl, MSpace.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr(ctx, 'You’ve been invited', 'Sinut on kutsuttu'), style: AppTheme.display(ctx, size: 22)),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppTheme.pastel(ctx, AppTheme.sunshineLight, AppTheme.sunshine),
                  borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                ),
                child: Text(code, style: AppTheme.display(ctx, size: 22).copyWith(letterSpacing: 2)),
              ),
              const SizedBox(height: MSpace.md),
              Text(
                tr(
                    ctx,
                    'We saved your friend’s invite code. It’s filled in at checkout, and Malvoya checks it there: invite codes work on a new customer’s first order.',
                    'Tallensimme ystäväsi kutsukoodin. Se täytetään kassalla valmiiksi, ja Malvoya tarkistaa sen siellä: kutsukoodi toimii uuden asiakkaan ensimmäiseen tilaukseen.'),
                style: TextStyle(fontSize: MTextSize.bodyM, height: 1.45, color: AppTheme.secondaryText(ctx)),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: FilledButton(
                  onPressed: () {
                    Haptics.selection();
                    Navigator.pop(ctx);
                  },
                  child: Text(tr(ctx, 'Start shopping', 'Aloita ostokset')),
                ),
              ),
            ],
          ),
        ),
      ), isScrollControlled: false, useSafeArea: false);
  }
}
