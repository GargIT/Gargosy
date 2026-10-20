import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/save/state_sync_service.dart';
import 'package:gargosy/core/storage/shared_preferences_app_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('"Save states on RomM" is on until the player turns it off', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = SharedPreferencesAppPreferences(await SharedPreferences.getInstance());
    expect(StateSyncService.isOn(prefs), isTrue);
    await prefs.setBool(StateSyncService.enabledKey, false);
    expect(StateSyncService.isOn(prefs), isFalse);
  });
}
