import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/ui/widgets/svg_styles.dart';

/// Shaped like RomM's platform icons (Illustrator exports): colours in a
/// <style> block, shapes by class.
const _icon = '''<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">
  <defs>
    <style>
      .cls-1 {
        fill: #adc3e5;
      }

      .cls-4, .cls-5 {
        fill: none;
        stroke-width: 4px;
      }

      .cls-4 {
        stroke: #eb9cc4;
      }
    </style>
  </defs>
  <rect class="cls-1" width="5" height="5"/>
  <path class="cls-4" d="M0 0L10 10"/>
  <circle class="cls-5 cls-1" cx="5" cy="5" r="2"/>
  <ellipse class="cls-1" style="opacity:0.5" cx="5" cy="5" rx="1" ry="2"/>
  <line x1="0" y1="0" x2="1" y2="1"/>
</svg>''';

void main() {
  final out = inlineSvgStyles(_icon);

  test('the <style> block is gone', () => expect(out, isNot(contains('<style'))));

  test("each shape carries its class's rules", () {
    expect(out, contains(RegExp(r'<rect class="cls-1" width="5" height="5" style="fill:#adc3e5"\s*/>')));
  });

  test('a rule for several classes reaches each, and later rules add to earlier ones', () {
    expect(out, contains('<path class="cls-4" d="M0 0L10 10" style="fill:none;stroke-width:4px;stroke:#eb9cc4"'));
  });

  test('several classes on one shape: in order, the last one wins', () {
    expect(out, contains('style="fill:#adc3e5;stroke-width:4px"'));
  });

  test("the shape's own style still wins", () {
    expect(out, contains('style="fill:#adc3e5;opacity:0.5"'));
  });

  test('shapes without a class, and icons without <style>, are left alone', () {
    expect(out, contains('<line x1="0" y1="0" x2="1" y2="1"/>'));
    const plain = '<svg><rect fill="red"/></svg>';
    expect(inlineSvgStyles(plain), plain);
  });
}
