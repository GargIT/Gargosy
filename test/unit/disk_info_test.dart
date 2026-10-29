import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/platform/platform_info.dart';
import 'package:gargosy/library/disk_space.dart';
import 'package:path/path.dart' as p;

void main() {
  group('diskInfoFor (#201)', () {
    test('Windows reads its drives', () {
      expect(diskInfoFor(const PlatformInfo('windows')), isA<WindowsDiskInfo>());
    });

    test('an OS without disk info yet is refused', () {
      expect(() => diskInfoFor(const PlatformInfo('linux')), throwsUnsupportedError);
    });
  });

  group('WindowsDiskInfo', () {
    const disk = WindowsDiskInfo();

    test('a volume is its drive letter, any case; a share is the share', () {
      expect(disk.volumeOf(r'd:\Games\roms'), 'D:');
      expect(disk.volumeOf(r'D:\other'), disk.volumeOf(r'd:\Games'));
      expect(disk.volumeOf(r'\\nas\share\roms'), r'\\NAS\SHARE');
    });

    test('a folder not made yet is told by the nearest one that is', () {
      final temp = io.Directory.systemTemp.path;
      final here = disk.usage(temp);
      final later = disk.usage(p.join(temp, 'not', 'made', 'yet'));
      expect(here, isNotNull);
      expect(later?.total, here!.total);
      expect(disk.freeOf(temp), greaterThan(0));
    });
  });
}
