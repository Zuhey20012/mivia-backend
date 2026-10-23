// Token lint for the Malvoya Flutter apps.
//
// Lists design values that should come from `packages/malvoya_ui` tokens instead of being typed
// into screens:
//   * hex colour literals   `Color(0xFF6D2E8C)`
//   * font-size literals    `fontSize: 15`
//   * Material colours      `Colors.grey.shade400` (`Colors.transparent` is not a colour choice and is
//                           not counted)
//
// Everything under `packages/malvoya_ui` is allowed to define them: that is where tokens live.
//
// Usage (from the repository root, no pub get needed):
//   dart tool/check_tokens.dart                 # summary per app and category
//   dart tool/check_tokens.dart --list          # also every finding as path:line
//   dart tool/check_tokens.dart --baseline      # fail (exit 1) when any app has more findings than
//                                               # tool/token_baseline.json allows (CI ratchet)
//   dart tool/check_tokens.dart --update-baseline   # write the current counts as the new ceiling
//
// The ratchet means new literals fail the check while the existing ones are migrated screen by
// screen; lower the baseline after each migration.
import 'dart:convert';
import 'dart:io';

const _roots = <String, String>{
  'customer': 'Malvoya_customer/lib',
  'store': 'malvoya_vendor/lib',
  'courier': 'malvoya_courier/lib',
  'malvoya_core': 'packages/malvoya_core/lib',
};

final _rules = <String, RegExp>{
  'hex': RegExp(r'\bColor\(\s*0x[0-9A-Fa-f]{6,8}\s*\)'),
  'fontSize': RegExp(r'\bfontSize:\s*-?\d+(\.\d+)?\b'),
  'colors': RegExp(r'\bColors\.(?!transparent\b)[a-zA-Z]\w*'),
};

class Finding {
  final String app;
  final String rule;
  final String path;
  final int line;
  final String text;
  Finding(this.app, this.rule, this.path, this.line, this.text);
}

/// The code part of a line: `//` comments and string contents are ignored, so documentation that
/// names a colour does not count.
String _codeOf(String line) {
  final out = StringBuffer();
  String? quote;
  for (var i = 0; i < line.length; i++) {
    final c = line[i];
    if (quote != null) {
      if (c == r'\') {
        i++;
        continue;
      }
      if (c == quote) quote = null;
      continue;
    }
    if (c == "'" || c == '"') {
      quote = c;
      out.write(c);
      continue;
    }
    if (c == '/' && i + 1 < line.length && line[i + 1] == '/') break;
    out.write(c);
  }
  return out.toString();
}

List<Finding> scan(Directory repo) {
  final findings = <Finding>[];
  for (final entry in _roots.entries) {
    final dir = Directory('${repo.path}/${entry.value}');
    if (!dir.existsSync()) continue;
    final files = dir.listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart')).toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    for (final file in files) {
      final rel = file.path.substring(repo.path.length + 1).replaceAll(r'\', '/');
      if (rel.endsWith('.g.dart')) continue;
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final code = _codeOf(lines[i]);
        for (final rule in _rules.entries) {
          for (final _ in rule.value.allMatches(code)) {
            findings.add(Finding(entry.key, rule.key, rel, i + 1, lines[i].trim()));
          }
        }
      }
    }
  }
  return findings;
}

Map<String, Map<String, int>> countsOf(List<Finding> findings) {
  final counts = <String, Map<String, int>>{
    for (final app in _roots.keys) app: {for (final r in _rules.keys) r: 0},
  };
  for (final f in findings) {
    counts[f.app]![f.rule] = counts[f.app]![f.rule]! + 1;
  }
  return counts;
}

void main(List<String> args) {
  final repo = _findRepo();
  final findings = scan(repo);
  final counts = countsOf(findings);

  if (args.contains('--list')) {
    for (final f in findings) {
      stdout.writeln('${f.path}:${f.line}  [${f.rule}]  ${f.text}');
    }
    stdout.writeln('');
  }

  stdout.writeln('Token lint (outside packages/malvoya_ui)');
  stdout.writeln('${'app'.padRight(14)}${'hex'.padLeft(6)}${'fontSize'.padLeft(10)}${'Colors.*'.padLeft(10)}${'total'.padLeft(8)}');
  var grand = 0;
  for (final app in _roots.keys) {
    final c = counts[app]!;
    final total = c.values.fold(0, (a, b) => a + b);
    grand += total;
    stdout.writeln('${app.padRight(14)}${'${c['hex']}'.padLeft(6)}${'${c['fontSize']}'.padLeft(10)}${'${c['colors']}'.padLeft(10)}${'$total'.padLeft(8)}');
  }
  stdout.writeln('${'all'.padRight(14)}${''.padLeft(26)}${'$grand'.padLeft(8)}');

  final baselineFile = File('${repo.path}/tool/token_baseline.json');
  if (args.contains('--update-baseline')) {
    baselineFile.writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(counts)}\n');
    stdout.writeln('\nBaseline written to tool/token_baseline.json');
    return;
  }
  if (args.contains('--baseline')) {
    if (!baselineFile.existsSync()) {
      stderr.writeln('No tool/token_baseline.json yet: run with --update-baseline first.');
      exitCode = 2;
      return;
    }
    final baseline = (jsonDecode(baselineFile.readAsStringSync()) as Map).cast<String, dynamic>();
    final over = <String>[];
    for (final app in _roots.keys) {
      for (final rule in _rules.keys) {
        final allowed = (baseline[app] as Map?)?[rule] as int? ?? 0;
        final now = counts[app]![rule]!;
        if (now > allowed) over.add('$app $rule: $now (baseline $allowed)');
      }
    }
    if (over.isNotEmpty) {
      stderr.writeln('\nNew design literals were added. Use MalvoyaTokens / AppTheme instead:');
      for (final o in over) {
        stderr.writeln('  $o');
      }
      stderr.writeln('Run with --list to see where.');
      exitCode = 1;
    } else {
      stdout.writeln('\nWithin the baseline.');
    }
  }
}

/// The repository root: the folder that holds `tool/check_tokens.dart`.
Directory _findRepo() {
  var dir = Directory.current.absolute;
  for (var i = 0; i < 6; i++) {
    if (File('${dir.path}/tool/check_tokens.dart').existsSync()) return dir;
    dir = dir.parent;
  }
  final script = File.fromUri(Platform.script);
  return script.parent.parent;
}
