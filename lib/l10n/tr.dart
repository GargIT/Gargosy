import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import '../core/storage/app_preferences.dart';
import '../profiles/profile_providers.dart';
import 'da.dart';
import 'de.dart';
import 'nb.dart';
import 'nl.dart';
import 'sv.dart';

import 'package:intl/number_symbols_data.dart' show numberFormatSymbols;

import 'dart:ui' show PlatformDispatcher;

/// Gargosy's languages (#191). The English text in the code is the key:
/// [tr] looks it up in the chosen language's table, and English is itself.
enum AppLanguage {
  system('System (Windows\' language)', locale: 'en_US'),
  en('English', locale: 'en_US'),
  sv('Svenska', locale: 'sv_SE', table: svText),
  de('Deutsch', locale: 'de_DE', table: deText, letters: ('ü', 'ö', 'ä'), extraLetter: 'ß'),
  nl('Nederlands', locale: 'nl_NL', table: nlText, letters: ('é', 'ë', 'ï')),
  // Windows says nb, no, or nn for Nynorsk, which gets bokmål.
  nb('Norsk bokmål', locale: 'nb_NO', table: nbText, codes: ['no', 'nn'], letters: ('å', 'ø', 'æ')),
  da('Dansk', locale: 'da_DK', table: daText, letters: ('å', 'æ', 'ø'));

  const AppLanguage(
    this._label, {
    required this.locale,
    this.table,
    this.codes = const [],
    this.letters = ('å', 'ö', 'ä'),
    this.extraLetter,
  });
  final String _label;

  /// Dates and numbers in this language (`intl`'s locale).
  final String locale;

  /// Its text by the English (#191, #239); null for English itself.
  final Map<String, String>? table;

  /// Windows' language codes that mean this one besides its [name].
  final List<String> codes;

  /// The on-screen keyboard's three letter keys beyond a–z (after p, and
  /// after l), where this language's own keyboard has them.
  final (String, String, String) letters;

  /// One more letter, at the end of the symbols (German ß).
  final String? extraLetter;

  /// The name in the menu: a language's own name, System in the shown one.
  String get label => this == system ? tr(_label) : _label;

  /// App-wide pref (`settings.json`): the profile picker comes before a profile.
  static const prefKey = 'ui.language';

  static AppLanguage of(AppPreferences prefs) =>
      AppLanguage.values.where((l) => l.name == prefs.getString(prefKey)).firstOrNull ?? system;

  /// The language shown: System is Windows' when Gargosy has it, else English.
  AppLanguage resolve(String systemLanguageCode) {
    if (this != system) return this;
    bool means(AppLanguage l) => l.name == systemLanguageCode || l.codes.contains(systemLanguageCode);
    return AppLanguage.values.where((l) => l != system && means(l)).firstOrNull ?? en;
  }
}

var _shown = AppLanguage.en;

/// The language [tr] shows now.
AppLanguage get shownLanguage => _shown;

/// Shows [language] from the next build on; dates and numbers follow it.
Future<void> showLanguage(AppLanguage language) async {
  _shown = language == AppLanguage.system ? AppLanguage.en : language;
  final locale = _shown.locale;
  await initializeDateFormatting(locale);
  Intl.defaultLocale = locale;
}

/// [english] in the shown language, with `{0}`, `{1}` … filled from [args]
/// (`{{` and `}}` are braces). Text without a translation stays English.
String tr(String english, [List<Object?> args = const []]) {
  final text = _shown.table?[english] ?? english;
  return fillPlaceholders(text, args);
}

/// [text] with `{n}` replaced by `args[n]`.
String fillPlaceholders(String text, List<Object?> args) {
  if (!text.contains('{') && !text.contains('}')) return text;
  final b = StringBuffer();
  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    final next = i + 1 < text.length ? text[i + 1] : '';
    if ((c == '{' && next == '{') || (c == '}' && next == '}')) {
      b.write(c);
      i++;
    } else if (c == '{') {
      final end = text.indexOf('}', i);
      final n = end < 0 ? null : int.tryParse(text.substring(i + 1, end));
      if (n != null && n < args.length) {
        b.write(args[n]);
        i = end;
      } else {
        b.write(c);
      }
    } else {
      b.write(c);
    }
  }
  return b.toString();
}

/// [value] with [digits] decimals, the shown language's decimal mark.
String decimal(num value, int digits) {
  final s = value.toStringAsFixed(digits);
  // intl names its symbols by language (`sv`), some by locale.
  final symbols = numberFormatSymbols[_shown.locale] ?? numberFormatSymbols[_shown.locale.split('_').first];
  final mark = symbols?.DECIMAL_SEP ?? '.';
  return mark == '.' ? s : s.replaceAll('.', mark);
}

/// Windows' display language as a code (`sv`, `de`), what System follows:
/// the same at start and when System is picked again.
String windowsLanguageCode() => PlatformDispatcher.instance.locale.languageCode.toLowerCase();

/// The language chosen in Settings → Display.
final languageProvider = Provider<AppLanguage>((ref) => AppLanguage.of(ref.watch(appPreferencesProvider)));

/// Saves [language], shows it, and builds every widget again with it.
Future<void> changeLanguage(WidgetRef ref, AppLanguage language) async {
  await ref.read(appPreferencesProvider).setString(AppLanguage.prefKey, language.name);
  ref.invalidate(languageProvider);
  await showLanguage(language.resolve(windowsLanguageCode()));
  void rebuild(Element e) {
    e.markNeedsBuild();
    e.visitChildren(rebuild);
  }

  WidgetsBinding.instance.rootElement?.visitChildren(rebuild);
}
