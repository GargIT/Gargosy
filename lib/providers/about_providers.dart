import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/platform/external_opener.dart';
import '../core/platform/platform_info.dart';

import 'romm_providers.dart';

/// Opens a web address or a file with Windows' default program; tests replace it.
final externalOpenerProvider = Provider<ExternalOpener>((ref) => externalOpenerFor(PlatformInfo.current));

/// The active profile's RomM version, or null when the server can't be asked.
final rommServerVersionProvider = FutureProvider<String?>((ref) async {
  final romm = ref.watch(rommServiceProvider);
  if (romm == null) return null;
  final caps = await romm.fetchCapabilities();
  return caps.version == '0.0.0' ? null : caps.version;
});
