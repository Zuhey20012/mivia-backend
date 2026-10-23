import 'package:url_launcher/url_launcher.dart';
import '../api/api_client.dart';

/// The public URL of a legal document on the server (one source of truth, also linked from Google
/// Play). [doc]: privacy | terms | sellers | couriers | delete-account.
Uri legalUrl(String doc) => Uri.parse('${ApiConfig.baseUrl.replaceAll('/api/v1', '')}/legal/$doc');

/// Opens [legalUrl] in the in-app browser.
Future<void> openLegal(String doc) => launchUrl(legalUrl(doc), mode: LaunchMode.inAppBrowserView);
