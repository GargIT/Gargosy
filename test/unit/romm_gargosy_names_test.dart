import 'dart:io' as io;

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/romm/romm_models.dart';
import 'package:gargosy/core/romm/romm_service.dart';
import 'package:gargosy/core/save/catalog/save_maker.dart';
import 'package:path/path.dart' as p;

/// Gargosy's own names on RomM: its saves' slot and tag, and its device.
/// Saves in Freegosy's old `freegosy` slot are still read, never pruned.
void main() {
  late Dio dio;
  late RommService romm;
  final sent = <RequestOptions>[];
  var saves = <Map<String, dynamic>>[];

  setUp(() {
    sent.clear();
    saves = [];
    dio = Dio(BaseOptions(baseUrl: 'https://romm.example.com'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (o, h) {
          sent.add(o);
          final data = o.method == 'GET' && o.path == '/api/saves' ? saves : <String, dynamic>{'id': 1};
          h.resolve(Response(requestOptions: o, statusCode: 200, data: data));
        },
      ),
    );
    romm = RommService(
      RomMConfig(baseUrl: 'https://romm.example.com', username: '', password: '', apiKey: 'k'),
      dio: dio,
    );
  });

  test("a save with no slot or tag goes up in Gargosy's slot, tagged gargosy", () async {
    final tmp = await io.Directory.systemTemp.createTemp('gargosy_names');
    addTearDown(() => tmp.delete(recursive: true));
    final file = io.File(p.join(tmp.path, 'G.srm'))..writeAsStringSync('x');
    await romm.uploadSave('42', file);
    final post = sent.singleWhere((o) => o.method == 'POST' && o.path == '/api/saves');
    expect(post.queryParameters['slot'], 'gargosy');
    expect(post.queryParameters['emulator'], 'gargosy');
  });

  test('the device registers as client Gargosy', () async {
    await romm.registerDevice(name: 'PC', platform: 'windows');
    final post = sent.singleWhere((o) => o.path == '/api/devices');
    expect((post.data as Map)['client'], 'Gargosy');
  });

  test('the device asks for its existing registration in the body, where RomM reads it', () async {
    await romm.registerDevice(name: 'PC', platform: 'windows');
    final post = sent.singleWhere((o) => o.path == '/api/devices');
    expect((post.data as Map)['allow_existing'], isTrue);
    expect(post.queryParameters, isNot(contains('allow_existing')));
  });

  test("a device made for one profile asks RomM for a new one, not the PC's shared one (#293)", () async {
    await romm.registerDevice(name: 'PC', platform: 'windows', allowDuplicate: true);
    final post = sent.singleWhere((o) => o.path == '/api/devices');
    expect((post.data as Map)['allow_duplicate'], isTrue);
    await romm.registerDevice(name: 'PC', platform: 'windows');
    expect((sent.last.data as Map), isNot(contains('allow_duplicate')));
  });

  test("an upload from a device sends its hash, RomM's baseline for that device", () async {
    final tmp = await io.Directory.systemTemp.createTemp('gargosy_names');
    addTearDown(() => tmp.delete(recursive: true));
    final file = io.File(p.join(tmp.path, 'G.srm'))..writeAsStringSync('x');
    await romm.uploadSave('42', file, deviceId: 'dev-1', contentHash: 'abc');
    final post = sent.singleWhere((o) => o.method == 'POST' && o.path == '/api/saves');
    expect(post.queryParameters['device_id'], 'dev-1');
    expect(post.queryParameters['content_hash'], 'abc');
  });

  test('an upload without a device sends no hash', () async {
    final tmp = await io.Directory.systemTemp.createTemp('gargosy_names');
    addTearDown(() => tmp.delete(recursive: true));
    final file = io.File(p.join(tmp.path, 'G.srm'))..writeAsStringSync('x');
    await romm.uploadSave('42', file, contentHash: 'abc');
    final post = sent.singleWhere((o) => o.method == 'POST' && o.path == '/api/saves');
    expect(post.queryParameters, isNot(contains('content_hash')));
  });

  test("confirming a copy sends RomM's hash with the device", () async {
    await romm.confirmSaveDownloaded(7, deviceId: 'dev-1', contentHash: 'abc');
    final post = sent.singleWhere((o) => o.path == '/api/saves/7/downloaded');
    expect(post.data, {'device_id': 'dev-1', 'content_hash': 'abc'});
  });

  test("pruning removes only Gargosy's slot, never saves in Freegosy's old slot", () async {
    saves = [
      for (var i = 1; i <= 3; i++) {'id': i, 'slot': 'gargosy', 'created_at': '2026-10-0${4 - i}T10:00:00Z'},
      for (var i = 11; i <= 13; i++) {'id': i, 'slot': 'freegosy', 'created_at': '2026-09-0${14 - i}T10:00:00Z'},
    ];
    await romm.pruneOldSaves('42', keepCount: 1);
    final delete = sent.singleWhere((o) => o.path == '/api/saves/delete');
    expect((delete.data as Map)['saves'], [2, 3]);
  });

  test('a save tagged gargosy or gargosy has no known maker', () {
    for (final tag in ['gargosy', 'freegosy']) {
      expect(resolveSaveMaker(tag, emulatorIds: const {'pcsx2', 'gargosy', 'freegosy'}), isNull, reason: tag);
    }
  });
}
