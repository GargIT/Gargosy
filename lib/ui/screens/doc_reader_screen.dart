import 'dart:async';
import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/input/gamepad_service.dart';
import '../../core/input/input_action_bus.dart';
import '../../providers/about_providers.dart';
import '../input/gargosy_intents.dart';
import '../shell/backdrop.dart';
import '../theme/tokens.dart';
import '../widgets/controller_dialogs.dart';
import '../widgets/hint_bar.dart';

/// Opens the document at [path] (a file in the Gargosy folder) in the reader.
Future<void> openDoc(BuildContext context, String path) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => DocReaderScreen(path: path)));

/// The links in Markdown [text], inline (`[label](href)`) and reference
/// style (`[label]: href`), in the order they appear; images left out.
List<({String label, String href})> markdownLinks(String text) {
  final links = <({String label, String href})>[];
  final seen = <String>{};
  final pattern = RegExp(r'(!?)\[([^\]]+)\]\(([^)\s]+)[^)]*\)|^\[([^\]]+)\]:\s*(\S+)', multiLine: true);
  for (final m in pattern.allMatches(text)) {
    if (m.group(1) == '!') continue;
    final label = (m.group(2) ?? m.group(4)!).replaceAll('`', '');
    final href = m.group(3) ?? m.group(5)!;
    if (href.startsWith('#') || !seen.add(href)) continue;
    links.add((label: label, href: href));
  }
  return links;
}

/// A document from the Gargosy folder: Markdown styled like the rest of the
/// app, anything else (LICENSE, `.txt`) as plain text. D-pad / arrows
/// scroll, LB/RB a page, X lists the links (a controller can't reach them
/// in the text), B goes back. A link to another file opens it here; a web
/// link or a folder opens outside.
class DocReaderScreen extends ConsumerStatefulWidget {
  const DocReaderScreen({super.key, required String this.path}) : text = null, title = null, baseDir = null;

  /// Markdown [text] that isn't a file (What's new, issue #3), under
  /// [title]; its links and images resolve against [baseDir], the Gargosy
  /// folder.
  const DocReaderScreen.text({
    super.key,
    required String this.title,
    required String this.text,
    required String this.baseDir,
  }) : path = null;

  final String? path;
  final String? text;
  final String? title;
  final String? baseDir;

  /// The folder links resolve against.
  String get dir => baseDir ?? p.dirname(path!);

  @override
  ConsumerState<DocReaderScreen> createState() => _DocReaderScreenState();
}

class _DocReaderScreenState extends ConsumerState<DocReaderScreen> {
  static const _step = 120.0;
  final _scroll = ScrollController();

  /// Read once, in one go: these are documents of a few KB.
  late final String? _text = _read();
  StreamSubscription<GameAction>? _pad;

  String? _read() {
    if (widget.text != null) return widget.text;
    try {
      return io.File(widget.path!).readAsStringSync();
    } on io.FileSystemException {
      return null;
    }
  }

  bool get _markdown => widget.text != null || p.extension(widget.path!).toLowerCase() == '.md';

  @override
  void initState() {
    super.initState();
    _pad = inputActionBus.stream.listen((a) {
      if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
      if (a == GameAction.down) _scrollBy(_step);
      if (a == GameAction.up) _scrollBy(-_step);
    });
  }

  @override
  void dispose() {
    _pad?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollBy(double delta) {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    final to = (pos.pixels + delta).clamp(pos.minScrollExtent, pos.maxScrollExtent);
    _scroll.animateTo(to, duration: GMotion.fast, curve: GMotion.easeOut);
  }

  double get _page => _scroll.hasClients ? _scroll.position.viewportDimension * 0.9 : 600;

  /// Web links and folders open outside; files open in the reader.
  void _openLink(String href) {
    final uri = Uri.tryParse(href);
    if (uri != null && uri.hasScheme) {
      ref.read(externalOpenerProvider)(href);
      return;
    }
    final file = href.split('#').first;
    if (file.isEmpty) return;
    final target = p.normalize(p.join(widget.dir, Uri.decodeComponent(file)));
    if (io.Directory(target).existsSync()) {
      ref.read(externalOpenerProvider)(target);
    } else {
      openDoc(context, target);
    }
  }

  Future<void> _showLinks(String text) async {
    final links = markdownLinks(text);
    if (links.isEmpty) return;
    final i = await showChoice(context, title: 'Links', labels: [for (final l in links) l.label]);
    if (i != null && mounted) _openLink(links[i].href);
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    if (e.logicalKey == LogicalKeyboardKey.arrowDown) {
      _scrollBy(_step);
    } else if (e.logicalKey == LogicalKeyboardKey.arrowUp) {
      _scrollBy(-_step);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  Widget _image(Uri uri, String? title, String? alt) {
    if (uri.hasScheme) return const SizedBox.shrink();
    final file = io.File(p.join(widget.dir, Uri.decodeComponent(uri.path)));
    // The release leaves the README's screenshots out: no broken-image box.
    if (!file.existsSync()) return const SizedBox.shrink();
    return Image.file(file);
  }

  Widget _body(String text) {
    if (!_markdown) {
      return SelectableText(
        text,
        style: const TextStyle(fontFamily: 'Consolas', fontSize: GFont.md, height: 1.45, color: GColors.fgSecondary),
      );
    }
    return MarkdownBody(
      data: text,
      styleSheet: docStyleSheet(Theme.of(context)),
      onTapLink: (_, href, _) {
        if (href != null) _openLink(href);
      },
      imageBuilder: _image,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Backdrop(
        child: Builder(
          builder: (context) {
            final text = _text;
            final hasLinks = text != null && _markdown && markdownLinks(text).isNotEmpty;
            return Actions(
              actions: {
                PrevTabIntent: CallbackAction<PrevTabIntent>(onInvoke: (_) => _scrollBy(-_page)),
                NextTabIntent: CallbackAction<NextTabIntent>(onInvoke: (_) => _scrollBy(_page)),
                DetailIntent: CallbackAction<DetailIntent>(onInvoke: (_) => text == null ? null : _showLinks(text)),
              },
              child: Focus(
                autofocus: true,
                onKeyEvent: _onKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(GSpace.rowPad, GSpace.s8, GSpace.rowPad, GSpace.s4),
                      child: Text(
                        widget.title ?? p.basename(widget.path!),
                        style: const TextStyle(fontSize: GFont.xxl, fontWeight: FontWeight.w800),
                      ),
                    ),
                    Expanded(
                      child: text == null
                          ? Center(
                              child: Text(
                                "${widget.title ?? p.basename(widget.path!)} isn't in the Gargosy folder.",
                                style: const TextStyle(color: GColors.fgSecondary),
                              ),
                            )
                          : Scrollbar(
                              controller: _scroll,
                              child: SingleChildScrollView(
                                controller: _scroll,
                                padding: const EdgeInsets.symmetric(horizontal: GSpace.rowPad, vertical: GSpace.s4),
                                child: Align(
                                  alignment: Alignment.topLeft,
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(maxWidth: 900),
                                    child: _body(text),
                                  ),
                                ),
                              ),
                            ),
                    ),
                    HintBar(
                      hints: [
                        const Hint(GameAction.verticalAxis, 'Scroll'),
                        const Hint(GameAction.l1, 'Page up'),
                        const Hint(GameAction.r1, 'Page down'),
                        if (hasLinks) const Hint(GameAction.detail, 'Links'),
                        const Hint(GameAction.back, 'Back'),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Markdown in Gargosy's colours and sizes.
MarkdownStyleSheet docStyleSheet(ThemeData theme) {
  const body = TextStyle(fontSize: GFont.lg, height: 1.55, color: GColors.fgSecondary);
  const code = TextStyle(
    fontFamily: 'Consolas',
    fontSize: GFont.md,
    color: GColors.fg,
    backgroundColor: GColors.surface,
  );
  return MarkdownStyleSheet.fromTheme(theme).copyWith(
    p: body,
    listBullet: body,
    tableBody: body,
    tableHead: body.copyWith(color: GColors.fg, fontWeight: FontWeight.w700),
    h1: const TextStyle(fontSize: GFont.xxxl, fontWeight: FontWeight.w800, color: GColors.fg),
    h2: const TextStyle(fontSize: GFont.xxl, fontWeight: FontWeight.w700, color: GColors.fg),
    h3: const TextStyle(fontSize: GFont.xl, fontWeight: FontWeight.w700, color: GColors.fg),
    h4: const TextStyle(fontSize: GFont.lg, fontWeight: FontWeight.w700, color: GColors.fg),
    h1Padding: const EdgeInsets.only(top: GSpace.s4, bottom: GSpace.s2),
    h2Padding: const EdgeInsets.only(top: GSpace.s6, bottom: GSpace.s2),
    h3Padding: const EdgeInsets.only(top: GSpace.s4, bottom: GSpace.s1),
    a: const TextStyle(color: GColors.primaryHover),
    code: code,
    codeblockPadding: const EdgeInsets.all(GSpace.s3),
    codeblockDecoration: BoxDecoration(color: GColors.surface, borderRadius: BorderRadius.circular(GRadius.md)),
    blockquoteDecoration: const BoxDecoration(
      border: Border(left: BorderSide(color: GColors.borderStrong, width: 3)),
    ),
    blockquotePadding: const EdgeInsets.only(left: GSpace.s4),
    horizontalRuleDecoration: const BoxDecoration(
      border: Border(top: BorderSide(color: GColors.borderStrong)),
    ),
    tableBorder: TableBorder.all(color: GColors.borderStrong),
    blockSpacing: GSpace.s3,
  );
}
