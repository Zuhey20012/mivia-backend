import 'package:flutter/widgets.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// The app's language and build outside the widget tree.
///
/// The API client has no `BuildContext`, so it reads [code] for `Accept-Language` and for the
/// language of its own error messages. [LocaleProvider] keeps it in sync with the language the
/// user picked. The apps are written in Finnish and English only.
class AppLanguage {
  AppLanguage._();

  /// The languages every app is fully written in.
  static const supportedCodes = ['fi', 'en'];

  /// "fi" or "en". Finnish until the saved choice is loaded.
  static String code = 'fi';

  /// True when the app language is Finnish.
  static bool get isFinnish => code == 'fi';

  /// "1.7.0+9": sent as `X-App-Version`, so the server can record which build an agreement was
  /// accepted in. Null until [loadAppVersion] has read it, and on platforms that cannot tell.
  static String? appVersion;

  /// Reads [appVersion] once at start-up. Requests sent before it is known go without the header.
  static Future<void> loadAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform().timeout(const Duration(seconds: 3));
      final build = info.buildNumber.trim();
      appVersion = build.isEmpty ? info.version : '${info.version}+$build';
    } catch (_) {}
  }

  /// `Accept-Language` and `X-App-Version`: merge into the headers of any raw `http` call to the API.
  static Map<String, String> get headers => {
        'Accept-Language': code,
        if (appVersion != null) 'X-App-Version': appVersion!,
      };

  /// [en] or [fi] by the app language, for text made outside a widget (e.g. in a service).
  static String pick(String en, String fi) => isFinnish ? fi : en;
}

/// Finnish when the widget's locale is Finnish, English otherwise.
String tr(BuildContext context, String en, String fi) => isFinnish(context) ? fi : en;

/// True when the widget's locale is Finnish.
bool isFinnish(BuildContext context) => Localizations.maybeLocaleOf(context)?.languageCode == 'fi';

/// The app-language text of a server value sent in both languages (`{en, fi}`), or a plain string.
/// Null for anything empty.
String? localized(BuildContext context, dynamic value) => localizedFor(isFinnish(context) ? 'fi' : 'en', value);

/// [localized] for a language code, without a widget.
String? localizedFor(String languageCode, dynamic value) {
  if (value is String) return value.trim().isEmpty ? null : value;
  if (value is Map) {
    final text = (languageCode == 'fi' ? value['fi'] : value['en']) ?? value['en'] ?? value['fi'];
    return text is String && text.trim().isNotEmpty ? text : null;
  }
  return null;
}

/// An int from JSON that may arrive as int, double or string. Null when it is none of them.
int? asInt(dynamic v) => v is int ? v : (v is num ? v.toInt() : int.tryParse('${v ?? ''}'));
