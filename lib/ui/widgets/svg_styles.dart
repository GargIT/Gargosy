/// [svg] with its `<style>` block's class rules written onto the shapes as
/// `style="..."`. RomM's platform icons (Illustrator exports) keep their
/// colours in CSS classes, which flutter_svg doesn't read: without this every
/// shape is drawn black. Only `.class` selectors are handled, which is all
/// those icons use; a shape's own `style` still wins, as in a browser.
String inlineSvgStyles(String svg) {
  final styleBlock = RegExp(r'<style[^>]*>(.*?)</style>', dotAll: true);
  final blocks = styleBlock.allMatches(svg).toList();
  if (blocks.isEmpty) return svg;

  // Class → its declarations, in the order the rules come.
  final rules = <String, Map<String, String>>{};
  for (final block in blocks) {
    final css = block.group(1)!.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
    for (final rule in RegExp(r'([^{}]+)\{([^}]*)\}').allMatches(css)) {
      final decls = <String, String>{};
      for (final d in rule.group(2)!.split(';')) {
        final colon = d.indexOf(':');
        if (colon > 0) decls[d.substring(0, colon).trim()] = d.substring(colon + 1).trim();
      }
      for (final selector in rule.group(1)!.split(',')) {
        final s = selector.trim();
        if (RegExp(r'^\.[\w-]+$').hasMatch(s)) (rules[s.substring(1)] ??= {}).addAll(decls);
      }
    }
  }

  final withoutStyle = svg.replaceAll(styleBlock, '');
  return withoutStyle.replaceAllMapped(RegExp(r'<([A-Za-z][\w:.-]*)(\s[^<>]*?)(/?)>'), (m) {
    var attrs = m.group(2)!;
    final cls = RegExp(r'\sclass="([^"]*)"').firstMatch(attrs);
    if (cls == null) return m.group(0)!;
    final merged = <String, String>{};
    for (final name in cls.group(1)!.split(RegExp(r'\s+'))) {
      merged.addAll(rules[name] ?? const {});
    }
    final own = RegExp(r'\sstyle="([^"]*)"').firstMatch(attrs);
    if (own != null) {
      for (final d in own.group(1)!.split(';')) {
        final colon = d.indexOf(':');
        if (colon > 0) merged[d.substring(0, colon).trim()] = d.substring(colon + 1).trim();
      }
      attrs = attrs.replaceFirst(own.group(0)!, '');
    }
    if (merged.isEmpty) return m.group(0)!;
    final style = merged.entries.map((e) => '${e.key}:${e.value}').join(';');
    return '<${m.group(1)}${attrs.trimRight()} style="$style"${m.group(3)}>';
  });
}
