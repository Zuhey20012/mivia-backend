import 'package:url_launcher/url_launcher.dart';
import '../config/constants.dart';

/// The legal documents live on the server (one source of truth, also linked from Google Play).
/// doc: privacy | terms | sellers | couriers
Uri legalUrl(String doc) => Uri.parse('${AppConstants.apiBase.replaceAll('/api/v1', '')}/legal/$doc');

Future<void> openLegal(String doc) => launchUrl(legalUrl(doc), mode: LaunchMode.inAppBrowserView);
