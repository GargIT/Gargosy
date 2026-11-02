import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/app_preferences.dart';
import '../../profiles/profile_providers.dart';

/// Settings → Display → Text size (#240): app-wide, for a TV across the
/// room. Every text grows by it through `MediaQuery`'s text scaler; the
/// layout around it doesn't.
class TextSize {
  static const prefKey = 'ui.textSize';
  static const choices = [100, 125, 150];
  static const fallback = 100;

  static int of(AppPreferences prefs) {
    final n = int.tryParse(prefs.getString(prefKey) ?? '');
    return n != null && choices.contains(n) ? n : fallback;
  }
}

/// The text size in percent; 100 without preferences (a test's frame).
final textSizeProvider = Provider<int>((ref) {
  final prefs = watchAppPreferencesOrNull(ref);
  return prefs == null ? TextSize.fallback : TextSize.of(prefs);
});

/// [height] of text as tall as the text size makes it: for a box sized
/// around its text, so it grows with it instead of clipping.
double scaledText(BuildContext context, double height) => MediaQuery.textScalerOf(context).scale(height);

/// [child] with every text at [percent] of its size, on top of Windows'
/// own text size (Accessibility → Text size).
class ScaledText extends StatelessWidget {
  const ScaledText({super.key, required this.percent, required this.child});

  final int percent;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (percent == 100) return child;
    return MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(MediaQuery.textScalerOf(context).scale(1) * percent / 100)),
      child: child,
    );
  }
}
