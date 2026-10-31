import 'dart:io' as io;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'romm_providers.dart';

/// Opens a web address or a file with Windows' default program; tests replace it.
final externalOpenerProvider = Provider<void Function(String target)>(
  (ref) => (target) {
    // cmd reads & as "and then": a web address's query (#231) is escaped.
    io.Process.start('cmd', ['/c', 'start', '', target.startsWith('http') ? target.replaceAll('&', '^&') : target]);
  },
);

/// The active profile's RomM version, or null when the server can't be asked.
final rommServerVersionProvider = FutureProvider<String?>((ref) async {
  final romm = ref.watch(rommServiceProvider);
  if (romm == null) return null;
  final caps = await romm.fetchCapabilities();
  return caps.version == '0.0.0' ? null : caps.version;
});
