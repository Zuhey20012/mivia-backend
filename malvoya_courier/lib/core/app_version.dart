import 'dart:async';
import 'package:package_info_plus/package_info_plus.dart';

/// "<version>+<build>" of this app (for example "1.7.0+9"), sent as `X-App-Version` with every API
/// request. Since API 2.11 the server stores it with each agreement acceptance as part of the record.
/// Empty until [load] has run, or when the platform cannot tell; the header is then left out.
class AppVersion {
  AppVersion._();

  static String value = '';

  static Future<void> load() async {
    try {
      final info = await PackageInfo.fromPlatform().timeout(const Duration(seconds: 3));
      value = info.buildNumber.isEmpty ? info.version : '${info.version}+${info.buildNumber}';
    } catch (_) {}
  }

  static Map<String, String> get headers => value.isEmpty ? const {} : {'X-App-Version': value};
}
