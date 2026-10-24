// PostToolUse: dart format the edited .dart file, so CI's format check (page width 120) never fails.
const { execSync } = require('child_process');
const { projectRelative } = require('./paths');

let input = '';
process.stdin.on('data', (d) => (input += d));
process.stdin.on('end', () => {
  let file;
  try {
    file = (JSON.parse(input).tool_input || {}).file_path;
  } catch {
    process.exit(0);
  }
  if (!file || !file.endsWith('.dart')) process.exit(0);
  const rel = projectRelative(file);
  if (rel === null || rel.startsWith('third_party/') || rel.startsWith('build/')) process.exit(0);
  try {
    // A file that doesn't parse yet is left alone; analyze reports it.
    execSync(`dart format "${file}"`, { stdio: 'ignore' });
  } catch {}
  process.exit(0);
});
