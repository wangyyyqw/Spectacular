import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/painting.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/epub/epub_document.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/text_layout.dart';
import 'package:reader_core/parser/block_builder.dart';
import 'package:reader_core/src/api/models.dart' show EpubNode, TextBlockNode;
import 'package:reader_core/paint/page_renderer.dart';

import '../support/corpus.dart';

/// 快照固定配置：视口、DPR、字体、字号、行高与页边距（P2-25）。
class SnapshotSpec {
  /// 创建快照配置。
  const SnapshotSpec({
    this.pageWidth = 390,
    this.pageHeight = 844,
    this.devicePixelRatio = 3,
    this.fontFamily = 'SnapshotSerif',
    this.fontSize = 18,
    this.lineHeight = 1.6,
    this.margin = 16,
  });

  /// 页面逻辑宽。
  final double pageWidth;

  /// 页面逻辑高。
  final double pageHeight;

  /// 设备像素比。
  final double devicePixelRatio;

  /// 字体族（测试里注册为 SnapshotSerif）。
  final String fontFamily;

  /// 字号。
  final double fontSize;

  /// 行高倍数。
  final double lineHeight;

  /// 正文四周页边距。
  final double margin;

  /// 正文区尺寸。
  Size get contentSize => Size(pageWidth - margin * 2, pageHeight - margin * 2);

  /// 稳定 JSON（字段顺序固定，用于基线对比）。
  Map<String, Object?> toJson() => <String, Object?>{
    'pageWidth': pageWidth,
    'pageHeight': pageHeight,
    'devicePixelRatio': devicePixelRatio,
    'fontFamily': fontFamily,
    'fontSize': fontSize,
    'lineHeight': lineHeight,
    'margin': margin,
  };

  /// 指纹。
  String get id => sha256.convert(utf8.encode(jsonEncode(toJson()))).toString();
}

/// 一页的快照记录。
class PageRecord {
  /// 创建记录。
  const PageRecord({
    required this.index,
    required this.layoutHash,
    required this.inkPixels,
    required this.lineCount,
    required this.textLength,
  });

  /// 页序号（从 0 开始）。
  final int index;

  /// 版式指纹（可见文本 + 行盒位置/宽度）。
  final String layoutHash;

  /// 墨迹像素数（非白像素，跨平台仅作参考）。
  final int inkPixels;

  /// 行数。
  final int lineCount;

  /// 可见字符数。
  final int textLength;

  /// JSON。
  Map<String, Object?> toJson() => <String, Object?>{
    'index': index,
    'layoutHash': layoutHash,
    'inkPixels': inkPixels,
    'lineCount': lineCount,
    'textLength': textLength,
  };
}

/// 整书快照：配置 + 页序列哈希。
class BookSnapshot {
  /// 创建整书快照。
  const BookSnapshot({
    required this.specId,
    required this.spec,
    required this.pages,
  });

  /// 配置指纹。
  final String specId;

  /// 配置 JSON。
  final Map<String, Object?> spec;

  /// 页记录。
  final List<PageRecord> pages;

  /// 整书哈希：配置 + 页序列（顺序敏感）。
  String get bookHash {
    // 跨平台稳定：只含版式与文本摘要，不含光栅化墨迹数（inkPixels 仅作参考）。
    final payload = jsonEncode(<String, Object?>{
      'spec': spec,
      'pages': pages
          .map(
            (page) => <String, Object?>{
              'index': page.index,
              'layoutHash': page.layoutHash,
              'lineCount': page.lineCount,
              'textLength': page.textLength,
            },
          )
          .toList(growable: false),
    });
    return sha256.convert(utf8.encode(payload)).toString();
  }

  /// JSON（写基线用）。
  Map<String, Object?> toJson() => <String, Object?>{
    'spec': spec,
    'specId': specId,
    'bookHash': bookHash,
    'pages': pages.map((page) => page.toJson()).toList(growable: false),
  };
}

/// 构造确定性的三章 EPUB（内存构建，不依赖本地样本库）。
Uint8List buildSnapshotEpub() {
  String chapter(int index) {
    final paragraphs = <String>[];
    for (var p = 0; p < 8; p++) {
      paragraphs.add(
        '<p>第${index + 1}章第${p + 1}段：山中有雾，雾里有灯。'
        '灯下有人，人读旧书。书页翻过去，风从窗外来。'
        '这是用于排版快照的固定样本段落，字句不随版本变化。</p>',
      );
    }
    return paragraphs.join('\n');
  }

  final files = <String, String>{
    'mimetype': 'application/epub+zip',
    'META-INF/container.xml':
        '<?xml version="1.0" encoding="UTF-8"?>'
        '<container version="1.0" '
        'xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
        '<rootfiles><rootfile full-path="OEBPS/content.opf" '
        'media-type="application/oebps-package+xml"/></rootfiles></container>',
    'OEBPS/content.opf':
        '<?xml version="1.0" encoding="UTF-8"?>'
        '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" '
        'unique-identifier="bookid">'
        '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
        '<dc:identifier id="bookid">urn:uuid:snapshot-0001</dc:identifier>'
        '<dc:title>快照样本</dc:title><dc:language>zh-CN</dc:language>'
        '<meta property="dcterms:modified">2026-01-01T00:00:00Z</meta>'
        '</metadata><manifest>'
        '<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" '
        'properties="nav"/>'
        '<item id="c1" href="c1.xhtml" media-type="application/xhtml+xml"/>'
        '<item id="c2" href="c2.xhtml" media-type="application/xhtml+xml"/>'
        '<item id="c3" href="c3.xhtml" media-type="application/xhtml+xml"/>'
        '</manifest><spine>'
        '<itemref idref="c1"/><itemref idref="c2"/><itemref idref="c3"/>'
        '</spine></package>',
    'OEBPS/nav.xhtml':
        '<?xml version="1.0" encoding="UTF-8"?>'
        '<html xmlns="http://www.w3.org/1999/xhtml" '
        'xmlns:epub="http://www.idpf.org/2007/ops"><head>'
        '<title>目录</title></head><body>'
        '<nav epub:type="toc"><ol>'
        '<li><a href="c1.xhtml">第一章</a></li>'
        '<li><a href="c2.xhtml">第二章</a></li>'
        '<li><a href="c3.xhtml">第三章</a></li>'
        '</ol></nav></body></html>',
    for (var i = 0; i < 3; i++)
      'OEBPS/c${i + 1}.xhtml':
          '<?xml version="1.0" encoding="UTF-8"?>'
          '<html xmlns="http://www.w3.org/1999/xhtml"><head>'
          '<title>第${i + 1}章</title></head><body>'
          '${chapter(i)}'
          '</body></html>',
  };
  return buildZip(files);
}

/// 按快照配置分页整书，返回所有页。
Future<List<PageContent>> paginateSnapshot(
  Uint8List epubBytes,
  SnapshotSpec spec,
) async {
  final opened = await openEpub(epubBytes);
  final document = opened.document;
  if (document == null) {
    throw StateError('快照样本打不开：${opened.report.message}');
  }
  final style = ComputedStyle(<String, String>{
    'font-size': '${spec.fontSize}px',
    'line-height': '${spec.lineHeight}',
    'font-family': spec.fontFamily,
    'color': '#000000',
    'text-align': 'start',
  });
  final pages = <PageContent>[];
  for (var spine = 0; spine < document.spine.length; spine++) {
    final aggregated = document.aggregateText(spine);
    final blocks = <PageBlock>[];
    void collect(EpubNode epubNode) {
      if (epubNode is TextBlockNode) {
        final text = epubNode.text;
        if (text.trim().isEmpty) {
          return;
        }
        final layout = TextLayoutEngine.layout(
          text: text,
          style: style,
          maxWidth: spec.contentSize.width,
        );
        if (layout.lineCount > 0) {
          blocks.add(
            PageBlock.styled(
              layout: layout,
              style: style,
              containingWidth: spec.contentSize.width,
            ),
          );
        }
      } else if (epubNode is BlockNode) {
        for (final child in epubNode.children) {
          collect(child);
        }
      } else if (epubNode is InlineNode) {
        for (final child in epubNode.children) {
          collect(child);
        }
      }
    }

    collect(aggregated.root);
    pages.addAll(
      Paginator(pageHeight: spec.contentSize.height)
          .measureChapter(blocks: blocks, spineIndex: spine)
          .pages,
    );
  }
  return pages;
}

/// 单页版式指纹：可见文本 + 行盒（起点/宽度/偏移）四舍五入到 0.01。
String pageLayoutHash(PageContent page) {
  final buffer = StringBuffer();
  for (final slice in page.slices) {
    for (var i = slice.startLine; i < slice.endLine; i++) {
      final line = slice.block.layout.lines[i];
      final text = slice.block.layout.text.substring(line.start, line.end);
      buffer
        ..write(text)
        ..write('|')
        ..write((line.width * 100).round())
        ..write('|')
        ..write((line.offsetX * 100).round())
        ..write('|')
        ..write((line.height * 100).round())
        ..write('\n');
    }
  }
  return sha256.convert(utf8.encode(buffer.toString())).toString();
}

/// 渲染单页并统计墨迹像素数。
Future<int> renderInkPixels(PageContent page, SnapshotSpec spec) async {
  final pixelWidth = (spec.pageWidth * spec.devicePixelRatio).round();
  final pixelHeight = (spec.pageHeight * spec.devicePixelRatio).round();
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.scale(spec.devicePixelRatio);
  canvas.translate(spec.margin, spec.margin);
  const PagePainter().paint(canvas, page, pageSize: spec.contentSize);
  final image = await recorder.endRecording().toImage(pixelWidth, pixelHeight);
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  if (data == null) {
    return 0;
  }
  var ink = 0;
  for (var i = 0; i < data.lengthInBytes; i += 4) {
    // 未绘制的像素为透明（画布起点），白底页边距为纯白，都算空白。
    final r = data.getUint8(i);
    final g = data.getUint8(i + 1);
    final b = data.getUint8(i + 2);
    final a = data.getUint8(i + 3);
    if (a > 0 && (r < 250 || g < 250 || b < 250)) {
      ink += 1;
    }
  }
  return ink;
}

/// 生成整书快照。
Future<BookSnapshot> snapshotBook(
  Uint8List epubBytes,
  SnapshotSpec spec,
) async {
  final pages = await paginateSnapshot(epubBytes, spec);
  final records = <PageRecord>[];
  for (var i = 0; i < pages.length; i++) {
    final page = pages[i];
    final textLength = pageVisibleText(page).length;
    records.add(
      PageRecord(
        index: i,
        layoutHash: pageLayoutHash(page),
        inkPixels: await renderInkPixels(page, spec),
        lineCount: page.slices.fold<int>(
          0,
          (sum, slice) => sum + (slice.endLine - slice.startLine),
        ),
        textLength: textLength,
      ),
    );
  }
  return BookSnapshot(specId: spec.id, spec: spec.toJson(), pages: records);
}

/// 一页的可见文本（按阅读顺序）。
String pageVisibleText(PageContent page) {
  final buffer = StringBuffer();
  for (final slice in page.slices) {
    for (var i = slice.startLine; i < slice.endLine; i++) {
      final line = slice.block.layout.lines[i];
      buffer.write(slice.block.layout.text.substring(line.start, line.end));
    }
  }
  return buffer.toString();
}
