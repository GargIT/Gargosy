import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../core/storage/app_preferences.dart';

/// Search's recent terms (#132), newest first, kept in the profile's
/// preferences. A term is remembered when it's submitted (Enter, the
/// on-screen keyboard's Done) or a game is opened from its results.
class RecentSearches extends StateNotifier<List<String>> {
  RecentSearches(this._prefs) : super(_read(_prefs));

  static const key = 'search.recent';
  static const max = 8;
  final AppPreferences? _prefs;

  static List<String> _read(AppPreferences? prefs) {
    final raw = prefs?.getString(key);
    if (raw == null) return const [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return const [];
      return [
        for (final t in list)
          if (t is String && t.trim().isNotEmpty) t.trim(),
      ].take(max).toList();
    } on FormatException {
      return const [];
    }
  }

  /// [term] first; the same term in another case goes, and the oldest past [max].
  Future<void> remember(String term) async {
    final t = term.trim();
    if (t.isEmpty) return;
    final lower = t.toLowerCase();
    await _save(
      [
        t,
        for (final o in state)
          if (o.toLowerCase() != lower) o,
      ].take(max).toList(),
    );
  }

  Future<void> forget(String term) => _save([
    for (final o in state)
      if (o != term) o,
  ]);

  Future<void> _save(List<String> next) async {
    if (listEquals(next, state)) return;
    state = next;
    await _prefs?.setString(key, jsonEncode(next));
  }
}
