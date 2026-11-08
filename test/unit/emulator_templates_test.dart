import 'dart:convert';
import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/emulators/emulator_templates.dart';
import 'package:gargosy/profiles/app_root.dart';
import 'package:gargosy/profiles/profile_paths.dart';
import 'package:gargosy/profiles/profile_store.dart';
import 'package:gargosy/profiles/template_paths.dart';
import 'package:path/path.dart' as p;

import '../helpers/profile_test_env.dart';

void main() {
  late AppRoot root;
  late ProfileStore store;
  late EmulatorTemplates templates;
  var ids = 0;

  setUp(() async {
    root = await tempAppRoot();
    ids = 0;
    store = ProfileStore(root, MemoryPrefs(), newId: () => 'p${++ids}');
    templates = EmulatorTemplates(root);
  });
  tearDown(() => io.Directory(root.root).delete(recursive: true));

  Future<ProfilePaths> profile(String name) async {
    final made = await store.create(
      name: name,
      colorIndex: 0,
      serverUrl: 'https://romm.example',
      rommUserId: ids + 1,
      rommUsername: name.toLowerCase(),
    );
    return ProfilePaths(root, made.id);
  }

  io.File put(ProfilePaths paths, String emulator, String rel, String text) =>
      io.File(p.joinAll([paths.emulatorDir(emulator), ...rel.split('/')]))
        ..createSync(recursive: true)
        ..writeAsStringSync(text);

  String read(ProfilePaths paths, String emulator, String rel) =>
      io.File(p.joinAll([paths.emulatorDir(emulator), ...rel.split('/')])).readAsStringSync();

  bool has(ProfilePaths paths, String emulator, String rel) =>
      io.File(p.joinAll([paths.emulatorDir(emulator), ...rel.split('/')])).existsSync();

  group('sign-ins left out', () {
    test('RetroArch: the achievements login and other passwords emptied, achievements off', () {
      final text = withoutSignIns(
        'cheevos_enable = "true"\ncheevos_username = "anna"\ncheevos_token = "abc"\n'
        'cheevos_password = ""\nwebdav_password = "pw"\nnetplay_nickname = "Anna"\nvideo_driver = "vulkan"\n',
      );
      expect(text, contains('cheevos_enable = "false"'));
      expect(text, contains('cheevos_username = ""'));
      expect(text, contains('cheevos_token = ""'));
      expect(text, contains('webdav_password = ""'));
      expect(text, contains('netplay_nickname = "Anna"'));
      expect(text, contains('video_driver = "vulkan"'));
      expect(text, isNot(contains('abc')));
    });

    test('PCSX2, DuckStation, Dolphin, PPSSPP: usernames, tokens and login times', () {
      final pcsx2 = withoutSignIns('[Achievements]\r\nEnabled = true\r\nUsername = anna\r\nLoginTimestamp = 123\r\n');
      expect(pcsx2, '[Achievements]\r\nEnabled = true\r\nUsername = \r\nLoginTimestamp = \r\n');
      final duck = withoutSignIns('[Cheevos]\nUsername = anna\nToken = abc\n[Pad1]\nCross = SDL-0/A\n');
      expect(duck, '[Cheevos]\nUsername = \nToken = \n[Pad1]\nCross = SDL-0/A\n');
      final dolphin = withoutSignIns('[Achievements]\nUsername = anna\nApiToken = abc\n');
      expect(dolphin, '[Achievements]\nUsername = \nApiToken = \n');
      final ppsspp = withoutSignIns('[Achievements]\nAchievementsUserName = anna\n');
      expect(ppsspp, '[Achievements]\nAchievementsUserName = \n');
    });

    test("Qt settings (Eden, Azahar): the web service login, not its 'default' flag", () {
      final text = withoutSignIns(
        '[WebService]\nweb_api_token\\default=false\nweb_api_token=abc\nyuzu_username=anna\ncitra_token=x\n',
      );
      expect(text, '[WebService]\nweb_api_token\\default=false\nweb_api_token=\nyuzu_username=\ncitra_token=\n');
    });

    test('TOML keeps an emptied value quoted', () {
      expect(withoutSignIns("token = 'abc'\nname = 'x'\n", toml: true), "token = ''\nname = 'x'\n");
    });
  });

  test('paths into the profile become markers and then the new profile', () {
    const dir = r'C:\Gargosy\userdata\profiles\p1';
    const text =
        'a = C:\\Gargosy\\userdata\\profiles\\P1\\emulators\\x\n'
        'b = "C:/Gargosy/userdata/profiles/p1/saves"\n'
        'c = "C:\\\\Gargosy\\\\userdata\\\\profiles\\\\p1\\\\hdd"\n'
        'd = C:\\Gargosy\\userdata\\profiles\\p12\\other\n';
    final marked = toTemplateText(text, dir);
    expect(marked, isNot(contains(r'profiles\P1')));
    expect(marked, contains(r'profiles\p12'), reason: 'another profile whose name starts the same');
    final back = fromTemplateText(marked, r'C:\G\userdata\profiles\p9');
    expect(
      back,
      'a = C:\\G\\userdata\\profiles\\p9\\emulators\\x\n'
      'b = "C:/G/userdata/profiles/p9/saves"\n'
      'c = "C:\\\\G\\\\userdata\\\\profiles\\\\p9\\\\hdd"\n'
      'd = C:\\Gargosy\\userdata\\profiles\\p12\\other\n',
    );
  });

  test('a new profile starts with the copied settings, without saves, states or sign-ins', () async {
    final anna = await profile('Anna');
    put(anna, 'retroarch', 'retroarch.cfg', 'cheevos_token = "abc"\nsavefile_directory = "${anna.dir}\\x"\n');
    put(anna, 'retroarch', 'config/remaps/Snes9x/Snes9x.rmp', 'input_player1_btn_a = "1"\n');
    put(anna, 'retroarch', 'saves/Mario.srm', 'save');
    put(anna, 'retroarch', 'states/Mario.state', 'state');
    put(anna, 'retroarch', 'system/scph5501.bin', 'bios');
    put(anna, 'pcsx2', 'PCSX2/inis/PCSX2.ini', '[Pad1]\nCross = SDL-0/FaceEast\n');
    put(anna, 'pcsx2', 'PCSX2/inis/secrets.ini', '[Achievements]\nToken = abc\n');
    put(anna, 'pcsx2', 'PCSX2/memcards/Mcd001.ps2', 'card');

    expect(await templates.save('retroarch', anna, profileName: 'Anna', now: DateTime(2026, 11, 8)), 2);
    expect(await templates.save('pcsx2', anna, profileName: 'Anna'), 1);
    expect(templates.info('retroarch')?.profileName, 'Anna');
    expect(templates.info('retroarch')?.savedAt, DateTime(2026, 11, 8));

    final bob = await profile('Bob');
    expect(read(bob, 'retroarch', 'retroarch.cfg'), 'cheevos_token = ""\nsavefile_directory = "${bob.dir}\\x"\n');
    expect(read(bob, 'retroarch', 'config/remaps/Snes9x/Snes9x.rmp'), 'input_player1_btn_a = "1"\n');
    expect(read(bob, 'pcsx2', 'PCSX2/inis/PCSX2.ini'), contains('SDL-0/FaceEast'));
    for (final (emu, rel) in [
      ('retroarch', 'saves/Mario.srm'),
      ('retroarch', 'states/Mario.state'),
      ('retroarch', 'system/scph5501.bin'),
      ('pcsx2', 'PCSX2/inis/secrets.ini'),
      ('pcsx2', 'PCSX2/memcards/Mcd001.ps2'),
      ('retroarch', templateManifest),
    ]) {
      expect(has(bob, emu, rel), isFalse, reason: '$emu $rel');
    }
    // Anna's own files are untouched.
    expect(read(anna, 'retroarch', 'retroarch.cfg'), contains('abc'));
  });

  test('no settings yet: nothing is saved; a new save replaces the template, Forget removes it', () async {
    final anna = await profile('Anna');
    expect(await templates.save('dolphin', anna, profileName: 'Anna'), 0);
    expect(templates.info('dolphin'), isNull);
    put(anna, 'dolphin', 'Config/Dolphin.ini', '[General]\n');
    put(anna, 'dolphin', 'Config/Hotkeys.ini', '[Hotkeys]\n');
    await templates.save('dolphin', anna, profileName: 'Anna');
    io.File(p.join(anna.emulatorDir('dolphin'), 'Config', 'Hotkeys.ini')).deleteSync();
    expect(await templates.save('dolphin', anna, profileName: 'Anna 2'), 1);
    expect(io.File(p.join(root.templates, 'dolphin', 'Config', 'Hotkeys.ini')).existsSync(), isFalse);
    expect(templates.all().keys, ['dolphin']);
    expect(templates.forget('dolphin'), isTrue);
    expect(io.Directory(p.join(root.templates, 'dolphin')).existsSync(), isFalse);
  });

  test("a folder Gargosy didn't make is set aside, never deleted, and Forget leaves it", () async {
    final anna = await profile('Anna');
    final theirs = io.File(p.join(root.templates, 'eden', 'user', 'nand', 'save.bin'))
      ..createSync(recursive: true)
      ..writeAsStringSync('old');
    expect(templates.info('eden'), isNull);
    expect(templates.forget('eden'), isFalse);
    expect(theirs.existsSync(), isTrue);
    put(anna, 'eden', 'user/config/qt-config.ini', '[UI]\n');
    await templates.save('eden', anna, profileName: 'Anna');
    final aside = io.Directory(p.join(root.appData, 'set-aside')).listSync().single;
    expect(io.File(p.join(aside.path, 'user', 'nand', 'save.bin')).readAsStringSync(), 'old');
    expect(jsonDecode(io.File(p.join(root.templates, 'eden', templateManifest)).readAsStringSync())['profile'], 'p1');
  });

  test('stream keys, JSON strings, and a file in Windows code page lose their sign-ins too', () async {
    expect(
      withoutSignIns('twitch_stream_key = "live_1"\ninput_enable_hotkey = "nul"\n'),
      'twitch_stream_key = ""\ninput_enable_hotkey = "nul"\n',
    );
    expect(
      withoutSignIns('{\n  "api_key": "abc",\n  "user_token": 5,\n  "volume": 1\n}\n'),
      '{\n  "api_key": "",\n  "user_token": 5,\n  "volume": 1\n}\n',
    );
    final anna = await profile('Anna');
    // Latin-1 ("Användare"), which UTF-8 refuses: still cleaned, other bytes as they were.
    final cfg = io.File(p.join(anna.emulatorDir('retroarch'), 'retroarch.cfg'))..createSync(recursive: true);
    cfg.writeAsBytesSync([
      ...'cheevos_token = "abc"\nrgui_browser_directory = "C:\\Anv'.codeUnits,
      0xE4,
      ...'ndare"\n'.codeUnits,
    ]);
    await templates.save('retroarch', anna, profileName: 'Anna');
    final copied = io.File(p.join(root.templates, 'retroarch', 'retroarch.cfg')).readAsBytesSync();
    expect(String.fromCharCodes(copied), 'cheevos_token = ""\nrgui_browser_directory = "C:\\Anv\u00e4ndare"\n');
  });

  test('a letter that grows when lower-cased elsewhere in the file still lets the path match any case', () {
    const dir = r'C:\G\userdata\profiles\p1';
    expect(
      toTemplateText('title = \u0130stanbul\npath = C:\\G\\USERDATA\\profiles\\P1\\x\n', dir),
      'title = \u0130stanbul\npath = {{gargosy:profile}}\\x\n',
    );
  });

  test("a folder an install had in the way is copied into new profiles as it is, not read for markers", () async {
    final nand = io.File(p.join(root.templates, 'eden', 'user', 'nand', 'a.ini'))
      ..createSync(recursive: true)
      ..writeAsStringSync('x = {{gargosy:profile}}\n');
    final bob = await profile('Bob');
    expect(read(bob, 'eden', 'user/nand/a.ini'), 'x = {{gargosy:profile}}\n');
    expect(nand.existsSync(), isTrue);
  });

  test('every emulator with a template lists only settings', () {
    for (final entry in templateSettings.entries) {
      for (final rel in entry.value) {
        expect(
          rel,
          isNot(matches(RegExp(r'save|state|memcard|card|nand|mlc|cache|log', caseSensitive: false))),
          reason: '${entry.key} $rel',
        );
      }
    }
  });
}
