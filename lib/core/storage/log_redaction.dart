/// Masks secrets in a log line before it's written (issue #1): RomM tokens
/// and passwords, the RetroAchievements Web API key, emulator config lines
/// that hold a login. Paths, game names and the word "token" in a sentence
/// stay as they are.
String redact(String line) {
  var out = line;
  for (final rule in _rules) {
    out = out.replaceAllMapped(rule.pattern, rule.mask);
  }
  return out;
}

const _hidden = '***';

typedef _Rule = ({RegExp pattern, String Function(Match) mask});

final List<_Rule> _rules = [
  // Authorization: Bearer <token> / Basic <base64>, as a header line or in a
  // printed map ({Authorization: Bearer …}).
  (
    pattern: RegExp(
      r'(authorization["\x27]?\s*[:=]\s*["\x27]?(?:bearer|basic)\s+)[^\s,"\x27}\]]+',
      caseSensitive: false,
    ),
    mask: (m) => '${m[1]}$_hidden',
  ),
  // A bare "Bearer <token>" anywhere else.
  (
    pattern: RegExp(r'\b(bearer\s+)(?!\*\*\*)[A-Za-z0-9._~+/=-]{8,}', caseSensitive: false),
    mask: (m) => '${m[1]}$_hidden',
  ),
  // JSON or a printed map: "token": "…", 'password': '…', raw_token: … (any key
  // ending in token or password: RomM's raw_token, RA's cheevos_token).
  (
    pattern: RegExp(
      r'''(["\x27]?\b(?:[a-z_]*token|[a-z_]*password|client_secret|device_code)["\x27]?\s*:\s*)(?:"[^"]*"|\x27[^\x27]*\x27|[^\s,}\]]+)''',
      caseSensitive: false,
    ),
    mask: (m) => '${m[1]}"$_hidden"',
  ),
  // Query strings: ?token=…&password=…, RA's Web API key in y= (and key=, apikey=).
  (
    pattern: RegExp(
      r'([?&](?:[a-z_]*token|[a-z_]*password|device_code|y|key|apikey|api_key)=)[^&\s"\x27#]*',
      caseSensitive: false,
    ),
    mask: (m) => '${m[1]}$_hidden',
  ),
  // Emulator config keys, alone on a line or inside a tagged one
  // ([RetroArch] set cheevos_token = "…"): webdav_password = "…", PCSX2's
  // [Achievements] Token = … . An unquoted value ends at a space or a comma.
  (
    pattern: RegExp(
      r'''(\b(?:cheevos_token|cheevos_password|webdav_password|token)\s*=\s*)(?:"[^"\r\n]*"|[^\s",}\]&#]*)''',
      caseSensitive: false,
    ),
    mask: (m) => m[0]!.substring(m[1]!.length).startsWith('"') ? '${m[1]}"$_hidden"' : '${m[1]}$_hidden',
  ),
];
