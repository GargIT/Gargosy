import '../core/emulator/platform_slugs.dart';
import '../core/romm/romm_models.dart';
import '../library/dsi_title.dart';
import '../l10n/tr.dart';

/// Emulators that start a DSiWare game but can't keep its save (#114):
/// standalone melonDS keeps it inside the DSi's NAND, and only for a title
/// installed there with its Title Manager, so nothing is saved to sync.
/// melonDS DS (RetroArch) writes it beside the other saves.
const dsiWareCantSaveIn = {'melonds'};

String get dsiWareCantSaveNote => tr(
  'melonDS can\'t save DSiWare games, so Gargosy doesn\'t start them there. Play them in RetroArch with melonDS DS (Start → Emulators).',
);

/// The emulators [game] at [romPath] mustn't be played in: [dsiWareCantSaveIn]
/// for a DSiWare game, else none.
Future<Set<String>> emulatorsUnfitFor(Game game, String? romPath) async {
  if (romPath == null || canonicalPlatformSlug(game.platformSlug?.toLowerCase() ?? '') != 'nds') return const {};
  final title = await readDsiTitle(romPath);
  return title != null && title.dsiWare ? dsiWareCantSaveIn : const {};
}
