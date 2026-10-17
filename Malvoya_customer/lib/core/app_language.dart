import 'package:shared_preferences/shared_preferences.dart';
import '../auth_service.dart';
import 'api_client.dart';

/// The app's language outside the widget tree: sent as `Accept-Language` on every request to the
/// Malvoya API, and saved on the account (`PATCH /me {locale}`) so pushes and emails come in the
/// same language. [LocaleProvider] keeps [code] up to date.
class AppLanguage {
  AppLanguage._();

  static String code = 'fi';

  /// Merge into the headers of any raw `http` call to the API.
  static Map<String, String> get header => {'Accept-Language': code};

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

  /// The user picked another language.
  static void set(String languageCode) {
    if (languageCode != 'fi' && languageCode != 'en') return;
    code = languageCode;
    sync();
  }

  /// Tells the server the account's language (only when it changed for this account).
  /// Older servers without the field answer 4xx; that is ignored.
  static Future<void> sync() async {
    final auth = _auth;
    if (auth == null || !auth.isAuthenticated) return;
    final id = auth.currentUser?.id;
    final lang = code;
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

  /// Reads the saved choice before the first request goes out.
  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('languageCode') ?? prefs.getString('selected_user_locale');
      if (saved == 'fi' || saved == 'en') code = saved!;
    } catch (_) {}
  }
}
