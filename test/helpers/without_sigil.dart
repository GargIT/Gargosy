import 'package:gargosy/core/save/save_strategy.dart';

/// For `SaveSyncService(wrapSaves:)` in tests of the strategies sigil wraps,
/// checked on their own: every emulator keeps its own strategy. The app
/// always passes `sigilSavesFor` (#57).
SaveStrategy? withoutSigil(String emulatorId, SaveStrategy? base) => base;
