import 'package:gargosy/core/romm/romm_models.dart';

/// A RomM game as `/api/roms` sends it, with just the fields Gargosy reads.
Map<String, dynamic> gameJson(
  int id,
  String name, {
  String platform = 'ps2',
  String platformName = 'PlayStation 2',
  String? fsName,
  bool multi = false,
  int size = 1000,
}) => {
  'id': id,
  'name': name,
  'platform_id': 1,
  'platform_slug': platform,
  'platform_fs_slug': platform,
  'platform_display_name': platformName,
  'fs_name': fsName ?? '$name.chd',
  'file_size_bytes': size,
  'has_multiple_files': multi,
  'path_cover_large': '/assets/romm/resources/roms/1/$id/cover/big.png',
};

Game game(int id, String name, {String platform = 'ps2', String? fsName, bool multi = false}) =>
    Game.fromJson(gameJson(id, name, platform: platform, fsName: fsName, multi: multi));
