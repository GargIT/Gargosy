import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/romm/romm_models.dart';
import '../../../library/game_versions.dart';
import '../../../library/library_snapshot.dart';
import '../../widgets/g_dropdown.dart';
import '../../widgets/toast.dart';
import 'game_screen.dart';
import 'open_game.dart';
import '../../../l10n/tr.dart';

/// The game page's Version (#95): the game's regions and revisions on RomM,
/// those on this PC marked. Picking one opens its page in place of this one.
class VersionField extends ConsumerStatefulWidget {
  const VersionField({super.key, required this.game});

  final Game game;

  @override
  ConsumerState<VersionField> createState() => _VersionFieldState();
}

class _VersionFieldState extends ConsumerState<VersionField> {
  final _field = GlobalKey();
  bool _open = false;

  Future<void> _pick(List<GameVersion> versions, Set<String> onPc) async {
    setState(() => _open = true);
    final i = await showDropdown(
      context,
      field: _field,
      labels: [for (final v in versions) _label(v, onPc)],
      current: 0,
    );
    if (!mounted) return;
    setState(() => _open = false);
    if (i == null || i == 0) return;
    final other = await gameOfVersion(ref, versions[i].id);
    if (!mounted) return;
    if (other == null) {
      showToast(context, tr('Couldn\'t open that version.'));
      return;
    }
    await Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => GameScreen(game: other)));
  }

  static String _label(GameVersion v, Set<String> onPc) =>
      '${versionLabel(v.name, v.fsNameNoExt)}${onPc.contains(v.id) ? '  ·  on this PC' : ''}';

  @override
  Widget build(BuildContext context) {
    final versions = allVersions(widget.game);
    final onPc = {for (final g in ref.watch(gamesOnThisPcProvider)) g.id};
    return KeyedSubtree(
      key: _field,
      child: GDropdownField(
        key: const ValueKey('game-version'),
        icon: Icons.layers_outlined,
        text: tr('Version: {0}  ({1})', [
          versionLabel(versions.first.name, versions.first.fsNameNoExt),
          versions.length,
        ]),
        open: _open,
        compact: true,
        onPress: () => _pick(versions, onPc),
      ),
    );
  }
}
