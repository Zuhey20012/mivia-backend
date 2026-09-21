const fs = require('fs');
const readline = require('readline');

async function extractFromCurrent() {
  const fileStream = fs.createReadStream('C:/Users/Zuhey/.gemini/antigravity/brain/cfe87b4e-60a1-4d76-8d3d-f4f4335454d3/.system_generated/logs/transcript_full.jsonl');
  const rl = readline.createInterface({
    input: fileStream,
    crlfDelay: Infinity
  });

  let latestContent = null;
  let count = 0;
  for await (const line of rl) {
    if (line.includes('write_to_file') && line.includes('l10n.dart')) {
      try {
        const obj = JSON.parse(line);
        if (obj.tool_calls) {
          for (const tc of obj.tool_calls) {
            if (tc.name === 'write_to_file' && tc.args && tc.args.TargetFile && tc.args.TargetFile.includes('l10n.dart')) {
              latestContent = tc.args.CodeContent;
              count++;
              console.log(`Found l10n.dart in cfe87b4e (#${count}), length:`, latestContent.length);
            }
          }
        }
      } catch (e) {}
    }
  }

  if (latestContent) {
    fs.writeFileSync('c:/Users/Zuhey/mivia/Malvoya_customer/lib/l10n.dart', latestContent, 'utf8');
    console.log('Successfully wrote latest l10n.dart from cfe87b4e transcript!');
  } else {
    console.log('No write_to_file for l10n.dart found in cfe87b4e.');
  }
}

extractFromCurrent();
