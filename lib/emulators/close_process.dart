import 'dart:async';
import 'dart:io' as io;

import 'package:flutter/foundation.dart' show debugPrint;

/// Asks [process] to close (as its window's close button does: taskkill
/// without /F), then ends it after [wait]; one that is still there after
/// that is ended with its children (`taskkill /F /T`).
Future<void> closeProcess(io.Process process, {Duration wait = const Duration(seconds: 10)}) async {
  final pid = process.pid;
  final asked = await io.Process.run('taskkill', ['/PID', '$pid', '/T']);
  debugPrint('[Close] asked $pid to close: taskkill ${asked.exitCode} ${'${asked.stdout}${asked.stderr}'.trim()}');
  try {
    await process.exitCode.timeout(wait);
    debugPrint('[Close] $pid closed');
    return;
  } on TimeoutException {
    debugPrint('[Close] $pid still running after ${wait.inSeconds} s: ending it');
  }
  process.kill();
  try {
    await process.exitCode.timeout(const Duration(seconds: 5));
    return;
  } on TimeoutException {
    final forced = await io.Process.run('taskkill', ['/PID', '$pid', '/T', '/F']);
    debugPrint('[Close] forced $pid: taskkill ${forced.exitCode} ${'${forced.stdout}${forced.stderr}'.trim()}');
  }
  // Returned only once it's gone: the next launch mustn't meet it.
  await process.exitCode.timeout(const Duration(seconds: 10), onTimeout: () => -1);
}
