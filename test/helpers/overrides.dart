import 'package:flutter_riverpod/misc.dart';

/// [all] with only the last override of each provider: a test's own come
/// after a helper's defaults and replace them (Riverpod 3 refuses a
/// provider overridden twice in one container).
List<Override> lastWins(Iterable<Override> all) {
  final seen = <Object>{};
  final kept = <Override>[];
  for (final o in all.toList().reversed) {
    // ignore: invalid_use_of_visible_for_testing_member
    if (seen.add(o.origin)) kept.add(o);
  }
  return kept.reversed.toList();
}
