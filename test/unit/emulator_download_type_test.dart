// Adapted from Freegosy (MIT, © 2026 abduznik).
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/emulator/emulator_download_service.dart';
import 'package:gargosy/core/emulator/emulator_registry_data.dart';
import 'package:gargosy/core/platform/platform_info.dart';

void main() {
  final dolphin = kEmulatorDefinitions.firstWhere((d) => d['id'] == 'dolphin');

  test('Dolphin is scraped from its site on Windows and macOS', () {
    expect(EmulatorDownloadService.typeFor(dolphin, PlatformInfo('windows'), fallback: 'direct'), 'dolphin');
    expect(EmulatorDownloadService.typeFor(dolphin, PlatformInfo('macos'), fallback: 'direct'), 'dolphin');
  });

  test('the fallback is used when a definition has no type', () {
    expect(EmulatorDownloadService.typeFor(const {}, PlatformInfo('linux'), fallback: 'direct'), 'direct');
  });
}
