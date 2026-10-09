import '../core/emulator/retroarch_core_list.dart';
import '../core/save/catalog/save_catalog.dart';
import '../core/save/catalog/save_maker.dart';

/// An emulator (RetroArch with its core) a game can be played in.
class EmulatorOption {
  const EmulatorOption(this.maker, this.name, {this.cores = const [], this.fullscreen});

  /// The emulator, with the platform's core for RetroArch.
  final SaveMaker maker;

  /// "PCSX2", "RetroArch".
  final String name;

  /// RetroArch's cores for the platform (empty for other emulators).
  final List<RetroArchCore> cores;

  /// Whether it starts in full screen for this profile; null when Gargosy
  /// can't tell it to (set in the emulator itself).
  final bool? fullscreen;

  /// [core] (a bare core id) as the core picker shows it.
  String coreName(String? core) =>
      cores.where((c) => bareCoreId(c.id) == core).firstOrNull?.displayName ?? core ?? '';
}


/// What the play screen offers for a game: the installed emulators for its
/// platform, the one remembered for it, the platform's default, and every
/// save of it (this PC, backups, RomM).
class PlayMenu {
  const PlayMenu({required this.emulators, required this.catalog, this.remembered, this.platformDefault});

  final List<EmulatorOption> emulators;
  final SaveMaker? remembered;
  final SaveMaker? platformDefault;
  final SaveCatalog catalog;

  /// The emulator the game plays in when none is picked.
  SaveMaker? get forThisGame => remembered ?? platformDefault;

  Set<String> get installedIds => {for (final e in emulators) e.maker.emulatorId};

  EmulatorOption? optionOf(SaveMaker maker) => emulators.where((e) => e.maker.emulatorId == maker.emulatorId).firstOrNull;

  /// "PCSX2", or "RetroArch · Beetle PSX HW" for RetroArch with a core.
  String nameOf(SaveMaker maker) {
    final o = optionOf(maker);
    if (o == null) return maker.emulatorId;
    return maker.coreId == null || o.cores.isEmpty ? o.name : '${o.name} · ${o.coreName(maker.coreId)}';
  }
}
