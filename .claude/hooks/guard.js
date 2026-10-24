// PreToolUse guard for the CLAUDE.md rules a hook can check: exit 2 blocks the call and tells Claude why.
const { projectRelative } = require('./paths');

let input = '';
process.stdin.on('data', (d) => (input += d));
process.stdin.on('end', () => {
  let call;
  try {
    call = JSON.parse(input);
  } catch {
    process.exit(0);
  }
  const tool = call.tool_name;
  const args = call.tool_input || {};
  const block = (why) => {
    process.stderr.write(`Blocked by .claude/hooks/guard.js: ${why}\n`);
    process.exit(2);
  };

  if (tool === 'Bash' || tool === 'PowerShell') {
    const cmd = args.command || '';
    if (/\b(git|gh)\b/.test(cmd) && /claude\.ai\/code\/session/.test(cmd)) {
      block('commits, PRs and issues never link the session that made them (CLAUDE.md). Remove the link.');
    }
    process.exit(0);
  }

  const file = args.file_path;
  if (!file) process.exit(0);
  const rel = projectRelative(file);
  if (rel === null) process.exit(0);

  const generated = ['pubspec.lock', 'build/', 'dist/', 'third_party/argosy-sigil/'];
  const hit = generated.find((p) => (p.endsWith('/') ? rel.startsWith(p) : rel === p));
  if (hit) {
    block(`${rel} is generated or pinned (${hit}). Change it with its tool (flutter pub, the build, the submodule), not by hand.`);
  }

  const text =
    tool === 'Write'
      ? args.content || ''
      : tool === 'MultiEdit'
        ? (args.edits || []).map((e) => e.new_string || '').join('\n')
        : args.new_string || '';
  const platformAllowed = ['lib/core/platform/platform_info.dart', 'lib/core/emulator/linux_strategies/'];
  if (
    rel.startsWith('lib/') &&
    rel.endsWith('.dart') &&
    !platformAllowed.some((p) => rel.startsWith(p)) &&
    /\bPlatform\.(isWindows|environment)\b/.test(text)
  ) {
    block('never use Platform.isWindows or Platform.environment directly; take a PlatformInfo constructor parameter.');
  }
  process.exit(0);
});
