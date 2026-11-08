import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/emulators/emulator_library.dart';
import 'package:gargosy/emulators/emulator_updates.dart';

import '../helpers/profile_test_env.dart';

EmulatorInfo _emu(String id, {String? from, bool installed = true, String? downloadOff}) => EmulatorInfo(
  id: id,
  name: id,
  exe: '$id.exe',
  supported: true,
  installedExe: installed ? 'C:\\G\\emulators\\$id\\$id.exe' : null,
  installedFrom: from,
  downloadOff: downloadOff,
);

void main() {
  late MemoryPrefs prefs;
  late DateTime now;
  late Map<String, Object?> releases; // id → newest url, or an error
  late List<String> asked;

  EmulatorUpdateCheck checker() => EmulatorUpdateCheck(
    prefs: prefs,
    clock: () => now,
    latestUrl: (id) async {
      asked.add(id);
      final r = releases[id];
      if (r is Exception) throw r;
      return r as String?;
    },
  );

  setUp(() {
    prefs = MemoryPrefs();
    now = DateTime.utc(2026, 11, 8, 12);
    releases = {};
    asked = [];
  });

  test('a newer release is found; the same one, an import, an uninstalled one or a download off are not', () async {
    releases = {'dolphin': 'u/dolphin-3.zip', 'pcsx2': 'u/pcsx2-2.zip', 'mgba': 'u/mgba-9.zip'};
    final found = await checker().check([
      _emu('dolphin', from: 'u/dolphin-2.zip'),
      _emu('pcsx2', from: 'u/pcsx2-2.zip'),
      _emu('mgba', from: EmulatorLibrary.imported),
      _emu('ares', installed: false),
      _emu('ryujinx', from: 'u/ryu-1.zip', downloadOff: 'off'),
      _emu('flycast'), // installed before Gargosy noted the source
    ]);
    expect(found, {'dolphin': 'u/dolphin-3.zip'});
    expect(asked, ['dolphin', 'pcsx2'], reason: 'only emulators with a known download are asked');
  });

  test('at most one check a day unless forced; what it found shows in between', () async {
    final list = [_emu('dolphin', from: 'u/dolphin-2.zip')];
    releases = {'dolphin': 'u/dolphin-3.zip'};
    await checker().check(list);
    asked.clear();
    now = now.add(const Duration(hours: 23));
    expect(await checker().check(list), {'dolphin': 'u/dolphin-3.zip'});
    expect(asked, isEmpty);
    expect(await checker().check(list, force: true), {'dolphin': 'u/dolphin-3.zip'});
    expect(asked, ['dolphin']);
    asked.clear();
    now = now.add(const Duration(hours: 25));
    await checker().check(list);
    expect(asked, ['dolphin']);
  });

  test('an emulator updated since the check drops out of what was found', () async {
    releases = {'dolphin': 'u/dolphin-3.zip'};
    await checker().check([_emu('dolphin', from: 'u/dolphin-2.zip')]);
    expect(checker().remembered([_emu('dolphin', from: 'u/dolphin-3.zip')]), isEmpty);
    expect(checker().remembered([_emu('dolphin', installed: false)]), isEmpty);
    expect(checker().remembered([_emu('dolphin', from: 'u/dolphin-2.zip')]), {'dolphin': 'u/dolphin-3.zip'});
  });

  test("a release list that can't be read keeps what was found; none read means the next start checks", () async {
    final list = [_emu('dolphin', from: 'u/dolphin-2.zip'), _emu('pcsx2', from: 'u/pcsx2-1.zip')];
    releases = {'dolphin': 'u/dolphin-3.zip', 'pcsx2': 'u/pcsx2-1.zip'};
    await checker().check(list);
    final first = checker().lastCheck;

    now = now.add(const Duration(days: 2));
    releases = {'dolphin': Exception('rate limited'), 'pcsx2': 'u/pcsx2-2.zip'};
    expect(await checker().check(list), {'dolphin': 'u/dolphin-3.zip', 'pcsx2': 'u/pcsx2-2.zip'});
    expect(checker().lastCheck, isNot(first));

    final stamped = checker().lastCheck;
    now = now.add(const Duration(days: 2));
    releases = {'dolphin': Exception('offline'), 'pcsx2': Exception('offline')};
    expect(await checker().check(list), {'dolphin': 'u/dolphin-3.zip', 'pcsx2': 'u/pcsx2-2.zip'});
    expect(checker().lastCheck, stamped, reason: 'offline: not counted as a check');
  });

  test('no download given (the release service says nothing when offline) counts as not read', () async {
    final list = [_emu('dolphin', from: 'u/dolphin-2.zip')];
    releases = {'dolphin': 'u/dolphin-3.zip'};
    await checker().check(list);
    final stamped = checker().lastCheck;
    now = now.add(const Duration(days: 2));
    releases = {'dolphin': null};
    expect(await checker().check(list), {'dolphin': 'u/dolphin-3.zip'});
    expect(checker().lastCheck, stamped);
  });

  test('a last check in the future (a clock put back) is no reason to wait', () async {
    final list = [_emu('dolphin', from: 'u/dolphin-2.zip')];
    prefs.values[EmulatorUpdateCheck.lastKey] = DateTime.utc(2027, 6, 1).toIso8601String();
    releases = {'dolphin': 'u/dolphin-3.zip'};
    expect(await checker().check(list), {'dolphin': 'u/dolphin-3.zip'});
    expect(asked, ['dolphin']);
  });

  test('a damaged record reads as nothing found', () {
    prefs.values[EmulatorUpdateCheck.foundKey] = 'not json';
    expect(checker().remembered([_emu('dolphin', from: 'u/dolphin-2.zip')]), isEmpty);
  });
}
