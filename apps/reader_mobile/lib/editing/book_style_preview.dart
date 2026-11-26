import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:reader_core/editing/editable_document.dart';
import 'package:reader_core/epub/epub_chapter_source.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/paint/page_renderer.dart';

import 'book_style_presets.dart';

/// 内存样书复用正式 EPUB 排版与绘制，示例预览不修改编辑会话。
class BookStylePreview extends StatefulWidget {
  const BookStylePreview({super.key, required this.preset});
  final BookStylePreset preset;

  @override
  State<BookStylePreview> createState() => _BookStylePreviewState();
}

class _BookStylePreviewState extends State<BookStylePreview> {
  late Future<PageContent> _page = _layout();

  Future<PageContent> _layout() async {
    final source = await EpubChapterSource.open(
      _sampleBook(widget.preset),
      contentWidth: 360,
      contentHeight: 180,
    );
    try {
      return (await source.loadChapter(0)).first;
    } finally {
      source.close();
    }
  }

  @override
  void didUpdateWidget(covariant BookStylePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.preset != widget.preset) _page = _layout();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: '${widget.preset.name}样式示例：${widget.preset.sample}',
    child: SizedBox(
      height: 212,
      child: ColoredBox(
        color: Colors.white,
        child: FutureBuilder<PageContent>(
          key: ValueKey(widget.preset.id),
          future: _page,
          builder: (_, snapshot) {
            if (snapshot.hasError) {
              return const Center(
                child: Text(
                  '示例暂不可用，可查看下方 CSS',
                  style: TextStyle(color: Colors.black),
                ),
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            return FittedBox(
              fit: BoxFit.scaleDown,
              child: SizedBox(
                width: 392,
                height: 212,
                child: CustomPaint(painter: _SamplePainter(snapshot.data!)),
              ),
            );
          },
        ),
      ),
    ),
  );
}

class _SamplePainter extends CustomPainter {
  const _SamplePainter(this.page);
  final PageContent page;

  @override
  void paint(Canvas canvas, Size size) => const PagePainter().paint(
    canvas,
    page,
    pageSize: size,
    pageInsets: const EdgeInsets.all(16),
  );

  @override
  bool shouldRepaint(_SamplePainter oldDelegate) => oldDelegate.page != page;
}

Uint8List _sampleBook(BookStylePreset preset) {
  final entries = {
    'mimetype': 'application/epub+zip',
    'META-INF/container.xml': '<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="book.opf" media-type="application/oebps-package+xml"/></rootfiles></container>',
    'book.opf': '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="id">style-sample</dc:identifier><dc:title>样式示例</dc:title><dc:language>zh-CN</dc:language></metadata><manifest><item id="sample" href="sample.xhtml" media-type="application/xhtml+xml"/></manifest><spine><itemref idref="sample"/></spine></package>',
    'sample.xhtml':
        '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>样式示例</title><style>body { margin: 0; font-size: 16px; } p { ${preset.css} }</style></head><body><p>${escapeXmlText(preset.sample)}</p></body></html>',
  };
  final archive = Archive();
  for (final entry in entries.entries) {
    final bytes = utf8.encode(entry.value);
    archive.addFile(ArchiveFile(entry.key, bytes.length, bytes));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}
