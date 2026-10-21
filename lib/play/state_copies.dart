import 'dart:io' as io;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../core/emulator/emulator_strategy.dart';
import '../core/romm/romm_models.dart';
import '../core/save/resume_service.dart';
import '../profiles/app_root.dart';
import '../profiles/json_file.dart';
import '../profiles/path_guard.dart';

/// Where Resume's copies of a state live for one session:
/// `userdata\app\temp\resume\`.
String resumeTempDir(AppRoot root) => p.join(root.appData, 'temp', 'resume');

/// The state Resume starts: a copy in [resumeTempDir] when the emulator
/// needs it changed for this PC's [romPath] ([EmulatorStrategy.stateForRom]:
/// DuckStation's disc path), else [statePath] itself. The synced file is
/// never changed, so it isn't uploaded again. Any failure starts the state
/// as it is.
Future<String> stateForThisPc(EmulatorStrategy strategy, String statePath, String romPath, AppRoot root) async {
  try {
    final changed = strategy.stateForRom(await io.File(statePath).readAsBytes(), romPath);
    if (changed == null) return statePath;
    final copy = p.join(resumeTempDir(root), p.basename(statePath));
    await writeBytesAtomic(PathGuard(root), copy, changed);
    debugPrint("[Resume] ${p.basename(statePath)}: started from a copy naming this PC's ROM");
    return copy;
  } catch (e) {
    debugPrint('[Resume] ${p.basename(statePath)}: kept as it is: $e');
    return statePath;
  }
}

/// Gargosy (#92): another player's state [entry] downloaded for a resume in
/// [strategy]. An emulator that loads a state from any path starts from a
/// copy in [resumeTempDir] (deleted after the session); one that loads a
/// slot by number gets it in the player's first free slot
/// ([ResumeService.freeSlotFor]), written through [profileGuard]: it is
/// theirs from then on. Returns the path to load; throws with why.
Future<String> copySharedState(
  ResumeService resume,
  ResumeEntry entry,
  Game game,
  String romPath,
  EmulatorStrategy strategy, {
  required AppRoot root,
  required PathGuard profileGuard,
}) async {
  final bytes = await resume.downloadShared(entry, game);
  if (strategy.loadsStateFromPath) {
    final copy = p.join(resumeTempDir(root), 'shared-${p.basename(entry.fileName)}');
    await writeBytesAtomic(PathGuard(root), copy, bytes);
    return copy;
  }
  final slot = await resume.freeSlotFor(entry, game, romPath);
  await writeBytesAtomic(profileGuard, slot, bytes);
  debugPrint("[Resume] another player's ${entry.slot.label} put in ${p.basename(slot)}");
  return slot;
}
