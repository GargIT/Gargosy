import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';

/// #232: an open manual, page by page. The seam tests fake: the reader
/// never touches PDFium itself.
abstract class ManualDocument {
  int get pageCount;

  /// Page [index] (from 0), filling the box it's given, its shape kept.
  Widget page(int index);

  /// Page [index]'s shape (any unit): where it sits once fitted.
  Size pageSize(int index);

  Future<void> dispose();
}

/// Opens the PDF at a path; tests replace it.
final manualOpenerProvider = Provider<Future<ManualDocument> Function(String path)>((ref) => PdfManual.open);

/// A manual through pdfrx (PDFium).
class PdfManual implements ManualDocument {
  PdfManual._(this._doc);

  final PdfDocument _doc;

  /// Pages are drawn twice their size in points (about 144 dpi, PDFium
  /// capped at 200), then fitted to the screen: a zoomed page stays sharp
  /// enough without a 40 MB bitmap a page.
  static const _detail = 2.0;

  static Future<ManualDocument> open(String path) async {
    await pdfrxFlutterInitialize();
    return PdfManual._(await PdfDocument.openFile(path));
  }

  @override
  int get pageCount => _doc.pages.length;

  @override
  Widget page(int index) {
    final page = _doc.pages[index];
    return FittedBox(
      child: SizedBox(
        width: page.width * _detail,
        height: page.height * _detail,
        child: PdfPageView(document: _doc, pageNumber: index + 1, maximumDpi: 200, backgroundColor: Colors.white),
      ),
    );
  }

  @override
  Size pageSize(int index) => Size(_doc.pages[index].width, _doc.pages[index].height);

  @override
  Future<void> dispose() => _doc.dispose();
}
