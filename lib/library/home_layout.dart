import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/storage/app_preferences.dart';

/// What sits at the top of Home (#139).
enum HomeTop {
  lastPlayed('Last played'),
  randomPick('Random pick'),
  nothing('Nothing');

  const HomeTop(this.label);
  final String label;
}

/// Home's small cards under the header (#139); each on or off.
enum HomeWidget {
  randomPick('Random pick', 'Y on Home picks another'),
  onThisDay('On this day', "games released on today's date"),
  library('Your library', 'games, on this PC, platforms');

  const HomeWidget(this.label, this.note);
  final String label;
  final String note;
}

/// Home's rows (#139), each on or off and in the player's order.
enum HomeRow {
  /// Who plays what on RomM now (#180); hidden while nobody does.
  playingNow('Playing now', 'who plays what on RomM'),
  continuePlaying('Continue playing', 'last played first'),
  recentlyAdded('Recently added', "RomM's newest"),
  favourites('Favourites', 'your ♥ games'),
  onThisPc('On this PC', 'first while RomM is offline'),
  platforms('Platforms', 'as on the Platforms tab'),
  collections('Collections', 'yours and shared'),
  forYou('For you', "RomM 5.4's recommendations"),
  smartCollections('Smart collections', ''),
  virtualCollections('Virtual collections', "RomM's series");

  const HomeRow(this.label, this.note);
  final String label;
  final String note;

  /// Off until the player turns it on.
  bool get offByDefault => this == forYou || this == smartCollections || this == virtualCollections;
}

/// A profile's Home: the top, the widgets that are on, and every row in its
/// order with whether it shows.
class HomeLayout {
  const HomeLayout({required this.top, required this.widgets, required this.rows});

  final HomeTop top;
  final Set<HomeWidget> widgets;
  final List<(HomeRow, bool)> rows;

  static final standard = HomeLayout(
    top: HomeTop.lastPlayed,
    widgets: HomeWidget.values.toSet(),
    rows: [for (final r in HomeRow.values) (r, !r.offByDefault)],
  );

  /// The rows that show, in order.
  List<HomeRow> get shown => [
    for (final (r, on) in rows)
      if (on) r,
  ];

  HomeLayout copyWith({HomeTop? top, Set<HomeWidget>? widgets, List<(HomeRow, bool)>? rows}) =>
      HomeLayout(top: top ?? this.top, widgets: widgets ?? this.widgets, rows: rows ?? this.rows);

  HomeLayout withWidget(HomeWidget w, bool on) => copyWith(widgets: on ? {...widgets, w} : ({...widgets}..remove(w)));

  HomeLayout withRow(HomeRow row, bool on) => copyWith(rows: [for (final (r, o) in rows) (r, r == row ? on : o)]);

  /// [row] one place up ([by] -1) or down (1); nothing past either end.
  HomeLayout moved(HomeRow row, int by) {
    final list = [...rows];
    final i = list.indexWhere((e) => e.$1 == row);
    final j = i + by;
    if (i < 0 || j < 0 || j >= list.length) return this;
    final e = list.removeAt(i);
    list.insert(j, e);
    return copyWith(rows: list);
  }

  Map<String, dynamic> toJson() => {
    'top': top.name,
    'widgets': [
      for (final w in HomeWidget.values)
        if (widgets.contains(w)) w.name,
    ],
    'rows': [
      for (final (r, on) in rows) {'row': r.name, 'on': on},
    ],
  };

  /// A saved layout; a row it doesn't know (a newer Gargosy's) is dropped,
  /// one it lacks (an older Gargosy's) is added at its place by default, on
  /// or off as by default.
  factory HomeLayout.fromJson(Map<String, dynamic> json) {
    T? byName<T extends Enum>(List<T> values, Object? name) => values.where((v) => v.name == name).firstOrNull;
    final rows = <(HomeRow, bool)>[];
    for (final e in json['rows'] is List ? json['rows'] as List : const []) {
      final r = e is Map ? byName(HomeRow.values, e['row']) : null;
      if (r != null && !rows.any((x) => x.$1 == r)) rows.add((r, e['on'] != false));
    }
    for (final (i, r) in HomeRow.values.indexed) {
      if (!rows.any((x) => x.$1 == r)) rows.insert(i < rows.length ? i : rows.length, (r, !r.offByDefault));
    }
    final widgets = json['widgets'];
    return HomeLayout(
      top: byName(HomeTop.values, json['top']) ?? HomeTop.lastPlayed,
      widgets: widgets is List ? {for (final w in widgets) ?byName(HomeWidget.values, w)} : HomeWidget.values.toSet(),
      rows: rows,
    );
  }
}

/// The profile's Home layout, in its preferences (`home.layout`).
class HomeLayoutNotifier extends StateNotifier<HomeLayout> {
  HomeLayoutNotifier(this._prefs) : super(_read(_prefs));

  static const key = 'home.layout';
  final AppPreferences? _prefs;

  static HomeLayout _read(AppPreferences? prefs) {
    final raw = prefs?.getString(key);
    if (raw == null) return HomeLayout.standard;
    try {
      final json = jsonDecode(raw);
      return json is Map<String, dynamic> ? HomeLayout.fromJson(json) : HomeLayout.standard;
    } on FormatException {
      return HomeLayout.standard;
    }
  }

  Future<void> set(HomeLayout layout) async {
    state = layout;
    await _prefs?.setString(key, jsonEncode(layout.toJson()));
  }

  /// [change] applied to the layout as it is now (two quick changes both count).
  Future<void> change(HomeLayout Function(HomeLayout) change) => set(change(state));

  Future<void> reset() async {
    state = HomeLayout.standard;
    await _prefs?.remove(key);
  }
}
