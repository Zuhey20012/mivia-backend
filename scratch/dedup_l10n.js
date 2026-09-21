const fs = require('fs');
const path = require('path');

const l10nPath = path.resolve('c:/Users/Zuhey/mivia/Malvoya_customer/lib/l10n.dart');
let code = fs.readFileSync(l10nPath, 'utf8');

const regex = /'([a-z]{2})'\s*:\s*\{([\s\S]*?)\n\s*\},/g;
let newCode = code.replace(regex, (match, locale, body) => {
  const lines = body.split('\n');
  const seen = new Set();
  const dedupedLines = [];
  for (const line of lines) {
    const keyMatch = line.match(/^\s*'([^']+)'\s*:/);
    if (keyMatch) {
      const k = keyMatch[1];
      if (seen.has(k)) {
        continue;
      }
      seen.add(k);
    }
    dedupedLines.push(line);
  }
  return `'${locale}': {\n${dedupedLines.join('\n')}\n    },`;
});

fs.writeFileSync(l10nPath, newCode, 'utf8');
console.log('Successfully deduplicated l10n.dart');
