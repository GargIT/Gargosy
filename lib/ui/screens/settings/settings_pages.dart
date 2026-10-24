import 'package:flutter/material.dart';

/// Settings' groups, as RomM's profile page has them.
enum SettingsGroup {
  profile('PROFILE'),
  library('LIBRARY'),
  thisPc('THIS PC'),
  gargosy('GARGOSY');

  const SettingsGroup(this.heading);
  final String heading;
}

/// A section of Settings, in the sidebar's order. The user menu lists the
/// same sections (one item each) and opens Settings on the one picked.
enum SettingsPage {
  profile(SettingsGroup.profile, 'Profile', Icons.person_outline),
  retroAchievements(SettingsGroup.profile, 'RetroAchievements', Icons.emoji_events_outlined),
  home(SettingsGroup.profile, 'Home', Icons.home_outlined),
  emulators(SettingsGroup.library, 'Emulators', Icons.download_outlined),
  emulatorSettings(SettingsGroup.library, 'Emulator settings', Icons.tune),
  controller(SettingsGroup.thisPc, 'Controller', Icons.gamepad_outlined),
  display(SettingsGroup.thisPc, 'Display', Icons.desktop_windows_outlined),
  imageCache(SettingsGroup.thisPc, 'Image cache', Icons.photo_library_outlined),
  about(SettingsGroup.gargosy, 'About', Icons.info_outline);

  const SettingsPage(this.group, this.label, this.icon);
  final SettingsGroup group;
  final String label;
  final IconData icon;
}
