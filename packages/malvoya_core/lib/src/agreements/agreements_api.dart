import 'package:flutter/widgets.dart';
import '../api/api_client.dart';
import '../format/dates.dart';
import '../i18n/app_language.dart';

/// The data layer of versioned agreements (API 2.11), shared by the three apps. The sheets that
/// ask for acceptance stay in each app, because each role has its own summary and wording.
///
/// * `GET /me/agreements` → [AgreementState] (what binds the account, what it accepted)
/// * `GET /legal/:doc/versions` → [AgreementVersion]s (what changed in each version)
/// * `POST /me/agreements/accept` → [AgreementAcceptResult]
/// * 428 `AGREEMENT_REQUIRED` → [AgreementRequired.from]

/// Documents: `terms` (customers), `seller-terms`, `courier-agreement`, `privacy` (never blocking).
abstract final class AgreementDocs {
  /// Terms of Service (customers).
  static const terms = 'terms';

  /// Seller Terms (stores).
  static const sellerTerms = 'seller-terms';

  /// Courier Agreement.
  static const courierAgreement = 'courier-agreement';

  /// Privacy Policy: acknowledged, never blocking.
  static const privacy = 'privacy';
}

/// The body of a 428 `AGREEMENT_REQUIRED` answer: the version in force that must be accepted.
@immutable
class AgreementRequired {
  /// Creates the requirement.
  const AgreementRequired({required this.doc, required this.version, this.title, this.url, this.message});

  /// The document, e.g. "seller-terms".
  final String doc;

  /// The exact version to accept.
  final String version;

  /// `{en, fi}` title from the server.
  final Map? title;

  /// The text of that version.
  final String? url;

  /// The server's own sentence ("Please read and accept …"), in the app language.
  final String? message;

  /// The requirement in [res], or null when [res] is anything else.
  static AgreementRequired? from(ApiResult res) {
    if (!res.agreementRequired) return null;
    final doc = res.data['doc'];
    final version = res.data['version'];
    if (doc is! String || version is! String || version.isEmpty) return null;
    return AgreementRequired(
      doc: doc,
      version: version,
      title: res.data['title'] is Map ? res.data['title'] as Map : null,
      url: res.data['url'] is String ? res.data['url'] as String : null,
      message: res.error,
    );
  }
}

/// One document of `GET /me/agreements` → `required`.
@immutable
class AgreementDoc {
  /// Wraps one `required` item.
  const AgreementDoc(this.raw);

  /// The item as the server sent it.
  final Map<String, dynamic> raw;

  /// The document, e.g. "terms".
  String get doc => '${raw['doc'] ?? ''}';

  /// `{en, fi}` title.
  Map? get title => raw['title'] is Map ? raw['title'] as Map : null;

  /// Actions are refused until the version in force is accepted (false for privacy).
  bool get blocking => raw['blocking'] == true;

  /// The version in force.
  String? get currentVersion => raw['currentVersion'] as String?;

  /// When the version in force took effect.
  DateTime? get effectiveAt => parseApiDate(raw['effectiveAt']);

  /// The account accepted the version in force.
  bool get accepted => raw['accepted'] == true;

  /// When it was accepted.
  DateTime? get acceptedAt => parseApiDate(raw['acceptedAt']);

  /// Text of the version in force.
  String? get url => raw['url'] as String?;

  /// An announced version (accepting is possible now, never required before it takes effect).
  String? get pendingVersion => raw['pendingVersion'] as String?;

  /// When [pendingVersion] takes effect.
  DateTime? get pendingEffectiveAt => parseApiDate(raw['pendingEffectiveAt']);

  /// The account already accepted [pendingVersion].
  bool get pendingAccepted => raw['pendingAccepted'] == true;

  /// Text of [pendingVersion].
  String? get pendingUrl => raw['pendingUrl'] as String?;

  /// `{en, fi}` summary of what changes in [pendingVersion].
  Map? get summary => raw['summary'] is Map ? raw['summary'] as Map : null;

  /// Until when the contract can be ended before the update applies (Seller Terms §7a).
  DateTime? get canTerminateBefore => parseApiDate(raw['canTerminateBefore']);

  /// An announced version the account has not accepted yet.
  bool get hasOpenUpdate => pendingVersion != null && !pendingAccepted;

  /// The version in force is blocking and not accepted.
  bool get missing => blocking && !accepted;
}

/// `GET /me/agreements` as loaded.
@immutable
class AgreementState {
  /// Creates the state.
  const AgreementState({required this.status, this.error, this.required = const [], this.history = const []});

  /// HTTP status: 0 = no connection, 404 = a server without agreements (before 2.11).
  final int status;

  /// The error in the app language; null when it loaded.
  final String? error;

  /// Every document that binds the account.
  final List<AgreementDoc> required;

  /// Acceptance records `{id, doc, version, acceptedAt, …}`, newest first.
  final List<Map<String, dynamic>> history;

  /// True when it loaded.
  bool get ok => error == null;

  /// True for a server without agreements.
  bool get unsupported => status == 404;

  /// The item for [doc], or null.
  AgreementDoc? docOf(String doc) => required.where((d) => d.doc == doc).firstOrNull;

  /// The first blocking document whose version in force is not accepted.
  AgreementDoc? get firstMissing => required.where((d) => d.missing).firstOrNull;

  /// The first announced update not accepted yet.
  AgreementDoc? get firstOpenUpdate => required.where((d) => d.hasOpenUpdate).firstOrNull;

  /// The account accepted another version of [doc] before, so [version] is an update.
  bool acceptedEarlier(String doc, String? version) => history.any((h) => h['doc'] == doc && h['version'] != version);
}

/// One row of `GET /legal/:doc/versions`.
@immutable
class AgreementVersion {
  /// Wraps one row.
  const AgreementVersion(this.raw);

  /// The row as the server sent it.
  final Map<String, dynamic> raw;

  /// The version id.
  String? get version => raw['version'] as String?;

  /// "current", "pending" or "superseded".
  String? get status => raw['status'] as String?;

  /// When it takes or took effect.
  DateTime? get effectiveAt => parseApiDate(raw['effectiveAt']);

  /// Text of this version.
  String? get url => raw['url'] as String?;

  /// `{en, fi}` summary of what changed in this version.
  Map? get summary => raw['summary'] is Map ? raw['summary'] as Map : null;
}

/// The answer to `POST /me/agreements/accept`.
@immutable
class AgreementAcceptResult {
  /// Wraps the API answer.
  const AgreementAcceptResult(this.result);

  /// The raw API answer.
  final ApiResult result;

  /// Accepted (or it had been accepted already).
  bool get ok => result.ok;

  /// The server really emailed a copy.
  bool get emailed => result.data['emailed'] == true;

  /// The version had been accepted earlier.
  bool get alreadyAccepted => result.data['alreadyAccepted'] == true;

  /// 409: the version was replaced a moment ago; see [currentVersion] / [pendingVersion].
  bool get conflict => result.status == 409;

  /// After a [conflict]: the version now in force.
  String? get currentVersion => result.data['currentVersion'] as String?;

  /// After a [conflict]: the version now announced.
  String? get pendingVersion => result.data['pendingVersion'] as String?;

  /// The error in the app language, or null.
  String? get error => result.error;
}

/// The agreement endpoints for one session.
class AgreementsApi {
  /// Uses [client] (which carries the session).
  const AgreementsApi(this.client);

  /// The API client.
  final ApiClient client;

  List<Map<String, dynamic>> _maps(dynamic v) =>
      v is List ? v.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList() : <Map<String, dynamic>>[];

  /// `GET /me/agreements`.
  Future<AgreementState> load() async {
    final res = await client.get('/me/agreements');
    if (!res.ok) return AgreementState(status: res.status, error: res.errorMessage);
    return AgreementState(
      status: res.status,
      required: _maps(res.data['required']).map(AgreementDoc.new).toList(),
      history: _maps(res.data['history']),
    );
  }

  /// `GET /legal/:doc/versions`, oldest first as the server lists them. Empty when unavailable.
  Future<List<AgreementVersion>> versions(String doc) async {
    final res = await client.get('/legal/$doc/versions');
    if (!res.ok) return const [];
    return _maps(res.data['versions']).map(AgreementVersion.new).toList();
  }

  /// Accepts [version] of [doc] (the version in force or the announced one; idempotent).
  Future<AgreementAcceptResult> accept(String doc, String version) async =>
      AgreementAcceptResult(await client.post('/me/agreements/accept', {'doc': doc, 'version': version}));

  /// A 10-minute signed link to the copy of acceptance [id], or the failed result.
  Future<(Uri?, ApiResult)> copyLink(int id) async {
    final res = await client.get('/me/agreements/$id/copy/link');
    final url = res.ok ? Uri.tryParse('${res.data['url'] ?? ''}') : null;
    return (url != null && url.hasScheme ? url : null, res);
  }
}

/// The name of a document in the widget's language: the server's `{en, fi}` title, or a fallback
/// per document.
String agreementTitle(BuildContext context, Object? title, String doc) {
  final fromServer = localized(context, title);
  if (fromServer != null) return fromServer;
  return switch (doc) {
    AgreementDocs.terms => tr(context, 'Terms of Service', 'Käyttöehdot'),
    AgreementDocs.sellerTerms => tr(context, 'Seller Terms', 'Myyjän ehdot'),
    AgreementDocs.courierAgreement => tr(context, 'Courier Agreement', 'Lähettisopimus'),
    AgreementDocs.privacy => tr(context, 'Privacy Policy', 'Tietosuojaseloste'),
    _ => tr(context, 'Agreement', 'Sopimus'),
  };
}
