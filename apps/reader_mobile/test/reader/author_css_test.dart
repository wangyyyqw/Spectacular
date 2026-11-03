import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show Color;

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_mobile/reader/epub_chapter_source.dart';

/// 构造带 link 作者 CSS 的最小 EPUB（真实书适配回归）。
Uint8List _buildEpubWithCss(String css, String bodyHtml) {
  final archive = Archive();
  void addText(String name, String content) {
    final bytes = Uint8List.fromList(utf8.encode(content));
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }

  archive.addFile(
    ArchiveFile('mimetype', 20, 'application/epub+zip'.codeUnits),
  );
  addText(
    'META-INF/container.xml',
    '''<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
</container>''',
  );
  addText(
    'OEBPS/content.opf',
    '''<?xml version="1.0"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="uid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="uid">urn:uuid:css-test-0001</dc:identifier>
    <dc:title>CssStyle</dc:title>
    <dc:language>zh</dc:language>
  </metadata>
  <manifest>
    <item id="c1" href="c1.xhtml" media-type="application/xhtml+xml"/>
    <item id="css" href="style.css" media-type="text/css"/>
  </manifest>
  <spine><itemref idref="c1"/></spine>
</package>''',
  );
  addText(
    'OEBPS/c1.xhtml',
    '<html xmlns="http://www.w3.org/1999/xhtml"><head>'
    '<link href="style.css" type="text/css" rel="stylesheet"/>'
    '</head><body>$bodyHtml</body></html>',
  );
  addText('OEBPS/style.css', css);
  return Uint8List.fromList(ZipEncoder().encodeBytes(archive));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('作者 p 规则：首行缩进/两端对齐/行距生效', () async {
    final source = await EpubChapterSource.open(_buildEpubWithCss(
      'p { text-align: justify; text-indent: 2em; line-height: 130%; }',
      '<p>正文段落，验证作者 CSS 的首行缩进与两端对齐是否进入 flat 管线。</p>',
    ));
    final block = (await source.loadChapter(0))
        .expand((page) => page.slices.map((s) => s.block))
        .first;
    final style = block.style!;
    expect(style.textIndent, isNotNull, reason: 'text-indent: 2em 解析');
    expect(style.textAlign, CssTextAlign.justify, reason: 'text-align: justify');
    expect(style.lineHeight, greaterThan(style.fontSize * 1.2),
        reason: 'line-height: 130% 相对字号解算');
  });

  test('作者 class 规则：h2.cls 居中覆盖 UA 左对齐', () async {
    final source = await EpubChapterSource.open(_buildEpubWithCss(
      'h2.chapter { text-align: center; }',
      '<h2 class="chapter">第一章 标题</h2><p>正文。</p>',
    ));
    final blocks = (await source.loadChapter(0))
        .expand((page) => page.slices.map((s) => s.block))
        .toList();
    final title = blocks.firstWhere((b) => b.layout.text.contains('第一章'));
    expect(title.style!.textAlign, CssTextAlign.center,
        reason: 'h2.chapter 类选择器命中');
    final body = blocks.firstWhere((b) => b.layout.text.contains('正文'));
    expect(body.style!.textAlign, isNot(CssTextAlign.center),
        reason: 'class 规则不串扰到无 class 的 p');
  });

  test('行内样式区间：span 类规则着色进入混排 runs', () async {
    final source = await EpubChapterSource.open(_buildEpubWithCss(
      'span.hl { color: #fc8c23; font-weight: bold; }',
      '<p>前文<span class="hl">高亮文字</span>后文</p>',
    ));
    final block = (await source.loadChapter(0))
        .expand((page) => page.slices.map((s) => s.block))
        .first;
    final runs = block.layout.runs;
    final highlight = runs.firstWhere(
      (run) => block.layout.text.substring(run.start, run.end) == '高亮文字',
    );
    expect(highlight.style.color, const Color(0xFFFC8C23));
  });

  test('后代选择器（块级）：div.panel p 命中且不串扰普通 p', () async {
    final source = await EpubChapterSource.open(_buildEpubWithCss(
      'div.panel p { text-indent: 2em; color: #33691E; }',
      '<div class="panel"><p>面板内段落文字。</p></div><p>面板外普通段落。</p>',
    ));
    final blocks = (await source.loadChapter(0))
        .expand((page) => page.slices.map((s) => s.block))
        .toList();
    final inside = blocks.firstWhere((b) => b.layout.text.contains('面板内'));
    expect(inside.style!.textIndent, greaterThan(0), reason: 'div.panel p 缩进生效');
    expect(inside.style!.color, const Color(0xFF33691E));
    final outside = blocks.firstWhere((b) => b.layout.text.contains('面板外'));
    expect(outside.style!.textIndent, 0.0, reason: '普通 p 不受影响');
  });

  test('后代选择器（行内）：h2.t b 命中标题内 b 元素', () async {
    final source = await EpubChapterSource.open(_buildEpubWithCss(
      'h2.t b { font-size: 1.5em; color: #880E4F; }',
      '<h2 class="t">主标题<br/><b>副标题粗体</b></h2><p>正文。</p>',
    ));
    final blocks = (await source.loadChapter(0))
        .expand((page) => page.slices.map((s) => s.block))
        .toList();
    final title = blocks.firstWhere((b) => b.layout.text.contains('副标题'));
    final runs = title.layout.runs;
    expect(runs, isNotEmpty, reason: 'b 元素产生样式区间');
    final run = runs.firstWhere(
      (r) => title.layout.text.substring(r.start, r.end) == '副标题粗体',
    );
    expect(run.style.fontSize, greaterThan(title.style!.fontSize),
        reason: 'h2.t b 的 1.5em 字号命中');
  });

  test('子代组合器：div > p 命中直接子级、孙级不命中', () async {
    final source = await EpubChapterSource.open(_buildEpubWithCss(
      'div > p { color: #0D47A1; }',
      '<div><section><p>孙级段落。</p></section><p>子级段落。</p></div>',
    ));
    final blocks = (await source.loadChapter(0))
        .expand((page) => page.slices.map((s) => s.block))
        .toList();
    final child = blocks.firstWhere((b) => b.layout.text.contains('子级'));
    expect(child.style!.color, const Color(0xFF0D47A1), reason: '直接子级命中');
    final grand = blocks.firstWhere((b) => b.layout.text.contains('孙级'));
    expect(grand.style!.color, isNot(const Color(0xFF0D47A1)),
        reason: '孙级不命中（子代组合器）');
  });

  test('容器背景独立保留，正文使用容器内容区', () async {
    final source = await EpubChapterSource.open(_buildEpubWithCss(
      'div.panel { background-color: #FFF3E0; padding-left: 12px; }',
      '<div class="panel"><p>面板段落一。</p><p>面板段落二。</p></div>',
    ));
    final blocks = (await source.loadChapter(0))
        .expand((page) => page.slices.map((s) => s.block))
        .toList();
    for (final block in blocks.where((b) => b.layout.text.contains('面板'))) {
      expect(block.containers.single.container.style.backgroundColor,
          const Color(0xFFFFF3E0), reason: '容器背景独立保存');
      expect(block.style!.backgroundColor.a, 0, reason: '正文不重复绘制祖先背景');
      // 容器 padding-left 折算成后代块的左内缩；flat 管线把它记在
      // margin.left（P9-27 后不再同时写进 leftInset，避免重复计算），
      // 实际文字 x 仍是 leftInset + margin.left。
      expect(
        block.leftInset + block.style!.margin.left,
        greaterThanOrEqualTo(12),
        reason: '容器 padding-left 折算后代左内缩',
      );
    }
  });

  test('容器重建样式后仍保留作者文字色标记', () async {
    final source = await EpubChapterSource.open(_buildEpubWithCss(
      'div.panel { color: #33691E; padding-left: 12px; }',
      '<div class="panel"><p>面板内继承色。</p></div>',
    ));
    final block = (await source.loadChapter(0))
        .expand((page) => page.slices.map((s) => s.block))
        .firstWhere((b) => b.layout.text.contains('面板内'));
    expect(block.style!.color, const Color(0xFF33691E));
    expect(
      block.style!.hasExplicitTextColor,
      isTrue,
      reason: '容器 padding 触发样式重建，作者色标记不能丢',
    );
  });

  test('P8-05 块级上下边距进分页几何', () async {
    final source = await EpubChapterSource.open(_buildEpubWithCss(
      'p { margin-top: 24px; margin-bottom: 16px; }',
      '<p>第一段。</p><p>第二段。</p>',
    ));
    final blocks = (await source.loadChapter(0))
        .expand((page) => page.slices.map((s) => s.block))
        .toList();
    expect(blocks.first.spaceBefore, 24, reason: 'margin-top 进 spaceBefore');
    // 相邻兄弟折叠（CSS 2.1 §8.3.1）：段后 16 与下段段前 24 折叠为 max=24，
    // 落在下一块的 spaceBefore，上一块 spaceAfter 清零。
    expect(blocks.first.spaceAfter, 0, reason: '折叠后段后距并入下段');
    expect(blocks[1].spaceBefore, 24, reason: '相邻段距折叠取 max(16, 24)');
  });

  test('P8-05 负 margin 生效（段前距可为负）', () async {
    final source = await EpubChapterSource.open(_buildEpubWithCss(
      'p.tight { margin-top: -12px; }',
      '<p>普通段。</p><p class="tight">上提段。</p>',
    ));
    final blocks = (await source.loadChapter(0))
        .expand((page) => page.slices.map((s) => s.block))
        .toList();
    final tight = blocks.firstWhere((b) => b.layout.text.contains('上提'));
    // 折叠 = 正边距最大值 + 负边距最小值：上段段后 16 +（−12）= 4。
    expect(tight.spaceBefore, 4, reason: '负 margin-top 与上段段后距折叠');
  });

  test('P8-05c 容器上下边框拼合：首块画上边框、末块画下边框', () async {
    final source = await EpubChapterSource.open(_buildEpubWithCss(
      'div.frame { border: 2px solid #333333; }',
      '<div class="frame"><p>首段。</p><p>中段。</p><p>末段。</p></div>',
    ));
    final blocks = (await source.loadChapter(0))
        .expand((page) => page.slices.map((s) => s.block))
        .toList();
    final first = blocks.firstWhere((b) => b.layout.text.contains('首段'));
    final middle = blocks.firstWhere((b) => b.layout.text.contains('中段'));
    final last = blocks.firstWhere((b) => b.layout.text.contains('末段'));
    expect(first.containers.single.startsHere, isTrue);
    expect(first.containers.single.endsHere, isFalse);
    expect(middle.containers.single.startsHere, isFalse);
    expect(middle.containers.single.endsHere, isFalse);
    expect(last.containers.single.endsHere, isTrue);
    expect(last.containers.single.startsHere, isFalse);
    expect(first.containers.single.container.style.borders.top.width, 2);
    expect(identical(first.containers.single.container,
        last.containers.single.container), isTrue);
    expect(first.style!.borders.hasBorder, isFalse);

  });

  test('无 link 的书不受影响（UA 默认路径）', () async {
    final archive = Archive();
    void addText(String name, String content) {
      final bytes = Uint8List.fromList(utf8.encode(content));
      archive.addFile(ArchiveFile(name, bytes.length, bytes));
    }

    archive.addFile(
      ArchiveFile('mimetype', 20, 'application/epub+zip'.codeUnits),
    );
    addText(
      'META-INF/container.xml',
      '''<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
</container>''',
    );
    addText(
      'OEBPS/content.opf',
      '''<?xml version="1.0"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="uid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="uid">urn:uuid:no-css-0001</dc:identifier>
    <dc:title>NoCss</dc:title>
    <dc:language>zh</dc:language>
  </metadata>
  <manifest><item id="c1" href="c1.xhtml" media-type="application/xhtml+xml"/></manifest>
  <spine><itemref idref="c1"/></spine>
</package>''',
    );
    addText(
      'OEBPS/c1.xhtml',
      '<html xmlns="http://www.w3.org/1999/xhtml"><body><p>普通段落。</p></body></html>',
    );
    final source = await EpubChapterSource.open(
      Uint8List.fromList(ZipEncoder().encodeBytes(archive)),
    );
    final block = (await source.loadChapter(0))
        .expand((page) => page.slices.map((s) => s.block))
        .first;
    expect(block.style!.textIndent, 0.0, reason: '无作者 CSS 无首行缩进');
  });

  test('P8-07 display:none 容器子树剔除', () async {
    final source = await EpubChapterSource.open(_buildEpubWithCss(
      'div.secret { display: none; }',
      '<p>可见段。</p>'
      '<div class="secret"><p>隐藏段一。</p><p>隐藏段二。</p></div>'
      '<p>又见段。</p>',
    ));
    final texts = (await source.loadChapter(0))
        .expand((page) => page.slices.map((s) => s.block))
        .map((b) => b.layout.text)
        .toList();
    expect(texts.any((t) => t.contains('隐藏')), isFalse,
        reason: 'display:none 容器整棵子树不产出');
    expect(texts.any((t) => t.contains('可见')), isTrue);
    expect(texts.any((t) => t.contains('又见')), isTrue);
  });

  test('P8-07 [hidden] 属性元素剔除（UA 规则）', () async {
    final source = await EpubChapterSource.open(_buildEpubWithCss(
      '',
      '<p>前段。</p><p hidden="">隐藏段。</p><p>后段。</p>',
    ));
    final texts = (await source.loadChapter(0))
        .expand((page) => page.slices.map((s) => s.block))
        .map((b) => b.layout.text)
        .toList();
    expect(texts.any((t) => t.contains('隐藏段')), isFalse,
        reason: '[hidden] 经 UA 规则 display:none 剔除');
  });
}
