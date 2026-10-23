import 'dart:async';
import 'package:flutter/material.dart';
import 'package:malvoya_core/malvoya_core.dart';
import '../auth_service.dart';
import '../widgets/agreement_sheet.dart';

/// One document the customer is asked to accept (Terms of Service) or acknowledge (Privacy Policy),
/// in one exact version.
class AgreementPrompt {
  final String doc;
  final String version;
  final dynamic title; // {en, fi}
  final String? url;
  final dynamic summary; // {en, fi}, for an update
  /// When the version takes effect (set for an announced, not yet effective version).
  final DateTime? effectiveAt;
  /// An announced version: accepting is possible now but never required before [effectiveAt].
  final bool pending;
  /// The customer accepted an earlier version of the same document.
  final bool isUpdate;
  /// Orders are refused until it is accepted (false for the Privacy Policy, an acknowledgement).
  final bool blocking;

  const AgreementPrompt({
    required this.doc,
    required this.version,
    this.title,
    this.url,
    this.summary,
    this.effectiveAt,
    this.pending = false,
    this.isUpdate = false,
    this.blocking = true,
  });

  bool get isPrivacy => doc == 'privacy';
}

/// "1.11.2026" in Finnish, "1 Nov 2026" in English (local time).
String agreementDate(BuildContext context, dynamic value) {
  final d = parseApiDate(value);
  return d == null ? '' : dateText(context, d, short: true);
}

/// The customer's legal agreements (`GET /me/agreements`): what is required, what was accepted, and
/// the prompts. The sheet opens (a) once per app session after sign-in or app start when the Terms
/// in force are not accepted, and (b) whenever an order is refused with 428 AGREEMENT_REQUIRED.
class Agreements extends ChangeNotifier {
  Agreements._();
  static final Agreements instance = Agreements._();

  List<Map<String, dynamic>> required = const [];
  List<Map<String, dynamic>> history = const [];
  bool loaded = false;
  bool loading = false;
  String? error;

  AuthService? _auth;
  GlobalKey<NavigatorState>? _navigator;
  int? _userId;
  /// Accounts already shown the sheet after sign-in in this app session (no nag loop).
  final Set<int> _promptedAfterSignIn = {};
  Future<bool>? _open;

  /// Called once from main.dart with the app's AuthService and navigator.
  void attach(AuthService auth, GlobalKey<NavigatorState> navigator) {
    _auth = auth;
    _navigator = navigator;
    auth.addListener(_onAuthChanged);
    _onAuthChanged();
  }

  void _onAuthChanged() {
    final auth = _auth;
    final id = auth != null && auth.isAuthenticated ? auth.currentUser?.id : null;
    if (id == _userId) return;
    _userId = id;
    _reset();
    if (id != null) unawaited(_checkAfterSignIn(auth!, id));
  }

  void _reset() {
    required = const [];
    history = const [];
    loaded = false;
    error = null;
    notifyListeners();
  }

  /// Fetches the list. Returns false when it could not be read (offline, older server).
  Future<bool> load(AuthService auth) async {
    if (!auth.isAuthenticated) return false;
    final id = auth.currentUser?.id;
    loading = true;
    notifyListeners();
    final state = await AgreementsApi(ApiClient(auth)).load();
    loading = false;
    // Signed out or another account meanwhile: this answer is not theirs
    if (id != _userId && _userId != null) {
      notifyListeners();
      return false;
    }
    if (!state.ok) {
      error = state.error;
      notifyListeners();
      return false;
    }
    required = [for (final d in state.required) d.raw];
    history = state.history;
    loaded = true;
    error = null;
    notifyListeners();
    return true;
  }

  Map<String, dynamic>? itemFor(String doc) {
    for (final r in required) {
      if (r['doc'] == doc) return r;
    }
    return null;
  }

  bool _acceptedEarlier(String doc, String version) => history.any((h) => h['doc'] == doc && h['version'] != version);

  /// The first blocking document whose version in force is not accepted.
  AgreementPrompt? get missingBlocking {
    for (final r in required) {
      if (r['blocking'] == true && r['accepted'] != true) return promptFor(r);
    }
    return null;
  }

  /// An announced version not yet accepted (the soft "Terms update on …" banner).
  Map<String, dynamic>? get pendingNotice {
    for (final r in required) {
      if (r['pendingVersion'] != null && r['pendingAccepted'] != true) return r;
    }
    return null;
  }

  /// The prompt for one `required` item: its version in force, or with [pending] its announced one.
  AgreementPrompt promptFor(Map<String, dynamic> item, {bool pending = false}) {
    final doc = '${item['doc']}';
    final version = '${pending ? item['pendingVersion'] : item['currentVersion']}';
    return AgreementPrompt(
      doc: doc,
      version: version,
      title: item['title'],
      url: (pending ? item['pendingUrl'] : item['url'])?.toString(),
      summary: pending ? item['summary'] : null,
      effectiveAt: pending ? DateTime.tryParse('${item['pendingEffectiveAt'] ?? ''}') : null,
      pending: pending,
      isUpdate: pending || _acceptedEarlier(doc, version),
      blocking: item['blocking'] == true,
    );
  }

  Future<void> _checkAfterSignIn(AuthService auth, int id) async {
    // Let the sign-in screens close first (they pop the routes above the screen that opened them)
    await Future.delayed(const Duration(milliseconds: 1500));
    if (_userId != id || !auth.isAuthenticated) return;
    if (!await load(auth)) return;
    if (_userId != id || _promptedAfterSignIn.contains(id) || _open != null) return;
    final prompt = missingBlocking;
    if (prompt == null) return;
    final context = _navigator?.currentContext;
    if (context == null || !context.mounted) return;
    _promptedAfterSignIn.add(id);
    await _show(context, prompt);
  }

  Future<bool> _show(BuildContext context, AgreementPrompt prompt) {
    final open = _open;
    if (open != null) return open;
    final future = showAgreementSheet(context, prompt).whenComplete(() => _open = null);
    _open = future;
    return future;
  }

  /// [ApiClient.onAgreementRequired]: the server refused an order with 428. Shows the sheet for the
  /// document it names and returns true once it is accepted (the request is then sent again).
  Future<bool> handleRequired(ApiResult result, ApiSession? session) async {
    final auth = session is AuthService ? session : null;
    final data = result.data;
    try {
      final open = _open;
      if (open != null) return await open;
      final context = _navigator?.currentContext;
      if (context == null || !context.mounted || auth == null || !auth.isAuthenticated) return false;
      final doc = '${data['doc'] ?? 'terms'}';
      final version = data['version']?.toString();
      if (version == null || version.isEmpty) return false;
      // Knowing the history tells "new terms" from "changed terms"
      await load(auth);
      final item = itemFor(doc);
      if (item != null && item['currentVersion'] == version && item['accepted'] == true) return true;
      if (!context.mounted) return false;
      final prompt = AgreementPrompt(
        doc: doc,
        version: version,
        title: data['title'] ?? item?['title'],
        url: (data['url'] ?? item?['url'])?.toString(),
        isUpdate: _acceptedEarlier(doc, version),
        blocking: true,
      );
      return await _show(context, prompt);
    } catch (_) {
      return false;
    }
  }
}
