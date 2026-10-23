import 'package:malvoya_core/malvoya_core.dart';
import '../auth_service.dart';

/// Saves the app language on the account (`PATCH /me {locale}`), so pushes and emails come in the
/// language the customer reads the app in. The language itself is [AppLanguage.code] (malvoya_core),
/// kept up to date by [LocaleProvider].
class AccountLanguage {
  AccountLanguage._();

  static AuthService? _auth;
  static int? _syncedUserId;
  static String? _syncedCode;

  /// Called once with the app's AuthService: saves the language on the account after each sign-in.
  static void attach(AuthService auth) {
    _auth = auth;
    auth.addListener(_onAuthChanged);
    _onAuthChanged();
  }

  static void _onAuthChanged() {
    final auth = _auth;
    final id = auth?.isAuthenticated == true ? auth!.currentUser?.id : null;
    if (id == null) {
      _syncedUserId = null;
      _syncedCode = null;
      return;
    }
    if (id != _syncedUserId) sync();
  }

  /// Tells the server the account's language (only when it changed for this account).
  /// Older servers without the field answer 4xx; that is ignored.
  static Future<void> sync() async {
    final auth = _auth;
    if (auth == null || !auth.isAuthenticated) return;
    final id = auth.currentUser?.id;
    final lang = AppLanguage.code;
    if (id == _syncedUserId && lang == _syncedCode) return;
    _syncedUserId = id;
    _syncedCode = lang;
    try {
      final res = await ApiClient(auth).patch('/me', {'locale': lang});
      if (!res.ok && res.status == 0) {
        // Offline: try again on the next change or sign-in
        _syncedCode = null;
      }
    } catch (_) {}
  }
}
