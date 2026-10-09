import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/romm/romm_library_api.dart';
import '../core/romm/romm_models.dart';
import '../core/storage/app_preferences.dart';

/// The Platforms page's Covers setting: which five games each card fans.
enum PlatformCovers {
  topRated('Top rated'),
  random('Random'),
  recentlyAdded('Recently added'),
  lastPlayed('Last played'),

  /// No covers: the platform's logo, large.
  logoOnly('Logo only');

  const PlatformCovers(this.label);
  final String label;
}

const _count = 5;
const _randomPage = 40;

/// The games [p]'s card shows for [choice], at most five.
Future<List<Game>> coversFor(LibraryApi api, Platform p, PlatformCovers choice, Random rng) async {
  Future<List<Game>> sorted(GallerySort sort) async =>
      (await api.page(GalleryQuery(platformId: p.id, sort: sort, descending: true), limit: _count)).games;
  switch (choice) {
    case PlatformCovers.logoOnly:
      return const [];
    case PlatformCovers.topRated:
      return sorted(GallerySort.rating);
    case PlatformCovers.recentlyAdded:
      return sorted(GallerySort.recentlyAdded);
    case PlatformCovers.random:
      // A page somewhere in the platform, five picked from it: one request.
      final offset = p.gamesCount > _randomPage ? rng.nextInt(p.gamesCount - _randomPage + 1) : 0;
      final page = (await api.page(GalleryQuery(platformId: p.id), offset: offset, limit: _randomPage)).games.toList()
        ..shuffle(rng);
      return page.take(_count).toList();
    case PlatformCovers.lastPlayed:
      final played = (await api.page(
        GalleryQuery(platformId: p.id, sort: GallerySort.lastPlayed, descending: true, lastPlayedOnly: true),
        limit: _count,
      ))
          .games;
      if (played.length >= _count) return played;
      final ids = {for (final g in played) g.id};
      return [...played, ...(await sorted(GallerySort.rating)).where((g) => !ids.contains(g.id))].take(_count).toList();
  }
}

/// The Covers setting, kept in the profile's preferences.
class PlatformCoversChoice extends StateNotifier<PlatformCovers> {
  PlatformCoversChoice(this._prefs) : super(_read(_prefs));

  static const key = 'platforms.covers';
  final AppPreferences? _prefs;

  static PlatformCovers _read(AppPreferences? prefs) =>
      PlatformCovers.values.where((c) => c.name == prefs?.getString(key)).firstOrNull ?? PlatformCovers.topRated;

  Future<void> pick(PlatformCovers choice) async {
    state = choice;
    await _prefs?.setString(key, choice.name);
  }
}

/// A card's covers in the session cache: one platform, one choice
/// ([Platform] has no `==`, so it's compared by id).
class PlatformCoversKey {
  const PlatformCoversKey(this.platform, this.choice);
  final Platform platform;
  final PlatformCovers choice;

  @override
  bool operator ==(Object other) =>
      other is PlatformCoversKey && other.platform.id == platform.id && other.choice == choice;

  @override
  int get hashCode => Object.hash(platform.id, choice);
}
