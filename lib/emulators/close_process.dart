import 'dart:async';
import 'dart:io' as io;

/// Asks [process] to close (as its window's close button does: taskkill
/// without /F), then ends it after 10 s.
Future<void> closeProcess(io.Process process) async {
  await io.Process.run('taskkill', ['/PID', '${process.pid}', '/T']);
  try {
    await process.exitCode.timeout(const Duration(seconds: 10));
  } on TimeoutException {
    process.kill();
    // Returned only once it's gone: the next launch mustn't meet it.
    await process.exitCode.timeout(const Duration(seconds: 10), onTimeout: () => -1);
  }
}
