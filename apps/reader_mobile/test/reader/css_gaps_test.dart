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

  test('background 简写生成整页背景（P9-11）', () async {
    final source = await open(
      body: '<p>正文</p>',
      css:
          'body { background: #101820 url("../Images/i.png") no-repeat '
          'center / cover; }',
    );
    final pages = await source.loadChapter(0);
    final background = pages.first.background;
    expect(background, isNotNull);
    expect(background!.imageUrl, 'OEBPS/Images/i.png');
    expect(background.repeat, CssBackgroundRepeat.noRepeat);
    expect(background.size.mode, CssBackgroundSizeMode.cover);
  });

  test('CSS 变量与 calc 在真实管线生效（P9-14/P9-15）', () async {
    final source = await open(
      body: '<p class="v">变量段落</p>',
      css:
          'body { --accent: #ff0000; } '
          'p.v { color: var(--accent); text-indent: calc(2em + 4px); }',
    );
    final pages = await source.loadChapter(0);
    final style = pages.first.slices.first.block.style!;
    expect(style.color, const Color(0xFFFF0000));
    expect(style.textIndent, closeTo(38, 0.5));
  });

  test('容器 duokan-bleed 让横幅图对齐页面边界（P9-22）', () async {
    final source = await open(
      body:
          '<div class="wrap"><img class="pic" src="../Images/i.png"/></div>'
          '<p>正文</p>',
      css:
          '.wrap { duokan-bleed: lefttopright; } '
          'img.pic { width: 100%; }',
    );
    final pages = await source.loadChapter(0);
    final imageBlock = pages.first.slices.first.block;
    expect(imageBlock.bleedLeft, isTrue);
    expect(imageBlock.bleedRight, isTrue);
    // 页面宽 300（正文宽 260 + 页边距 20*2），1×1 图按宽等高出血到 300；
    // 不出血时只有正文宽 260。
    expect(imageBlock.height, closeTo(300, 1.0));
  });

  test('表格单元格读取作者 CSS 与祖先选择器（P9-16）', () async {
    final source = await open(
      body:
          '<table class="t"><tr><td class="a">甲</td><td>乙</td></tr></table>',
      css:
          'table.t td { padding: 2px 6px; background: #102030; '
          'border: 1px solid #334455; }',
    );
    final pages = await source.loadChapter(0);
    final spec = pages
        .expand((page) => page.slices)
        .map((slice) => slice.block)
        .firstWhere((block) => block.table != null)
        .table!;
    final cell = spec.cells.firstWhere((item) => item.layout.text == '甲');
    expect(cell.style.padding.left, 6);
    expect(cell.style.padding.top, 2);
    expect(cell.style.backgroundColor, const Color(0xFF102030));
    expect(cell.style.borders.left.width, 1);
  });

  test('table-layout: fixed 按 col 声明宽分列（P9-17）', () async {
    final source = await open(
      body:
          '<table class="t"><colgroup>'
          '<col class="c1"/><col class="c2"/></colgroup>'
          '<tr><td>甲</td><td>乙</td></tr></table>',
      css:
          'table.t { table-layout: fixed; width: 100%; } '
          'table.t col.c1 { width: 70%; } '
          'table.t col.c2 { width: 30%; }',
    );
    final pages = await source.loadChapter(0);
    final spec = pages
        .expand((page) => page.slices)
        .map((slice) => slice.block)
        .firstWhere((block) => block.table != null)
        .table!;
    expect(spec.columnXs.length, 3, reason: '两列三个列界');
    final total = spec.columnXs.last;
    expect(total, greaterThan(0));
    expect(spec.columnXs[1] / total, closeTo(0.7, 0.03));
  });

  test('table-layout: fixed 未声明列平分剩余（P9-17）', () async {
    final source = await open(
      body:
          '<table class="t">'
          '<tr><td class="w">甲</td><td>乙</td></tr></table>',
      css:
          'table.t { table-layout: fixed; width: 100%; } '
          'table.t td.w { width: 20%; }',
    );
    final pages = await source.loadChapter(0);
    final spec = pages
        .expand((page) => page.slices)
        .map((slice) => slice.block)
        .firstWhere((block) => block.table != null)
        .table!;
    final total = spec.columnXs.last;
    expect(spec.columnXs[1] / total, closeTo(0.2, 0.03));
    expect((total - spec.columnXs[1]) / total, closeTo(0.8, 0.03));
  });

  test('绝对定位块脱离流并按 top/left 绘制（P9-19）', () async {
    final source = await open(
      body:
          '<div class="badge">绝对块</div>'
          '<p>正文第一段足够长的文字用来占位。</p>',
      css: '.badge { position: absolute; top: 40px; left: 30px; }',
    );
    final pages = await source.loadChapter(0);
    final page = pages.first;
    final badge = page.slices.firstWhere(
      (slice) => slice.block.layout.text.contains('绝对块'),
    );
    expect(badge.overlay, isTrue, reason: '绝对块不占流高');
    expect(badge.absoluteTop, closeTo(40, 0.5));
    expect(badge.leftInset, closeTo(30, 0.5));
    // 正文仍然从页首正常排版，未被绝对块顶下去。
    final paragraph = page.slices.firstWhere(
      (slice) => slice.block.layout.text.contains('正文第一段'),
    );
    expect(paragraph.overlay, isFalse);
  });

  test('纯装饰章仍产出一页并承载整页背景（P9-21）', () async {
    final source = await open(
      body:
          '<h2 style="display: none;">制作页</h2><p><br/></p>',
      css: 'body { background-image: url("../Images/i.png"); '
          'background-size: cover; background-repeat: no-repeat; }',
    );
    final pages = await source.loadChapter(0);
    expect(pages, hasLength(1), reason: '空白章不能产出零页');
    expect(pages.first.slices, isEmpty);
    expect(pages.first.background?.imageUrl, 'OEBPS/Images/i.png');
  });

  test('多看私有属性在真实管线生效（P9-13）', () async {
    final source = await open(
      body: '<p class="d">多看段落</p>',
      css:
          'p.d { -duokan-text-indent: 2em; duokan-paragraph-align: center; '
          'duokan-break-inside: avoid; }',
    );
    final pages = await source.loadChapter(0);
    final style = pages.first.slices.first.block.style!;
    expect(style.textIndent, 34);
    expect(style.textAlign, CssTextAlign.center);
    expect(style.breakInsideAvoid, isTrue);
  });

  test('list-style-type 决定列表标记（P9-12）', () async {
    final roman = await open(
      body: '<ol><li class="r">一</li><li class="r">二</li></ol>',
      css: 'li.r { list-style-type: upper-roman; }',
    );
    final romanPages = await roman.loadChapter(0);
    final romanMarkers = romanPages.first.slices
        .map((slice) => slice.block.listMarker)
        .whereType<String>()
        .toList();
    expect(romanMarkers, containsAll(<String>['I.', 'II.']));

    final none = await open(
      body: '<ul class="plain"><li>无标记</li></ul>',
      css: 'ul.plain { list-style: none; }',
    );
    final nonePages = await none.loadChapter(0);
    final markers = nonePages.first.slices
        .map((slice) => slice.block.listMarker)
        .whereType<String>()
        .toList();
    expect(markers, isEmpty);
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
