/// Removes personal data and secrets from text before it goes into a crash report.
///
/// Crash reports carry only the type of an error, a cleaned message and the stack trace. Emails,
/// phone numbers, personal identity codes, IBANs, tokens, passwords and query strings are replaced
/// by placeholders; request and response bodies are never included (a `FormatException` keeps its
/// message but not its source text, which is often the body that failed to parse).
///
/// This is a safety net: callers should not put personal data into errors in the first place.
abstract final class CrashScrubber {
  /// Longest message kept; the rest is cut off.
  static const maxLength = 300;

  static final _rules = <(RegExp, String)>[
    // Bearer tokens and JWTs (access, refresh, Firebase ID tokens)
    (RegExp(r'Bearer\s+\S+', caseSensitive: false), 'Bearer <token>'),
    (RegExp(r'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+(?:\.[A-Za-z0-9_-]*)?'), '<token>'),
    // key=value or "key": "value" pairs that hold secrets or personal data
    (
      RegExp(
        r'''["']?\b(access_?token|refresh_?token|id_?token|token|password|passwd|secret|client_?secret|authorization|api_?key|email|phone|name|address|code)\b["']?\s*[:=]\s*("[^"]*"|'[^']*'|[^\s,&;}\]]+)''',
        caseSensitive: false,
      ),
      r'$1=<redacted>',
    ),
    // Query strings of URLs (they can carry emails, codes or tokens)
    (RegExp(r'\?[A-Za-z0-9_.%-]+=[^\s#]*'), '?<query>'),
    // Email addresses
    (RegExp(r'[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}'), '<email>'),
    // IBANs (FI21 1234 5600 0007 85)
    (RegExp(r'\b[A-Z]{2}\d{2}(?:\s?[A-Z0-9]{4}){2,7}(?:\s?[A-Z0-9]{1,4})?\b'), '<iban>'),
    // Finnish personal identity codes (131052-308T)
    (RegExp(r'\b\d{6}[-+A-FU-Y]\d{3}[0-9A-Y]\b'), '<id-code>'),
    // Phone numbers and other long digit runs (+358 40 123 4567, 0401234567)
    (RegExp(r'\+?\d[\d\s().-]{7,}\d'), '<number>'),
    // Long opaque strings: API keys, Stripe client secrets, random codes
    (RegExp(r'[A-Za-z0-9_-]{32,}'), '<token>'),
  ];

  /// [text] without personal data or secrets, at most [maxLength] characters.
  static String scrub(String text) {
    var out = text;
    for (final (pattern, replacement) in _rules) {
      out = out.replaceAllMapped(pattern, (m) => _expand(replacement, m));
    }
    if (out.length > maxLength) out = '${out.substring(0, maxLength)}…';
    return out;
  }

  /// A cleaned stand-in for [error]: its type name and a scrubbed message.
  static ScrubbedError error(Object error) {
    if (error is ScrubbedError) return error;
    final type = error.runtimeType.toString();
    // FormatException.toString() appends the source text (often a response body): leave it out
    final message = error is FormatException ? error.message : error.toString();
    return ScrubbedError(type, scrub(message));
  }

  /// An API path that is safe to report: no query string, and any segment that is not a plain
  /// word (ids, codes, emails, tokens) replaced by `:x`. `/orders/12?x=1` → `/orders/:x`.
  static String apiPath(String path) {
    final bare = path.split(RegExp('[?#]')).first;
    return bare
        .split('/')
        .map((s) => s.isEmpty || RegExp(r'^[a-z][a-z_-]*$').hasMatch(s) ? s : ':x')
        .join('/');
  }

  static String _expand(String replacement, Match m) =>
      replacement.replaceAllMapped(RegExp(r'\$(\d)'), (g) => m.group(int.parse(g.group(1)!)) ?? '');
}

/// An error as it is reported: the original type name and a scrubbed message, never the original
/// object (whose fields could hold personal data).
class ScrubbedError implements Exception {
  /// Creates a cleaned error.
  const ScrubbedError(this.type, this.message);

  /// The original error's type, e.g. `StateError`.
  final String type;

  /// The scrubbed message.
  final String message;

  @override
  String toString() => message.startsWith(type) ? message : '$type: $message';
}
