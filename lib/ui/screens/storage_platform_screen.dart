import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/input/gamepad_service.dart';
import '../../core/romm/romm_models.dart';
import '../../library/library_snapshot.dart';
import '../../library/storage_usage.dart';
import '../../play/play_controller.dart';
import '../../profiles/path_guard.dart';
import '../../profiles/profile_providers.dart';
import '../../providers/download_providers.dart';
import '../shell/backdrop.dart';
import '../shell/page_top_bar.dart';
import '../theme/tokens.dart';
import '../widgets/controller_dialogs.dart';
import '../widgets/format.dart';
import '../widgets/g_focusable.dart';
import '../widgets/hint_bar.dart';
import '../widgets/save_list/save_labels.dart';
import '../widgets/toast.dart';
import 'settings/storage_section.dart';

/// A platform's games on this PC (Settings → Storage, #145), largest first:
/// A deletes one from this PC, X marks several for Delete marked. Only the
/// ROM goes: saves are elsewhere and stay.
class StoragePlatformScreen extends ConsumerStatefulWidget {
  const StoragePlatformScreen({super.key, required this.folder});

  /// The platform's folder in `roms\` (RomM's slug).
  final String folder;

  @override
  ConsumerState<StoragePlatformScreen> createState() => _StoragePlatformScreenState();
}

class _StoragePlatformScreenState extends ConsumerState<StoragePlatformScreen> {
  final _marked = <String>{};
  late Future<List<RomEntry>> _entries = _read();

  Future<List<RomEntry>> _read() {
    final dir = p.join(ref.read(appRootProvider).roms, widget.folder);
    return Future(() => romsIn(dir));
  }

  /// This profile's games by the path they're at.
  Map<String, Game> _byPath() {
    final files = ref.read(romFilesProvider);
    return {for (final g in ref.read(gamesOnThisPcProvider)) p.normalize(files.pathFor(g)).toLowerCase(): g};
  }

  Future<void> _delete(List<RomEntry> entries) async {
    if (entries.isEmpty) return;
    if (ref.read(playControllerProvider).runningGameId != null) {
      showToast(context, "Close the game first: nothing is deleted while one runs.");
      return;
    }
    final games = _byPath();
    final others = entries.where((e) => games[p.normalize(e.path).toLowerCase()] == null).length;
    final bytes = entries.fold(0, (n, e) => n + e.bytes);
    final what = entries.length == 1
        ? (games[_key(entries.single)]?.displayName ?? entries.single.name)
        : '${entries.length} games';
    final shared = switch (others) {
      0 => '',
      1 => " One isn't in this profile's library: another profile may have downloaded it, and loses it too.",
      _ => " $others aren't in this profile's library: another profile may have downloaded them, and loses them too.",
    };
    final ok = await showConfirm(
      context,
      title: 'Delete $what from this PC?',
      body: 'Frees ${formatBytes(bytes)}. Only the ROM files go; your saves stay, and the games stay on RomM.$shared',
      yes: 'Delete',
      no: 'Keep',
      focusYes: false,
      danger: true,
    );
    if (!ok || !mounted) return;
    final guard = PathGuard(ref.read(appRootProvider));
    var failed = 0;
    for (final e in entries) {
      try {
        final game = games[_key(e)];
        if (game != null) {
          await ref.read(downloadsProvider.notifier).delete(game);
        } else {
          final path = guard.check(e.path);
          io.Directory(path).existsSync() ? io.Directory(path).deleteSync(recursive: true) : io.File(path).deleteSync();
        }
      } on Object {
        failed++;
      }
    }
    ref.read(romFilesVersionProvider.notifier).state++;
    ref.invalidate(storageUsageProvider);
    if (!mounted) return;
    if (failed > 0) showToast(context, "$failed couldn't be deleted (in use?).");
    setState(() {
      _marked.clear();
      _entries = _read();
    });
  }

  static String _key(RomEntry e) => p.normalize(e.path).toLowerCase();

  @override
  Widget build(BuildContext context) {
    final name = platformNameFor(ref, widget.folder);
    ref.watch(gamesOnThisPcProvider);
    final games = _byPath();
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Backdrop(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const PageTopBar(scrolled: false),
            Expanded(
              child: FutureBuilder<List<RomEntry>>(
                future: _entries,
                builder: (context, snap) {
                  final entries = snap.data;
                  if (entries == null) return const Center(child: CircularProgressIndicator());
                  final marked = [
                    for (final e in entries)
                      if (_marked.contains(_key(e))) e,
                  ];
                  return Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 900),
                      child: ListView(
                        key: const Key('page-Storage-platform'),
                        padding: const EdgeInsets.symmetric(horizontal: GSpace.s8, vertical: GSpace.s6),
                        children: [
                          Text(
                            name,
                            style: const TextStyle(fontSize: GFont.xxxl, fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: GSpace.s1),
                          Text(
                            '${entries.length} ${entries.length == 1 ? 'game' : 'games'} · '
                            '${formatBytes(entries.fold(0, (n, e) => n + e.bytes))} on this PC',
                            style: const TextStyle(color: GColors.fgSecondary),
                          ),
                          const SizedBox(height: GSpace.s4),
                          if (marked.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: GSpace.s3),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: GFocusable(
                                  key: const ValueKey('storage-delete-marked'),
                                  borderRadius: GRadius.pill,
                                  onActivate: () => _delete(marked),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: GSpace.s5, vertical: GSpace.s2),
                                    decoration: BoxDecoration(
                                      color: GColors.dangerFill,
                                      borderRadius: BorderRadius.circular(GRadius.pill),
                                    ),
                                    child: Text(
                                      'Delete marked (${marked.length} · '
                                      '${formatBytes(marked.fold(0, (n, e) => n + e.bytes))})',
                                      style: const TextStyle(fontWeight: FontWeight.w700),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          for (final (i, e) in entries.indexed)
                            _row(e, games[_key(e)], autofocus: i == 0, marked: _marked.contains(_key(e))),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const HintBar(
              hints: [
                Hint(GameAction.confirm, 'Delete'),
                Hint(GameAction.detail, 'Mark'),
                Hint(GameAction.back, 'Back'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(RomEntry e, Game? game, {required bool autofocus, required bool marked}) {
    final played = game?.lastPlayed;
    final line = [
      formatBytes(e.bytes),
      if (game == null)
        "not in this profile's library"
      else
        played == null ? 'never played' : 'played ${formatSaveTime(played)}',
    ].join(' · ');
    return Padding(
      key: ValueKey('storage-rom-${e.name}'),
      padding: const EdgeInsets.only(bottom: GSpace.s2),
      child: GFocusable(
        autofocus: autofocus,
        onActivate: () => _delete([e]),
        onDetail: () => setState(() => marked ? _marked.remove(_key(e)) : _marked.add(_key(e))),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: GSpace.s4, vertical: GSpace.s3),
          decoration: BoxDecoration(
            color: GColors.card,
            borderRadius: BorderRadius.circular(GRadius.card),
            border: Border.all(color: marked ? GColors.danger : GColors.border),
          ),
          child: Row(
            children: [
              Icon(
                marked ? Icons.check_box : Icons.check_box_outline_blank,
                color: marked ? GColors.danger : GColors.fgMuted,
              ),
              const SizedBox(width: GSpace.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      game?.displayName ?? e.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: GFont.lg, fontWeight: FontWeight.w600),
                    ),
                    Text(
                      line,
                      style: const TextStyle(fontSize: GFont.sm, color: GColors.fgSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
