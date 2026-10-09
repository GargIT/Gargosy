/// Marks Gargosy's per-profile folder services (lib/emulators/profile_directories.dart).
/// Copied Freegosy code checks for it where Gargosy must differ, e.g. mGBA's
/// saves live in the profile and never next to the ROM.
abstract interface class ProfileRootedDirectories {}
