import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/storage/log_redaction.dart';

void main() {
  group('masked', () {
    final cases = {
      'Authorization: Bearer rmm_abcdef1234567890': 'Authorization: Bearer ***',
      '{Authorization: Basic dXNlcjpwYXNz, Accept: */*}': '{Authorization: Basic ***, Accept: */*}',
      'headers: {"authorization": "Bearer eyJhbGciOi.xyz.abc"}': 'headers: {"authorization": "Bearer ***"}',
      '[RomM] sent Bearer rmm_0123456789abcdef': '[RomM] sent Bearer ***',
      '{"access_token": "abc.def", "token_type": "bearer"}': '{"access_token": "***", "token_type": "bearer"}',
      '{"refresh_token":"r1","expires":3600}': '{"refresh_token":"***","expires":3600}',
      '{"token": "t0k3n", "name": "Gargosy"}': '{"token": "***", "name": "Gargosy"}',
      "{'password': 'hunter2', 'username': 'henrik'}": "{'password': \"***\", 'username': 'henrik'}",
      '{username: henrik, password: hunter2}': '{username: henrik, password: "***"}',
      'GET https://romm.example/api/x?token=abc123&rom_id=5': 'GET https://romm.example/api/x?token=***&rom_id=5',
      'login?u=henrik&password=hunter2': 'login?u=henrik&password=***',
      'https://retroachievements.org/API/API_GetGame.php?z=henrik&y=SECRETKEY&i=1':
          'https://retroachievements.org/API/API_GetGame.php?z=henrik&y=***&i=1',
      'GET /x?apikey=k1&key=k2': 'GET /x?apikey=***&key=***',
      'cheevos_token = "abcdef"': 'cheevos_token = "***"',
      '  webdav_password = "pw"': '  webdav_password = "***"',
      'Token = 0123abcd': 'Token = ***',
      '{raw_token: rmm_abc123, name: Gargosy}': '{raw_token: "***", name: Gargosy}',
      '{"raw_token":"rmm_abc123"}': '{"raw_token":"***"}',
      '{"device_code": "dc-1", "user_code": "ABCD"}': '{"device_code": "***", "user_code": "ABCD"}',
      '[RetroArch] set cheevos_token = "abc123"': '[RetroArch] set cheevos_token = "***"',
      '[PCSX2] Token = abc, user = henrik': '[PCSX2] Token = ***, user = henrik',
      'GET /x?access_token=xyz&a=1': 'GET /x?access_token=***&a=1',
    };
    cases.forEach((line, want) => test(line, () => expect(redact(line), want)));
  });

  group('left as they are', () {
    for (final line in [
      r'[DuckStation] states folder D:\Games\Gargosy\userdata\profiles\452988cf\emulators\duckstation\savestates',
      '[StateSync] pull Final Fantasy VII (Disc 1) (rom 42, emulator duckstation)',
      'The device token expired; pair again.',
      'Saving token.json failed',
      'keyboard=true, mykey=5', // not a query string
      'https://romm.example/api/roms?platform_id=3&order_by=name',
      'Authorization header missing',
      '{"token_type": "bearer"}',
    ]) {
      test(line, () => expect(redact(line), line));
    }
  });
}
