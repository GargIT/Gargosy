import 'package:path/path.dart' as p;

import 'folder_link.dart';
import 'profile_launch_config.dart';

/// The launch config for an emulator that only reads a folder next to its
/// exe (Eden's and Azahar's `user\`, Cemu's and melonDS's `portable\`;
/// issue #8): before each launch, and before a pull ([repoint]), that folder
/// is a link to the same folder in the profile's data, then [then] (the
/// emulator's own settings step, if any) runs. A pointer, never a swap of
/// saves: the emulator writes straight into the profile.
class LinkedFolderConfig extends ProfileLaunchConfig {
  const LinkedFolderConfig(this.folder, {this.then});

  /// The folder's name next to the exe (`user`, `portable`).
  final String folder;
  final ProfileLaunchConfig? then;

  /// Where the link goes, where it points and where a real folder in its
  /// way is kept (`userdata\templates\<emu>\<folder>`).
  ({String link, String target, String template}) pathsFor(LaunchContext c) => (
        link: p.join(c.exeDir, folder),
        target: p.join(c.data, folder),
        template: p.join(c.guard.root.templates, p.basename(c.data), folder),
      );

  /// Points the link at this profile; what it moved aside, if anything.
  FolderLinkResult point(LaunchContext c) {
    final at = pathsFor(c);
    return pointFolderLink(link: at.link, target: at.target, guard: c.guard, templateDir: at.template);
  }

  @override
  Future<List<String>> prepare(LaunchContext c) async {
    point(c);
    return then == null ? const [] : then!.prepare(c);
  }

  @override
  List<String> gameArgs(LaunchContext c, String romPath) => then?.gameArgs(c, romPath) ?? [romPath];

  @override
  Future<void> finish(LaunchContext c) async => then?.finish(c);

  @override
  void repoint(LaunchContext c) {
    point(c);
    then?.repoint(c);
  }
}
