import 'dart:io' as io;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:path/path.dart' as p;

import '../core/platform/shortcut_maker.dart';
import '../core/romm/romm_models.dart';
import '../play/outside_launch.dart';
import '../profiles/json_file.dart';
import '../profiles/profile_paths.dart';

/// #223: the game page's Create shortcut. A link on the player's desktop to
/// [exe] with `--play=<game> --profile=<profile>`, named after the game,
/// with its cover as icon (kept in the profile's `cache\shortcuts\`).
/// Returns the link's path.
Future<String> createGameShortcut({
  required Game game,
  required ProfilePaths profile,
  required ShortcutMaker maker,
  required String exe,
  Uint8List? iconPng,
}) async {
  final desktop = await maker.desktopDir();
  if (desktop == null) throw const io.FileSystemException('There is no desktop folder');
  String? icon;
  if (iconPng != null) {
    icon = p.join(profile.cache, 'shortcuts', '${game.id}.ico');
    await io.Directory(p.dirname(profile.guard.check(icon))).create(recursive: true);
    await writeBytesAtomic(profile.guard, icon, icoOfPng(iconPng));
  }
  final link = freeLinkPath(desktop, shortcutName(game.displayName), maker.extension);
  await maker.make(
    linkPath: link,
    target: exe,
    args: ['${OutsideLaunch.playArg}${game.id}', '${OutsideLaunch.profileArg}${profile.id}'],
    workingDir: p.dirname(exe),
    iconPath: icon,
    description: game.displayName,
  );
  return link;
}

/// [title] as a file name Windows takes: no `<>:"/\|?*` or control
/// characters, no trailing dots or spaces, at most 100 characters.
String shortcutName(String title) {
  var name = title.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  if (name.length > 100) name = name.substring(0, 100);
  name = name.replaceAll(RegExp(r'[. ]+$'), '');
  return name.isEmpty ? 'Game' : name;
}

/// `<dir>\<name><ext>`, or `<name> (2)<ext>` and on when that is taken: a
/// link never replaces a file on the desktop.
String freeLinkPath(String dir, String name, String ext) {
  var path = p.join(dir, '$name$ext');
  for (var n = 2; io.FileSystemEntity.typeSync(path) != io.FileSystemEntityType.notFound; n++) {
    path = p.join(dir, '$name ($n)$ext');
  }
  return path;
}

/// An `.ico` holding one 256 × 256 PNG (Windows Vista and later read PNG
/// icons as they are).
Uint8List icoOfPng(Uint8List png) {
  final b = BytesBuilder()
    ..add(_le16(0)) // reserved
    ..add(_le16(1)) // icon
    ..add(_le16(1)) // one image
    ..add([0, 0, 0, 0]) // 256 × 256 (0 means 256), no palette, reserved
    ..add(_le16(1)) // colour planes
    ..add(_le16(32)) // bits per pixel
    ..add(_le32(png.length))
    ..add(_le32(22)) // the PNG starts after this 6 + 16 byte header
    ..add(png);
  return b.toBytes();
}

List<int> _le16(int v) => [v & 0xff, (v >> 8) & 0xff];
List<int> _le32(int v) => [v & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff, (v >> 24) & 0xff];

/// [image] (a cover, any format Flutter decodes) fitted into a transparent
/// 256 × 256 square, as PNG; null when it can't be decoded.
Future<Uint8List?> squareIconPng(Uint8List image) async {
  try {
    final codec = await ui.instantiateImageCodec(image);
    final src = (await codec.getNextFrame()).image;
    const size = 256.0;
    final scale = size / (src.width > src.height ? src.width : src.height);
    final w = src.width * scale, h = src.height * scale;
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawImageRect(
      src,
      ui.Rect.fromLTWH(0, 0, src.width.toDouble(), src.height.toDouble()),
      ui.Rect.fromLTWH((size - w) / 2, (size - h) / 2, w, h),
      ui.Paint()..filterQuality = ui.FilterQuality.high,
    );
    final out = await recorder.endRecording().toImage(size.toInt(), size.toInt());
    final bytes = await out.toByteData(format: ui.ImageByteFormat.png);
    return bytes?.buffer.asUint8List();
  } on Object {
    return null;
  }
}
