import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/save/state_sync_service.dart';

import '../helpers/profile_test_env.dart';

/// State-sync plan S0.4: the per-emulator switches become one.
void main() {
  test('an old switch that was on turns the one switch on, and the old keys go', () async {
    final prefs = MemoryPrefs();
    await prefs.setBool(StateSyncService.legacyEnabledKey('duckstation'), true);
    await prefs.setBool(StateSyncService.legacyEnabledKey('pcsx2'), false);
    await migrateStateSyncPref(prefs);
    expect(prefs.getBool(StateSyncService.enabledKey), isTrue);
    expect(prefs.getKeys().where((k) => k.startsWith('${StateSyncService.enabledKey}_')), isEmpty);
  });

  test('old switches all off: sync stays off, the old keys go', () async {
    final prefs = MemoryPrefs();
    await prefs.setBool(StateSyncService.legacyEnabledKey('retroarch'), false);
    await migrateStateSyncPref(prefs);
    expect(prefs.getBool(StateSyncService.enabledKey), isNull);
    expect(prefs.getKeys(), isEmpty);
  });

  test('nothing set: nothing changes, sync is off', () async {
    final prefs = MemoryPrefs();
    await migrateStateSyncPref(prefs);
    expect(prefs.getKeys(), isEmpty);
  });

  test('a one switch already set wins over the old ones', () async {
    final prefs = MemoryPrefs();
    await prefs.setBool(StateSyncService.enabledKey, false);
    await prefs.setBool(StateSyncService.legacyEnabledKey('duckstation'), true);
    await migrateStateSyncPref(prefs);
    expect(prefs.getBool(StateSyncService.enabledKey), isFalse);
    expect(prefs.getKeys(), {StateSyncService.enabledKey});
  });

  test('only the old bool switches go: another pref sharing the prefix stays', () async {
    final prefs = MemoryPrefs();
    await prefs.setString('${StateSyncService.enabledKey}_at', '2026-10-13');
    await prefs.setBool(StateSyncService.legacyEnabledKey('pcsx2'), true);
    await migrateStateSyncPref(prefs);
    expect(prefs.getBool(StateSyncService.enabledKey), isTrue);
    expect(prefs.getKeys(), {StateSyncService.enabledKey, '${StateSyncService.enabledKey}_at'});
  });
}
