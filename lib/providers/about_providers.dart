import 'dart:io' as io;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'romm_providers.dart';

/// Opens a web address or a file with Windows' default program; tests replace it.
final externalOpenerProvider = Provider<void Function(String target)>(
  (ref) => (target) {
    // Explorer, not cmd: nothing in an address or a path (&, %, |) is read
    // as a command (#231).
    io.Process.start('explorer.exe', [target]);
  },
);

/// The active profile's RomM version, or null when the server can't be asked.
final rommServerVersionProvider = FutureProvider<String?>((ref) async {
  final romm = ref.watch(rommServiceProvider);
  if (romm == null) return null;
  final caps = await romm.fetchCapabilities();
  return caps.version == '0.0.0' ? null : caps.version;
});
