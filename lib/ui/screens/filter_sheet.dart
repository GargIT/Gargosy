import 'package:flutter/material.dart';

import '../../core/romm/romm_library_api.dart';
import '../theme/tokens.dart';
import '../widgets/g_focusable.dart';

/// A gallery's filters (genres, regions), from the bar's Filters button.
/// Returns the new query, or null when closed with B.
Future<GalleryQuery?> showFilterSheet(
  BuildContext context, {
  required GalleryQuery query,
  required FilterValues values,
}) => showDialog<GalleryQuery>(
  context: context,
  builder: (_) => _FilterSheet(query: query, values: values),
);

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({required this.query, required this.values});

  final GalleryQuery query;
  final FilterValues values;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late GalleryQuery _q = widget.query;

  Widget _chip(String label, bool on, VoidCallback onTap, {bool autofocus = false}) => GFocusable(
    autofocus: autofocus,
    borderRadius: GRadius.pill,
    onActivate: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: GSpace.s4, vertical: GSpace.s2),
      decoration: BoxDecoration(
        color: on ? GColors.fg : GColors.surface,
        borderRadius: BorderRadius.circular(GRadius.pill),
      ),
      child: Text(
        label,
        style: TextStyle(fontWeight: FontWeight.w600, color: on ? GColors.bg : GColors.fgSecondary),
      ),
    ),
  );

  Set<String> _toggle(Set<String> set, String v) => set.contains(v) ? ({...set}..remove(v)) : {...set, v};

  Widget _section(String title, List<Widget> chips) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: GSpace.s4),
      Text(
        title,
        style: const TextStyle(fontSize: GFont.lg, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: GSpace.s2),
      Wrap(spacing: GSpace.s2, runSpacing: GSpace.s2, children: chips),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(GSpace.s6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Filters',
                style: TextStyle(fontSize: GFont.xxl, fontWeight: FontWeight.w800),
              ),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (widget.values.genres.isNotEmpty)
                        _section('Genres', [
                          for (final g in widget.values.genres)
                            _chip(
                              g,
                              _q.genres.contains(g),
                              () => setState(() => _q = _q.copyWith(genres: _toggle(_q.genres, g))),
                              autofocus: g == widget.values.genres.first,
                            ),
                        ]),
                      if (widget.values.regions.isNotEmpty)
                        _section('Regions', [
                          for (final r in widget.values.regions)
                            _chip(
                              r,
                              _q.regions.contains(r),
                              () => setState(() => _q = _q.copyWith(regions: _toggle(_q.regions, r))),
                              autofocus: widget.values.genres.isEmpty && r == widget.values.regions.first,
                            ),
                        ]),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: GSpace.s5),
              Row(
                children: [
                  _chip(
                    'Clear filters',
                    false,
                    () => setState(() => _q = _q.copyWith(genres: const {}, regions: const {})),
                  ),
                  const Spacer(),
                  _chip(
                    'Apply',
                    true,
                    () => Navigator.of(context).pop(_q),
                    autofocus: widget.values.genres.isEmpty && widget.values.regions.isEmpty,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
