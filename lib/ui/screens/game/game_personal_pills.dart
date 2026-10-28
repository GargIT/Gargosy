import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/romm/romm_models.dart';
import '../../../play/play_engine.dart';
import '../../../providers/library_providers.dart';
import '../../theme/tokens.dart';
import '../../widgets/controller_dialogs.dart';
import '../../widgets/g_focusable.dart';
import '../../widgets/toast.dart';
import '../../../l10n/tr.dart';

/// The player's own RomM fields for the game, as RomM's pills (spec Part 1):
/// status (with Backlog and Now playing), rating 0–10 and completion. A
/// change RomM doesn't take goes back to what it was.
class GamePersonalPills extends ConsumerStatefulWidget {
  const GamePersonalPills({super.key, required this.game});
  final Game game;

  @override
  ConsumerState<GamePersonalPills> createState() => _GamePersonalPillsState();
}

class _GamePersonalPillsState extends ConsumerState<GamePersonalPills> {
  /// RomM's status values and how they read.
  static Map<String, String> get statuses => {
    'never_playing': tr('Never played'),
    'incomplete': tr('Incomplete'),
    'finished': tr('Finished'),
    'completed_100': tr('100 % completed'),
    'retired': tr('Dropped'),
  };

  late String? _status = widget.game.status;
  late int _rating = widget.game.userRating;
  late int _completion = widget.game.completion;
  late bool _backlog = widget.game.backlogged;
  late bool _nowPlaying = widget.game.nowPlaying;

  Future<void> _write({
    String? status,
    int? rating,
    int? completion,
    bool? backlogged,
    bool? nowPlaying,
    required VoidCallback undo,
  }) async {
    final engine = ref.read(playEngineProvider);
    final ok =
        engine != null &&
        await engine.setRommUser(
          widget.game,
          status: status,
          rating: rating,
          completion: completion,
          backlogged: backlogged,
          nowPlaying: nowPlaying,
        );
    if (ok) {
      // The cached game would show the old value next time the page opens.
      ref.invalidate(gameProvider(widget.game.id));
      return;
    }
    if (!mounted) return;
    setState(undo);
    showToast(context, tr('RomM didn\'t save that. It\'s as it was.'));
  }

  Future<void> _pickStatus() async {
    final keys = statuses.keys.toList();
    final labels = [
      ...statuses.values,
      _backlog ? tr('Backlog ✓') : tr('Backlog'),
      _nowPlaying ? tr('Now playing ✓') : tr('Now playing'),
    ];
    final i = await showChoice(
      context,
      title: tr('Status'),
      labels: labels,
      current: _status == null ? null : keys.indexOf(_status!),
    );
    if (i == null || !mounted) return;
    if (i < keys.length) {
      final old = _status;
      setState(() => _status = keys[i]);
      await _write(status: keys[i], undo: () => _status = old);
    } else if (i == keys.length) {
      final old = _backlog;
      setState(() => _backlog = !old);
      await _write(backlogged: !old, undo: () => _backlog = old);
    } else {
      final old = _nowPlaying;
      setState(() => _nowPlaying = !old);
      await _write(nowPlaying: !old, undo: () => _nowPlaying = old);
    }
  }

  Future<void> _pickRating() async {
    final i = await showChoice(
      context,
      title: tr('Your rating'),
      labels: [for (var r = 0; r <= 10; r++) '$r'],
      current: _rating,
    );
    if (i == null || !mounted) return;
    final old = _rating;
    setState(() => _rating = i);
    await _write(rating: i, undo: () => _rating = old);
  }

  Future<void> _pickCompletion() async {
    final i = await showChoice(
      context,
      title: tr('Completion'),
      labels: [for (var c = 0; c <= 100; c += 10) '$c %'],
      current: _completion ~/ 10,
    );
    if (i == null || !mounted) return;
    final old = _completion;
    setState(() => _completion = i * 10);
    await _write(completion: i * 10, undo: () => _completion = old);
  }

  Widget _pill(Key key, IconData icon, String text, VoidCallback onPress) => Padding(
    padding: const EdgeInsets.only(right: GSpace.s2),
    child: GFocusable(
      key: key,
      borderRadius: GRadius.pill,
      onActivate: onPress,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: GSpace.s4, vertical: GSpace.s2),
        decoration: BoxDecoration(color: GColors.surface, borderRadius: BorderRadius.circular(GRadius.pill)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: GColors.fgSecondary),
            const SizedBox(width: GSpace.s2),
            Text(
              text,
              style: const TextStyle(color: GColors.fgSecondary, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final status = statuses[_status] ?? tr('Set status');
    final extra = [if (_nowPlaying) tr('now playing'), if (_backlog) tr('backlog')];
    return Wrap(
      runSpacing: GSpace.s2,
      children: [
        _pill(
          const ValueKey('pill-status'),
          Icons.flag_outlined,
          extra.isEmpty ? status : '$status · ${extra.join(' · ')}',
          _pickStatus,
        ),
        _pill(
          const ValueKey('pill-rating'),
          Icons.star_outline,
          _rating == 0 ? tr('Rate') : '$_rating / 10',
          _pickRating,
        ),
        _pill(const ValueKey('pill-completion'), Icons.donut_large, tr('{0} % done', [_completion]), _pickCompletion),
      ],
    );
  }
}
