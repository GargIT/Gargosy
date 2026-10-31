import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/ui/screens/manual/manual_document.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

/// A two-page PDF, small enough to write by hand (PDFium rebuilds the
/// cross-reference table it doesn't find).
const _twoPages = '''%PDF-1.4
1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj
2 0 obj << /Type /Pages /Kids [3 0 R 4 0 R] /Count 2 >> endobj
3 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] >> endobj
4 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] >> endobj
trailer << /Root 1 0 R >>
%%EOF
''';

void main() {
  test('PDFium opens a manual and counts its pages', () async {
    final dir = await io.Directory.systemTemp.createTemp('manual');
    addTearDown(() => dir.deleteSync(recursive: true));
    // In the app, path_provider's folders are Gargosy's own (userdata\app).
    Pdfrx.cacheDirectoryPath = dir.path;
    final file = p.join(dir.path, '1.pdf');
    io.File(file).writeAsStringSync(_twoPages);
    final doc = await PdfManual.open(file);
    expect(doc.pageCount, 2);
    await doc.dispose();
  });
}
