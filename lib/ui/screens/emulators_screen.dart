import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../emulators/emulator_installer.dart';
import '../../emulators/emulator_library.dart';
import '../../core/input/gamepad_service.dart';
import '../shell/backdrop.dart';
import '../theme/tokens.dart';
import '../widgets/g_focusable.dart';
import '../widgets/hint_bar.dart';
import '../widgets/toast.dart';

/// The emulators Gargosy owns (spec §6): import an existing install from a
/// folder, download one, or remove it.
class EmulatorsScreen extends ConsumerStatefulWidget {
  const EmulatorsScreen({super.key});

  @override
  ConsumerState<EmulatorsScreen> createState() => _EmulatorsScreenState();
}

class _EmulatorsScreenState extends ConsumerState<EmulatorsScreen> {
  /// Emulator id → what is happening to it right now ("Downloading 40 %").
  final Map<String, String> _busy = {};

  Future<void> _import(EmulatorInfo e) async {
    final lib = ref.read(emulatorLibraryProvider);
    if (lib == null) return;
    final folder = await FilePicker.getDirectoryPath(dialogTitle: 'The folder ${e.name} is installed in');
    if (folder == null || !mounted) return;
    setState(() => _busy[e.id] = 'Importing…');
    try {
      await lib.importFrom(e.id, folder);
      if (mounted) showToast(context, '${e.name} is installed.');
    } on Object catch (err) {
      if (mounted) showToast(context, "Couldn't import ${e.name}: $err");
    } finally {
      if (mounted) setState(() => _busy.remove(e.id));
      ref.invalidate(emulatorsProvider);
    }
  }

  /// Download, or Update: the newest build, unless it's the one installed.
  Future<void> _download(EmulatorInfo e) async {
    final installer = ref.read(emulatorInstallerProvider);
    if (installer == null) return;
    setState(() => _busy[e.id] = 'Looking for the newest…');
    String? error;
    var installed = false;
    try {
      final url = await installer.latestUrl(e.id);
      if (!mounted) return;
      if (url == null) {
        error = "no download was found";
      } else if (url == e.installedFrom) {
        showToast(context, '${e.name} is already the newest.');
      } else {
        await for (final pr in installer.install(e.id, url)) {
          if (!mounted) return;
          if (pr.error != null) error = pr.error;
          if (pr.status == 'done' && pr.error == null) installed = true;
          setState(() => _busy[e.id] = pr.status == 'extracting' ? 'Unpacking…' : 'Downloading ${(pr.percent * 100).round()} %');
        }
      }
    } on Object catch (err) {
      error = '$err';
    } finally {
      if (mounted) setState(() => _busy.remove(e.id));
      ref.invalidate(emulatorsProvider);
    }
    if (!mounted) return;
    if (error != null) {
      showToast(context, "Couldn't download ${e.name}: $error");
    } else if (installed) {
      showToast(context, '${e.name} is installed.');
    }
  }

  Future<void> _remove(EmulatorInfo e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Remove ${e.name}?'),
        content: const Text("The emulator's program is removed. Every profile's saves and settings for it stay."),
        actions: [
          GFocusable(
            autofocus: true,
            borderRadius: GRadius.pill,
            onActivate: () => Navigator.of(c).pop(false),
            child: const Padding(padding: EdgeInsets.all(GSpace.s3), child: Text('Keep')),
          ),
          GFocusable(
            borderRadius: GRadius.pill,
            onActivate: () => Navigator.of(c).pop(true),
            child: const Padding(padding: EdgeInsets.all(GSpace.s3), child: Text('Remove', style: TextStyle(color: GColors.danger))),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(emulatorLibraryProvider)?.remove(e.id);
    ref.invalidate(emulatorsProvider);
  }

  Widget _button(String label, VoidCallback? onPress, {bool autofocus = false}) => Padding(
        padding: const EdgeInsets.only(left: GSpace.s2),
        child: GFocusable(
          autofocus: autofocus,
          borderRadius: GRadius.pill,
          onActivate: onPress,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: GSpace.s4, vertical: GSpace.s2),
            decoration: BoxDecoration(color: GColors.surface, borderRadius: BorderRadius.circular(GRadius.pill)),
            child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ),
      );

  Widget _row(EmulatorInfo e, bool first) {
    final busy = _busy[e.id];
    final state = !e.supported
        ? 'Not supported yet'
        : (e.installedExe == null ? 'Not installed' : (e.version == null ? 'Installed' : 'Installed · ${e.version}'));
    return Container(
      margin: const EdgeInsets.only(bottom: GSpace.s2),
      padding: const EdgeInsets.symmetric(horizontal: GSpace.s4, vertical: GSpace.s3),
      decoration: BoxDecoration(color: GColors.surface, borderRadius: BorderRadius.circular(GRadius.lg)),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(e.name, style: const TextStyle(fontSize: GFont.xl, fontWeight: FontWeight.w700)),
            Text(e.exe, style: const TextStyle(fontSize: GFont.sm, color: GColors.fgMuted)),
          ]),
        ),
        Text(busy ?? state,
            style: TextStyle(color: e.installedExe != null && e.supported ? GColors.success : GColors.fgSecondary)),
        if (busy == null && e.supported) ...[
          _button('Import from folder', () => _import(e), autofocus: first),
          _button(e.installedExe == null ? 'Download' : 'Update', () => _download(e)),
          if (e.installedExe != null) _button('Remove', () => _remove(e)),
        ],
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final emulators = ref.watch(emulatorsProvider);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Backdrop(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(GSpace.rowPad, GSpace.s10, GSpace.rowPad, GSpace.s2),
            child: Text('Emulators', style: TextStyle(fontSize: GFont.xxxl, fontWeight: FontWeight.w800)),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: GSpace.rowPad),
            child: Text("Gargosy keeps its own copy of each emulator. Every profile gets its own saves and settings for it.",
                style: TextStyle(color: GColors.fgSecondary)),
          ),
          const SizedBox(height: GSpace.s4),
          Expanded(
            child: emulators.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('$e')),
              data: (list) {
                final sorted = [...list.where((e) => e.supported), ...list.where((e) => !e.supported)];
                return ListView(
                  padding: const EdgeInsets.fromLTRB(GSpace.rowPad, 0, GSpace.rowPad, GSpace.s14),
                  children: [for (var i = 0; i < sorted.length; i++) _row(sorted[i], i == 0)],
                );
              },
            ),
          ),
          const HintBar(hints: [Hint(GameAction.confirm, 'Choose'), Hint(GameAction.back, 'Back')]),
        ]),
      ),
    );
  }
}
