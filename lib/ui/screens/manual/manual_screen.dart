import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/input/gamepad_service.dart';
import '../../../core/input/input_action_bus.dart';
import '../../../core/romm/romm_models.dart';
import '../../../library/game_manual.dart';
import '../../../providers/download_providers.dart';
import '../../input/gargosy_intents.dart';
import '../../shell/backdrop.dart';
import '../../theme/tokens.dart';
import '../../widgets/hint_bar.dart';
import 'manual_document.dart';
import '../../../l10n/tr.dart';

/// Opens [game]'s manual.
Future<void> openManual(BuildContext context, Game game) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ManualScreen(game: game)));

/// #232: a game's manual, a page at a time fitted to the screen. LB/RB (Page
/// Up/Down) and, while it fits, D-pad left/right turn the page; A zooms in
/// (after the last step, back to the whole page), X fits it again, the D-pad
/// pans a zoomed page; B goes back. The mouse wheel zooms and a drag pans;
/// + and − zoom, Home and End go to the first and last page.
class ManualScreen extends ConsumerStatefulWidget {
  const ManualScreen({super.key, required this.game});

  final Game game;

  @override
  ConsumerState<ManualScreen> createState() => _ManualScreenState();
}

class _ManualScreenState extends ConsumerState<ManualScreen> {
  static const zooms = [1.0, 1.5, 2.0, 3.0];
  static const _panStep = 160.0;

  final _view = TransformationController();
  ManualDocument? _doc;
  String? _problem;
  int _page = 0;
  Size _viewport = Size.zero;
  StreamSubscription<GameAction>? _pad;

  @override
  void initState() {
    super.initState();
    _open();
    _pad = inputActionBus.stream.listen((a) {
      if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
      switch (a) {
        case GameAction.left:
          _move(-1, 0);
        case GameAction.right:
          _move(1, 0);
        case GameAction.up:
          _move(0, -1);
        case GameAction.down:
          _move(0, 1);
        default:
      }
    });
  }

  Future<void> _open() async {
    final manuals = ref.read(gameManualsProvider);
    final opener = ref.read(manualOpenerProvider);
    try {
      if (manuals == null) throw ManualUnavailable(tr('RomM has no manual for this game.'));
      final wasKept = manuals.isKept(widget.game);
      final path = await manuals.open(widget.game);
      ManualDocument doc;
      try {
        doc = await opener(path);
      } on Object catch (e) {
        if (!wasKept) rethrow;
        // A kept copy PDFium can't read: fetched again, once.
        debugPrint('[Manual] ${widget.game.id}: the kept copy doesn\'t open ($e), fetched again');
        await manuals.forget(widget.game);
        doc = await opener(await manuals.open(widget.game));
      }
      if (!mounted) {
        unawaited(doc.dispose());
        return;
      }
      if (doc.pageCount == 0) {
        unawaited(doc.dispose());
        setState(() => _problem = tr('The manual has no pages.'));
        return;
      }
      setState(() => _doc = doc);
    } on ManualUnavailable catch (e) {
      if (mounted) setState(() => _problem = e.message);
    } on Object catch (e) {
      debugPrint('[Manual] ${widget.game.id} can\'t be opened: $e');
      if (mounted) setState(() => _problem = tr('The manual can\'t be opened.'));
    }
  }

  @override
  void dispose() {
    _pad?.cancel();
    unawaited(_doc?.dispose());
    _view.dispose();
    super.dispose();
  }

  double get _scale => _view.value.getMaxScaleOnAxis();
  bool get _zoomed => _scale > 1.01;

  void _turn(int by) {
    final doc = _doc;
    if (doc == null) return;
    final to = (_page + by).clamp(0, doc.pageCount - 1);
    if (to == _page) return;
    setState(() {
      _page = to;
      _view.value = Matrix4.identity();
    });
  }

  /// The page where it sits on the screen, fitted and centred.
  Rect get _pageRect {
    final doc = _doc;
    if (doc == null || _viewport.isEmpty) return Offset.zero & _viewport;
    final page = doc.pageSize(_page);
    if (page.isEmpty) return Offset.zero & _viewport;
    final fit = applyBoxFit(BoxFit.contain, page, _viewport).destination;
    return Alignment.center.inscribe(fit, Offset.zero & _viewport);
  }

  /// A D-pad step: pans along a way the zoomed page is larger than the
  /// screen; left/right turn the page where it still fits across.
  void _move(int dx, int dy) {
    final r = _pageRect;
    final wider = _zoomed && r.width * _scale > _viewport.width + 0.5;
    final taller = _zoomed && r.height * _scale > _viewport.height + 0.5;
    if (dx != 0 && !wider) {
      _turn(dx);
    } else if ((dx != 0 && wider) || (dy != 0 && taller)) {
      _pan(-dx * _panStep, -dy * _panStep);
    }
  }

  void _pan(double dx, double dy) {
    _view.value = _clamped(Matrix4.translationValues(dx, dy, 0)..multiply(_view.value));
  }

  /// To [scale] around the middle of the screen.
  void _zoomTo(double scale) {
    if (_doc == null || _viewport.isEmpty) return;
    final c = _viewport.center(Offset.zero);
    final by = scale / _scale;
    final m = Matrix4.translationValues(c.dx, c.dy, 0)
      ..scaleByDouble(by, by, 1, 1)
      ..translateByDouble(-c.dx, -c.dy, 0, 1)
      ..multiply(_view.value);
    setState(() => _view.value = _clamped(m));
  }

  /// A: the next step in, after the last back to the whole page.
  void _zoomIn() {
    final next = zooms.firstWhere((z) => z > _scale + 0.01, orElse: () => zooms.first);
    _zoomTo(next);
  }

  void _zoomOut() {
    final prev = zooms.lastWhere((z) => z < _scale - 0.01, orElse: () => zooms.first);
    _zoomTo(prev);
  }

  /// Keeps the page on the screen: no pan past its edges, and centred
  /// along a way it still fits.
  Matrix4 _clamped(Matrix4 m) {
    final s = m.getMaxScaleOnAxis();
    if (s <= 1.0) return Matrix4.identity();
    final r = _pageRect;
    double along(double t, double lo, double hi, double view) =>
        (hi - lo) * s <= view ? view / 2 - s * (lo + hi) / 2 : t.clamp(view - s * hi, -s * lo).toDouble();
    final t = m.getTranslation();
    final x = along(t.x, r.left, r.right, _viewport.width);
    final y = along(t.y, r.top, r.bottom, _viewport.height);
    return m.clone()..setTranslationRaw(x, y, 0);
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    final key = e.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft) {
      _move(-1, 0);
    } else if (key == LogicalKeyboardKey.arrowRight) {
      _move(1, 0);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      _move(0, -1);
    } else if (key == LogicalKeyboardKey.arrowDown) {
      _move(0, 1);
    } else if (key == LogicalKeyboardKey.add ||
        key == LogicalKeyboardKey.numpadAdd ||
        key == LogicalKeyboardKey.equal) {
      _zoomTo(zooms.firstWhere((z) => z > _scale + 0.01, orElse: () => zooms.last));
    } else if (key == LogicalKeyboardKey.minus || key == LogicalKeyboardKey.numpadSubtract) {
      _zoomOut();
    } else if (key == LogicalKeyboardKey.home) {
      _turn(-_page);
    } else if (key == LogicalKeyboardKey.end) {
      _turn((_doc?.pageCount ?? 1) - 1 - _page);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  Widget _body() {
    final doc = _doc;
    if (_problem != null) {
      return Center(
        child: Text(
          _problem!,
          key: const ValueKey('manual-problem'),
          style: const TextStyle(color: GColors.fgSecondary),
        ),
      );
    }
    if (doc == null) return const Center(child: CircularProgressIndicator());
    return LayoutBuilder(
      builder: (context, box) {
        _viewport = box.biggest;
        return ClipRect(
          child: InteractiveViewer(
            // A new viewer a page: a mouse fling still running stops with the turn.
            key: ValueKey('manual-view-$_page'),
            transformationController: _view,
            minScale: 1,
            maxScale: zooms.last,
            onInteractionEnd: (_) => setState(() {}),
            child: SizedBox.fromSize(
              size: box.biggest,
              child: Center(
                child: KeyedSubtree(key: ValueKey('manual-page-$_page'), child: doc.page(_page)),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final doc = _doc;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Backdrop(
        child: Actions(
          actions: {
            PrevTabIntent: CallbackAction<PrevTabIntent>(onInvoke: (_) => _turn(-1)),
            NextTabIntent: CallbackAction<NextTabIntent>(onInvoke: (_) => _turn(1)),
            ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) => _zoomIn()),
            DetailIntent: CallbackAction<DetailIntent>(onInvoke: (_) => _zoomTo(1)),
          },
          child: Focus(
            autofocus: true,
            onKeyEvent: _onKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(GSpace.rowPad, GSpace.s6, GSpace.rowPad, GSpace.s3),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.game.displayName,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: GFont.xxl, fontWeight: FontWeight.w800),
                        ),
                      ),
                      if (doc != null)
                        Text(
                          tr('Page {0} of {1}', [_page + 1, doc.pageCount]),
                          key: const ValueKey('manual-page-number'),
                          style: const TextStyle(fontSize: GFont.lg, color: GColors.fgSecondary),
                        ),
                    ],
                  ),
                ),
                Expanded(child: _body()),
                HintBar(
                  hints: [
                    if (doc != null) ...[
                      Hint(GameAction.l1, tr('Previous page')),
                      Hint(GameAction.r1, tr('Next page')),
                      Hint(GameAction.confirm, tr('Zoom')),
                      if (_zoomed) ...[
                        Hint(GameAction.verticalAxis, tr('Move')),
                        Hint(GameAction.detail, tr('Whole page')),
                      ],
                    ],
                    Hint(GameAction.back, tr('Back')),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
