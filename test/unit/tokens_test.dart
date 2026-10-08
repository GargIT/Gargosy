import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/ui/theme/gargosy_theme.dart';
import 'package:gargosy/ui/theme/tokens.dart';

void main() {
  test('v2 values', () {
    expect(GColors.bg, const Color(0xFF07070F));
    expect(GColors.primary, const Color(0xFF8B74E8));
    expect(GColors.accent, const Color(0xFFE1A38D));
    expect(GColors.fav, const Color(0xFFFF4F6B));
    expect(GColors.surface, const Color(0x12FFFFFF));
    expect(GRadius.card, 14);
    expect(GLayout.navHeight, 58);
    expect(GFocusRing.pad, 3.5);
    expect(GMotion.med, const Duration(milliseconds: 220));
  });

  test('the theme is dark, on v2 black, with the v2 primary', () {
    final t = gargosyTheme();
    expect(t.brightness, Brightness.dark);
    expect(t.scaffoldBackgroundColor, GColors.bg);
    expect(t.colorScheme.primary, GColors.primary);
  });

  test('six distinct profile colours', () {
    expect(GColors.profileColors.toSet().length, 6);
  });
}
