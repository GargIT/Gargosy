import 'dart:convert';
import 'dart:io' as io;

import 'path_guard.dart';

/// The JSON object in [path]; null when the file is missing. Throws
/// [FormatException] when it isn't a JSON object.
Future<Map<String, dynamic>?> readJsonObject(String path) async => readJsonObjectSync(path);

/// [readJsonObject], synchronously (small files the UI needs at once).
Map<String, dynamic>? readJsonObjectSync(String path) {
  final file = io.File(path);
  if (!file.existsSync()) return null;
  final decoded = jsonDecode(file.readAsStringSync());
  if (decoded is! Map<String, dynamic>) throw FormatException('Not a JSON object', path);
  return decoded;
}

/// Writes [data] to [path] (checked by [guard]) through a `.tmp` file renamed into place.
Future<void> writeJsonObject(PathGuard guard, String path, Map<String, dynamic> data) =>
    writeBytesAtomic(guard, path, utf8.encode(const JsonEncoder.withIndent('  ').convert(data)));

/// Writes [bytes] to [path] (checked by [guard]) through a `.tmp` file renamed into place.
Future<void> writeBytesAtomic(PathGuard guard, String path, List<int> bytes) async {
  final target = guard.check(path);
  final tmp = io.File(guard.check('$target.tmp'));
  await tmp.parent.create(recursive: true);
  await tmp.writeAsBytes(bytes, flush: true);
  await tmp.rename(target);
}
