import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/reader/epub_chapter_source.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_ui/panels/settings_panel.dart';

/// P9 回归：CSS 长尾属性的真实管线效果。
///
/// 覆盖：sup/sub 基线位移、图片 CSS 尺寸、@import、行内图片、font 简写。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<EpubChapterSource> open({
    required String body,
    String css = '',
    String extraCss = '',
    ReaderOverrides? overrides,
  }) async {
    final source = await EpubChapterSource.open(
      _book(body: body, css: css, extraCss: extraCss),
      contentWidth: 300,
      contentHeight: 500,
      verifyCrc: false,
    );
    await source.applyOverrides(overrides ?? ReaderSettingsDefaults.overrides);
    return source;
  }

  test('vertical-align: super 写入 run 基线位移（P9-07）', () async {
    final source = await open(body: '<p>水 H<sup>2</sup>O 分子</p>');
    final pages = await source.loadChapter(0);
    final block = pages.first.slices.first.block;
    final run = block.layout.runs.firstWhere(
      (item) => item.style.verticalAlign == CssVerticalAlign.superscript,
    );
    expect(run.baselineShift, lessThan(0), reason: '上标应向上偏移');
    expect(run.baselineShift, closeTo(-0.4 * run.style.fontSize, 0.01));
  });

  test('图片 CSS 尺寸优先于默认整宽（P9-08）', () async {
    final source = await open(
      body: '<p>图前</p><p><img class="half" src="../Images/i.png"/></p>',
      css: 'img.half { width: 50%; height: 40px; }',
    );
    final pages = await source.loadChapter(0);
    final imageBlock = pages.first.slices
        .map((slice) => slice.block)
        .firstWhere((block) => block.style!.backgroundImage != null);
    expect(imageBlock.layout.height, 40);
  });

  test('@import 的样式表参与层叠（P9-10）', () async {
    final source = await open(
      body: '<p class="imp">导入样式段落</p>',
      css: '@import url("extra.css");',
      extraCss: 'p.imp { color: #ff0000; letter-spacing: 3px; }',
    );
    final pages = await source.loadChapter(0);
    final style = pages.first.slices.first.block.style!;
    expect(style.color, const Color(0xFFFF0000));
    expect(style.letterSpacing, 3);
  });

  test('行内图片透传到分页块（P9-06）', () async {
    final source = await open(
      body: '<p>文字<img class="emoji" src="../Images/i.png"/>文字</p>',
      css: 'img.emoji { height: 18px; }',
    );
    final pages = await source.loadChapter(0);
    final block = pages.first.slices.first.block;
    expect(block.inlineImages, hasLength(1));
    expect(block.inlineImages.first.url, 'OEBPS/Images/i.png');
    expect(block.inlineImages.first.height, 18);
  });

  test('font 简写在真实管线生效（P9-09）', () async {
    final source = await open(
      body: '<p class="f">简写段落</p>',
      css: 'p.f { font: italic bold 20px/2 serif; }',
      overrides: const ReaderOverrides(),
    );
    final pages = await source.loadChapter(0);
    final style = pages.first.slices.first.block.style!;
    expect(style.fontSize, 20);
    expect(style.fontWeight, 700);
    expect(style.italic, isTrue);
    expect(style.lineHeightFactor, 2);
  });
}

Uint8List _book({
  required String body,
  String css = '',
  String extraCss = '',
}) {
  final chapter =
      '<?xml version="1.0" encoding="UTF-8"?>'
      '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>t</title>'
      '${css.isEmpty ? '' : '<link rel="stylesheet" type="text/css" href="../Styles/s.css"/>'}'
      '</head><body>$body</body></html>';
  const opf = '<?xml version="1.0" encoding="UTF-8"?>'
      '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="b">'
      '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
      '<dc:identifier id="b">urn:uuid:css-gaps</dc:identifier><dc:title>t</dc:title>'
      '<dc:language>zh</dc:language>'
      '<meta property="dcterms:modified">2026-01-01T00:00:00Z</meta>'
      '</metadata><manifest>'
      '<item id="c" href="Text/c.xhtml" media-type="application/xhtml+xml"/>'
      '<item id="s" href="Styles/s.css" media-type="text/css"/>'
      '<item id="e" href="Styles/extra.css" media-type="text/css"/>'
      '<item id="i" href="Images/i.png" media-type="image/png"/>'
      '</manifest><spine><itemref idref="c"/></spine></package>';
  const container = '<?xml version="1.0" encoding="UTF-8"?>'
      '<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
      '<rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>'
      '</rootfiles></container>';
  final files = <String, List<int>>{
    'mimetype': utf8.encode('application/epub+zip'),
    'META-INF/container.xml': utf8.encode(container),
    'OEBPS/content.opf': utf8.encode(opf),
    'OEBPS/Text/c.xhtml': utf8.encode(chapter),
    'OEBPS/Styles/s.css': utf8.encode(css),
    'OEBPS/Styles/extra.css': utf8.encode(extraCss),
    // 1×1 PNG（尺寸由 intrinsic 缺失兜底，不影响断言）。
    'OEBPS/Images/i.png': <int>[
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
      0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
      0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
      0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
      0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
      0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
      0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
      0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
      0x42, 0x60, 0x82,
    ],
  };
  final archive = Archive();
  files.forEach((name, bytes) {
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  });
  return Uint8List.fromList(ZipEncoder().encodeBytes(archive));
}
