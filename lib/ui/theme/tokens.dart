import 'package:flutter/animation.dart';

abstract final class GColors {
  static const bg = Color(0xFF07070F);
  static const bgElevated = Color(0x0BFFFFFF); // white 4.5 %
  static const surface = Color(0x12FFFFFF); // white 7 %
  static const surfaceHover = Color(0x1FFFFFFF); // white 12 %
  static const fg = Color(0xFFFFFFFF);
  static const fgSecondary = Color(0xBFFFFFFF); // 75 %
  static const fgMuted = Color(0x73FFFFFF); // 45 %
  static const fgFaint = Color(0x40FFFFFF); // 25 %
  static const border = Color(0x12FFFFFF);
  static const borderStrong = Color(0x26FFFFFF); // 15 %
  static const focus = Color(0x73FFFFFF);
  static const panel = Color(0xF7100C1C); // rgba(16,12,28,.97)
  static const card = Color(0x99141024); // a settings card: rgba(20,16,36,.6)
  static const field = Color(0x128B74E8); // a field's box: primary at 7 %
  static const primary = Color(0xFF8B74E8);
  static const primaryHover = Color(0xFFA18FFF);
  static const primaryPressed = Color(0xFF6043C8);
  static const secondary = Color(0xFF9E8CD6);
  static const accent = Color(0xFFE1A38D);
  static const fav = Color(0xFFFF4F6B);
  static const danger = Color(0xFFFF5050);
  static const dangerFill = Color(0xFFD83A3A); // a red button, white text on it
  static const success = Color(0xFF4ADE80);
  static const coverArtBase = Color(0xFF553E98);
  static const coverArtShade = Color(0xFF371F69);
  static const coverArtWarm = Color(0xFFFF9B85);

  /// Gargosy's own colours (logo).
  static const gargosyGold = Color(0xFFF2C14E);
  static const gargosyTeal = Color(0xFF3DD6C4);

  /// Badge colours a profile can pick.
  static const profileColors = [
    Color(0xFF8B74E8), // primary
    Color(0xFF3DD6C4), // teal
    Color(0xFFF2C14E), // gold
    Color(0xFFE1A38D), // peach
    Color(0xFFFF4F6B), // rose
    Color(0xFF60A5FA), // blue
  ];
}

abstract final class GSpace {
  static const double s1 = 4,
      s2 = 8,
      s3 = 12,
      s4 = 16,
      s5 = 20,
      s6 = 24,
      s7 = 28,
      s8 = 32,
      s10 = 40,
      s12 = 48,
      s14 = 56;
  static const double rowPad = 36;
}

abstract final class GRadius {
  static const double sm = 4, chip = 6, md = 8, lg = 10, card = 14, xl = 20, pill = 100;
}

abstract final class GFont {
  static const double xs = 10.5, sm = 11.5, md = 13, lg = 14.5, xl = 17, xxl = 22, xxxl = 32, xxxxl = 38;
}

abstract final class GMotion {
  static const fast = Duration(milliseconds: 150);
  static const med = Duration(milliseconds: 220);
  static const slow = Duration(milliseconds: 360);
  static const easeOut = Cubic(0.22, 1, 0.36, 1);
  static const easeInOut = Cubic(0.65, 0, 0.35, 1);
}

abstract final class GFocusRing {
  static const double mouse = 2, key = 2.5, pad = 3.5, offset = 3;
}

abstract final class GLayout {
  static const double navHeight = 58, navPillHeight = 38, touchTarget = 44;
}
