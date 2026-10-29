import 'package:gargosy/library/disk_space.dart';

/// A [DiskInfo] with [free] bytes per path (null: can't be told) and
/// Windows' volumes by drive letter.
class FakeDisk implements DiskInfo {
  FakeDisk(this.free, {this.total = 1 << 50});

  /// Nothing can be told: every check is skipped.
  static final none = FakeDisk((_) => null);

  final int? Function(String path) free;
  final int total;

  @override
  ({int free, int total})? usage(String path) => switch (free(path)) {
    final f? => (free: f, total: total),
    null => null,
  };

  @override
  String volumeOf(String path) => const WindowsDiskInfo().volumeOf(path);
}
