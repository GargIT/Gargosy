import 'package:flutter/material.dart';

import '../../../core/save/catalog/play_choice.dart';
import '../../../core/save/catalog/play_view.dart';
import '../../../core/save/catalog/save_entry.dart';
import '../../../core/save/catalog/save_maker.dart';
import '../../theme/tokens.dart';
import '../controller_dialogs.dart';
import '../g_focusable.dart';
import 'player_avatar.dart';
import 'save_row.dart';

/// Choose (the play screen: A picks the save to play) or manage (the Saves
/// tab: X puts a save on this PC, hold A deletes it; nothing launches).
enum SaveListMode { choose, manage }

/// A game's saves as RomM groups them (spec Part 2): This PC (backups folded
/// under it), then On RomM (by slot, older versions folded). Two columns
/// side by side when there's room, stacked when not. Under them, From other
/// players (#92): each player's shared saves, two players a row when there's
/// room.
class SaveList extends StatefulWidget {
  const SaveList({
    super.key,
    required this.view,
    required this.mode,
    required this.nameOf,
    this.chosen,
    this.onChoose,
    this.onRestore,
    this.onDelete,
    this.footer,
  });

  final PlayView view;
  final SaveListMode mode;
  final String Function(SaveMaker) nameOf;
  final PlayItem? chosen;
  final void Function(SavePlay save)? onChoose;
  final void Function(SaveEntry save)? onRestore;
  final void Function(SaveEntry save)? onDelete;

  /// Under the list (the narrow play screen's "N hidden · Show all").
  final Widget? footer;

  /// The list's own width from which This PC and On RomM sit side by side.
  static const twoColumnWidth = 1100.0;

  @override
  State<SaveList> createState() => _SaveListState();
}

class _SaveListState extends State<SaveList> {
  /// Folded groups that are open: `backups`, or `romm:<slot>:<tag>`.
  final _open = <String>{};

  void _toggle(String key) => setState(() => _open.contains(key) ? _open.remove(key) : _open.add(key));

  bool _isChosen(PlayRow r) => widget.chosen is SavePlay && (widget.chosen as SavePlay).entry == r.entry;

  Widget _row(PlayRow r) {
    final manage = widget.mode == SaveListMode.manage;
    final romm = r.entry.source == SaveSource.romm;
    // Another player's save is theirs: it can be copied, never deleted.
    final theirs = r.entry.owner != null;
    final movable = r.entry.source != SaveSource.local && !(romm && widget.view.rommOffline);
    // A save the emulator can't use is never put on this PC (it would go
    // into the wrong emulator); it can still be deleted.
    final restorable = movable && r.fit.usable;
    return SaveRow(
      row: r,
      nameOf: widget.nameOf,
      chosen: !manage && _isChosen(r),
      onRomm: r.entry.source == SaveSource.local && widget.view.isOnRomm(r.entry),
      showChoice: !manage,
      onActivate: manage
          ? (movable ? () => _menu(r.entry, restorable: restorable) : null)
          : (r.fit.usable ? () => widget.onChoose?.call(r.item) : null),
      onDetail: manage && restorable && widget.onRestore != null ? () => widget.onRestore!(r.entry) : null,
      onLongActivate: manage && movable && !theirs && widget.onDelete != null ? () => widget.onDelete!(r.entry) : null,
    );
  }

  /// A click in manage mode (the mouse's way to what X and hold A do).
  Future<void> _menu(SaveEntry e, {required bool restorable}) async {
    final labels = [if (restorable) 'Put on this PC', if (e.owner == null) 'Delete'];
    if (labels.isEmpty) return;
    final i = await showChoice(context, title: e.fileName, labels: labels);
    if (i == null) return;
    if (labels[i] == 'Put on this PC') widget.onRestore?.call(e);
    if (labels[i] == 'Delete') widget.onDelete?.call(e);
  }

  Widget _heading(String text, {String? note}) => Padding(
    padding: const EdgeInsets.only(top: GSpace.s3, bottom: GSpace.s2),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          text,
          style: const TextStyle(
            fontSize: GFont.sm,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            color: GColors.fgMuted,
          ),
        ),
        if (note != null)
          Text(
            note,
            style: const TextStyle(fontSize: GFont.sm, color: GColors.fgMuted),
          ),
      ],
    ),
  );

  Widget _fold(String key, int count, String what) {
    final open = _open.contains(key);
    return Padding(
      padding: const EdgeInsets.only(bottom: GSpace.s2),
      child: GFocusable(
        borderRadius: GRadius.pill,
        onActivate: () => _toggle(key),
        onDetail: () => _toggle(key),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: GSpace.s4, vertical: GSpace.s1),
          child: Text('${open ? '▾' : '▸'} $count $what', style: const TextStyle(color: GColors.fgSecondary)),
        ),
      ),
    );
  }

  List<Widget> _thisPc() {
    final v = widget.view;
    return [
      _heading('This PC', note: 'What the emulator plays from. A backup is kept before anything replaces it.'),
      if (v.thisPc.isEmpty) const Text('No save on this PC yet.', style: TextStyle(color: GColors.fgMuted)),
      ...v.thisPc.map(_row),
      if (v.backups.isNotEmpty) ...[
        _fold('backups', v.backups.length, v.backups.length == 1 ? 'backup' : 'backups'),
        if (_open.contains('backups')) ...v.backups.map(_row),
      ],
    ];
  }

  List<Widget> _romm() {
    final v = widget.view;
    return [
      _heading(
        'On RomM',
        note: v.rommOffline
            ? "RomM can't be reached, so its saves aren't listed."
            : 'A live list: nothing is downloaded until you put a save on this PC or play it.',
      ),
      if (!v.rommOffline && v.romm.isEmpty)
        const Text('No saves on RomM yet.', style: TextStyle(color: GColors.fgMuted)),
      for (final g in v.romm) ..._group('romm:${g.group.slot}:${g.group.tag}', g),
    ];
  }

  /// Rows of a RomM save group: the newest, the older ones folded under
  /// [key].
  List<Widget> _group(String key, PlayRommGroup g) => [
    _row(g.newest),
    if (g.older.isNotEmpty) ...[
      _fold(key, g.older.length, g.older.length == 1 ? 'older version' : 'older versions'),
      if (_open.contains(key)) ...g.older.map(_row),
    ],
  ];

  Widget _player(PlayPlayer p) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.only(bottom: GSpace.s2),
        child: Row(
          children: [
            PlayerAvatar(p.owner),
            const SizedBox(width: GSpace.s2),
            Text(p.owner.username, style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
      ),
      for (final g in p.groups) ..._group('player:${p.owner.userId}:${g.group.slot}:${g.group.tag}', g),
    ],
  );

  /// From other players: two players a row when [wide].
  Widget _others(bool wide) {
    final players = widget.view.others;
    return Container(
      key: const ValueKey('save-list-others'),
      margin: const EdgeInsets.only(top: GSpace.s3),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: GColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _heading(
            'From other players',
            note: widget.mode == SaveListMode.manage
                ? "X puts a copy on this PC as your save. Theirs can't be changed or deleted from here."
                : 'Saves others shared on RomM. Playing one makes a copy for you; theirs never changes.',
          ),
          if (!wide)
            for (final p in players) _player(p)
          else
            for (var i = 0; i < players.length; i += 2)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _player(players[i])),
                  const SizedBox(width: GSpace.s6),
                  Expanded(child: i + 1 < players.length ? _player(players[i + 1]) : const SizedBox.shrink()),
                ],
              ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final wide = c.maxWidth >= SaveList.twoColumnWidth;
      final pc = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _thisPc());
      final romm = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _romm());
      return SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (wide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: pc),
                  const SizedBox(width: GSpace.s6),
                  Expanded(child: romm),
                ],
              )
            else ...[
              pc,
              romm,
            ],
            if (widget.view.others.isNotEmpty) _others(wide),
            ?widget.footer,
          ],
        ),
      );
    },
  );
}
