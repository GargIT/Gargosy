import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/romm/romm_library_api.dart';
import '../../providers/ui_provider.dart';
import '../input/gargosy_intents.dart';
import '../theme/tokens.dart';
import 'g_dropdown.dart';
import 'g_focusable.dart';
import 'on_screen_keyboard.dart';

/// The sorts the Sort by list offers: RomM's and the player's own, and
/// Downloaded with On this PC on.
List<GallerySort> sortsFor({required bool thisPc}) => [
  for (final s in GallerySort.values)
    if (s.group != SortGroup.thisPc || thisPc) s,
];

/// A games page's filter and sort bar (RomM v2's): the filter field, the
/// filters, On this PC, Sort by and its direction.
class GalleryBar extends StatelessWidget {
  const GalleryBar({
    super.key,
    required this.query,
    required this.onQuery,
    required this.onFilters,
    required this.thisPc,
    required this.onThisPc,
    this.thisPcCount,
    this.filterHint,
  });

  final GalleryQuery query;
  final ValueChanged<GalleryQuery> onQuery;
  final VoidCallback onFilters;
  final bool thisPc;
  final ValueChanged<bool> onThisPc;

  /// Shown on the switch while it's on.
  final int? thisPcCount;

  /// The filter field's hint; null leaves the field out (Search has its own).
  final String? filterHint;

  @override
  Widget build(BuildContext context) {
    final filters = query.genres.length + query.regions.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(GSpace.rowPad, GSpace.s4, GSpace.rowPad, 0),
      child: Wrap(
        spacing: GSpace.s3,
        runSpacing: GSpace.s3,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (filterHint != null)
            SizedBox(
              width: 320,
              child: FilterField(
                hint: filterHint!,
                text: query.search ?? '',
                onChanged: (t) => onQuery(query.copyWith(search: t.trim().isEmpty ? null : t.trim())),
              ),
            ),
          _BarButton(
            key: const ValueKey('bar-filters'),
            icon: Icons.tune,
            label: filters == 0 ? 'Filters' : 'Filters · $filters',
            on: filters > 0,
            onPress: onFilters,
          ),
          _BarButton(
            key: const ValueKey('bar-this-pc'),
            icon: thisPc ? Icons.toggle_on : Icons.toggle_off_outlined,
            label: thisPc && thisPcCount != null ? 'On this PC · $thisPcCount' : 'On this PC',
            on: thisPc,
            onPress: () => onThisPc(!thisPc),
          ),
          _SortField(query: query, thisPc: thisPc, onQuery: onQuery),
          _BarButton(
            key: const ValueKey('bar-direction'),
            icon: query.descending ? Icons.arrow_downward : Icons.arrow_upward,
            label: query.descending ? 'Descending' : 'Ascending',
            onPress: () => onQuery(query.copyWith(descending: !query.descending)),
          ),
        ],
      ),
    );
  }
}

class _SortField extends StatefulWidget {
  const _SortField({required this.query, required this.thisPc, required this.onQuery});

  final GalleryQuery query;
  final bool thisPc;
  final ValueChanged<GalleryQuery> onQuery;

  @override
  State<_SortField> createState() => _SortFieldState();
}

class _SortFieldState extends State<_SortField> {
  final _key = GlobalKey();
  bool _open = false;

  Future<void> _pick() async {
    final sorts = sortsFor(thisPc: widget.thisPc);
    final headings = <int, String>{};
    for (var i = 0; i < sorts.length; i++) {
      if (i == 0 || sorts[i].group != sorts[i - 1].group) headings[i] = sorts[i].group.label;
    }
    setState(() => _open = true);
    final i = await showDropdown(
      context,
      field: _key,
      labels: [for (final s in sorts) s.label],
      current: sorts.indexOf(widget.query.sort),
      headings: headings,
    );
    if (!mounted) return;
    setState(() => _open = false);
    if (i == null || sorts[i] == widget.query.sort) return;
    widget.onQuery(widget.query.copyWith(sort: sorts[i], descending: sorts[i].descByDefault));
  }

  @override
  Widget build(BuildContext context) => KeyedSubtree(
    key: _key,
    child: GDropdownField(
      key: const ValueKey('bar-sort'),
      icon: Icons.sort,
      text: 'Sort by ${widget.query.sort.label}',
      open: _open,
      compact: true,
      onPress: _pick,
    ),
  );
}

class _BarButton extends StatelessWidget {
  const _BarButton({super.key, required this.icon, required this.label, required this.onPress, this.on = false});

  final IconData icon;
  final String label;
  final VoidCallback onPress;
  final bool on;

  @override
  Widget build(BuildContext context) => GFocusable(
    borderRadius: GRadius.pill,
    onActivate: onPress,
    semanticLabel: label,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: GSpace.s4, vertical: GSpace.s3),
      decoration: BoxDecoration(
        color: on ? GColors.primary.withValues(alpha: 0.22) : GColors.surface,
        borderRadius: BorderRadius.circular(GRadius.pill),
        border: Border.all(color: on ? GColors.primary : GColors.borderStrong),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: on ? GColors.primaryHover : GColors.fgSecondary),
          const SizedBox(width: GSpace.s2),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    ),
  );
}

/// A filter box. With a controller, A opens the on-screen keyboard and the
/// text applies when it closes; with a mouse or keyboard it's typed in place
/// and applies [delay] after typing stops. B or Escape ends the typing.
class FilterField extends ConsumerStatefulWidget {
  const FilterField({
    super.key,
    required this.hint,
    required this.text,
    required this.onChanged,
    this.delay = const Duration(milliseconds: 400),
  });

  final String hint;
  final String text;
  final ValueChanged<String> onChanged;
  final Duration delay;

  @override
  ConsumerState<FilterField> createState() => _FilterFieldState();
}

class _FilterFieldState extends ConsumerState<FilterField> {
  final _box = FocusNode(debugLabel: 'filter-field');
  final _input = FocusNode(debugLabel: 'filter-input');
  late final _controller = TextEditingController(text: widget.text);
  bool _editing = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _input.addListener(() {
      if (!_input.hasFocus && _editing) _stop(refocus: false);
    });
  }

  @override
  void didUpdateWidget(FilterField old) {
    super.didUpdateWidget(old);
    if (!_editing && widget.text != _controller.text) _controller.text = widget.text;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _box.dispose();
    _input.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _activate() async {
    if (ref.read(inputModeProvider) == InputMode.gamepad) {
      final v = await showOnScreenKeyboard(context, title: widget.hint, initial: _controller.text);
      if (v == null || !mounted) return;
      _controller.text = v;
      _apply();
      return;
    }
    setState(() => _editing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _editing) _input.requestFocus();
    });
  }

  void _typed(String _) {
    _timer?.cancel();
    _timer = Timer(widget.delay, _apply);
  }

  void _apply() {
    _timer?.cancel();
    if (_controller.text != widget.text) widget.onChanged(_controller.text);
  }

  void _stop({bool refocus = true}) {
    _apply();
    if (!mounted) return;
    setState(() => _editing = false);
    if (refocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _box.requestFocus();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final empty = _controller.text.isEmpty;
    final content = Row(
      children: [
        const Icon(Icons.search, size: 18, color: GColors.fgMuted),
        const SizedBox(width: GSpace.s2),
        Expanded(
          child: _editing
              ? Actions(
                  actions: {BackIntent: CallbackAction<BackIntent>(onInvoke: (_) => _stop())},
                  child: TextField(
                    key: const ValueKey('filter-input'),
                    focusNode: _input,
                    controller: _controller,
                    onChanged: _typed,
                    onSubmitted: (_) => _stop(),
                    cursorColor: GColors.primary,
                    style: const TextStyle(fontSize: GFont.lg, color: GColors.fg),
                    decoration: InputDecoration.collapsed(
                      hintText: widget.hint,
                      hintStyle: const TextStyle(color: GColors.fgMuted),
                    ),
                  ),
                )
              : Text(
                  empty ? widget.hint : _controller.text,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: GFont.lg, color: empty ? GColors.fgMuted : GColors.fg),
                ),
        ),
        if (!empty && !_editing)
          GestureDetector(
            key: const ValueKey('filter-clear'),
            onTap: () {
              _controller.clear();
              _apply();
              setState(() {});
            },
            child: const Icon(Icons.close, size: 18, color: GColors.fgMuted),
          ),
      ],
    );
    final box = Container(
      padding: const EdgeInsets.symmetric(horizontal: GSpace.s4, vertical: GSpace.s3),
      decoration: BoxDecoration(
        color: GColors.bg.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(GRadius.pill),
        border: Border.all(color: _editing ? GColors.primary : GColors.borderStrong, width: 1.5),
      ),
      child: content,
    );
    if (_editing) return box;
    return GFocusable(
      key: const ValueKey('filter-field'),
      focusNode: _box,
      borderRadius: GRadius.pill,
      onActivate: _activate,
      semanticLabel: widget.hint,
      child: box,
    );
  }
}
