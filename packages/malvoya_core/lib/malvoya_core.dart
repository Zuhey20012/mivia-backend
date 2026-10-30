/// Shared infrastructure for the Malvoya customer, store and courier apps.
///
/// Set up once in each app's `main()`:
/// ```dart
/// ApiConfig.baseUrl = AppConstants.apiBase;
/// await AppLanguage.loadAppVersion();
/// ```
/// and implement [ApiSession] in the app's `AuthService`.
library;

export 'src/agreements/agreements_api.dart';
export 'src/api/api_client.dart';
export 'src/crash/crash_backend.dart';
export 'src/crash/crash_reporting.dart';
export 'src/crash/crash_scrubber.dart';
export 'src/format/dates.dart';
export 'src/format/money.dart';
export 'src/i18n/app_language.dart';
export 'src/i18n/locale_provider.dart';
export 'src/i18n/server_messages.dart';
export 'src/media/image_url.dart';
export 'src/platform/app_gate.dart';
export 'src/platform/haptics.dart';
export 'src/platform/legal_links.dart';
export 'src/platform/sign_in_setup.dart';
