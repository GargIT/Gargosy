import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/library/image_cache.dart';
import 'package:gargosy/profiles/app_root.dart';
import 'package:gargosy/ui/screens/settings/image_cache_section.dart';
import 'package:path/path.dart' as p;

import '../helpers/profile_test_env.dart';

void main() {
  late io.Directory tmp;
  late AppRoot root;

  setUp(() {
    tmp = io.Directory.systemTemp.createTempSync('gargosy-images-');
    root = AppRoot(tmp.path);
  });
  tearDown(() => deleteTempDir(tmp.path));

  test('the cache lives in userdata\\app\\cache\\images, not temp', () {
    expect(imageCacheDir(root), p.join(tmp.path, 'userdata', 'app', 'cache', 'images'));
  });

  test('the size is 10 000 until picked, and a value not offered reads as the default', () async {
    final prefs = MemoryPrefs();
    expect(ImageCacheSize(prefs).state, 10000);
    final size = ImageCacheSize(prefs);
    await size.pick(25000);
    expect(size.state, 25000);
    expect(prefs.values[ImageCacheSize.key], '25000');
    expect(ImageCacheSize(prefs).state, 25000);
    prefs.values[ImageCacheSize.key] = '7';
    expect(ImageCacheSize(prefs).state, 10000);
  });

  test('a choice reads with its rough size', () {
    expect(imageCacheChoiceLabel(25000), '25 000 images (about 2.9 GB)');
    expect(imageCacheChoiceLabel(2000), '2 000 images (about 234 MB)');
  });

  test('usage counts the files in the folder, and nothing when there is none', () async {
    final dir = imageCacheDir(root);
    expect(await imageCacheUsage(dir), (files: 0, bytes: 0));
    io.Directory(dir).createSync(recursive: true);
    io.File(p.join(dir, 'a.png')).writeAsBytesSync(List.filled(10, 0));
    io.File(p.join(dir, 'b.png')).writeAsBytesSync(List.filled(5, 0));
    expect(await imageCacheUsage(dir), (files: 2, bytes: 15));
  });

  test('the cache from before (temp\\gargosy-images and its list) is removed, the new one kept', () async {
    final old = io.Directory(p.join(root.appData, 'temp', 'gargosy-images'))..createSync(recursive: true);
    io.File(p.join(old.path, 'x.png')).writeAsStringSync('x');
    final list = io.File(p.join(root.appData, 'support', 'gargosy-images.json'))
      ..createSync(recursive: true)
      ..writeAsStringSync('[]');
    final download = io.File(p.join(root.appData, 'temp', 'game.zip'))..writeAsStringSync('z');
    final kept = io.File(p.join(imageCacheDir(root), 'y.png'))
      ..createSync(recursive: true)
      ..writeAsStringSync('y');

    await removeOldImageCache(root);

    expect(old.existsSync(), isFalse);
    expect(list.existsSync(), isFalse);
    expect(download.existsSync(), isTrue);
    expect(kept.existsSync(), isTrue);
    await removeOldImageCache(root); // nothing left: no error
  });

  test('the cache makes its folder on first use', () async {
    final f = await FolderFileSystem(imageCacheDir(root)).createFile('c.png');
    expect(p.dirname(f.path), imageCacheDir(root));
    expect(io.Directory(imageCacheDir(root)).existsSync(), isTrue);
  });
}
