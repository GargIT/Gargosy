import '../core/save/catalog/save_catalog.dart';
import '../core/save/catalog/save_maker.dart';

/// An emulator (RetroArch with its core) a game can be played in.
class EmulatorOption {
  const EmulatorOption(this.maker, this.name);
  final SaveMaker maker;

  /// "PCSX2", or "RetroArch · Beetle PSX HW".
  final String name;
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

  String nameOf(SaveMaker maker) =>
      emulators.where((e) => e.maker == maker).firstOrNull?.name ??
      emulators.where((e) => e.maker.emulatorId == maker.emulatorId).firstOrNull?.name ??
      maker.emulatorId;
}
