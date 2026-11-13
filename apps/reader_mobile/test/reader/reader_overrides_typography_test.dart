import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/font_face.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/epub/epub_chapter_source.dart';

import 'support/css_chapter_book.dart';

Uint8List _epub(String css, String body, {bool heading = true}) {
  final archive = Archive();
  void add(String name, String content) {
    final bytes = Uint8List.fromList(utf8.encode(content));
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }

  archive.addFile(
    ArchiveFile('mimetype', 20, 'application/epub+zip'.codeUnits),
  );
  add(
    'META-INF/container.xml',
    '<?xml version="1.0"?><container version="1.0" '
        'xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles>'
        '<rootfile full-path="OEBPS/content.opf" '
        'media-type="application/oebps-package+xml"/></rootfiles></container>',
  );
  add(
    'OEBPS/content.opf',
    '<?xml version="1.0"?><package xmlns="http://www.idpf.org/2007/opf" '
        'version="3.0" unique-identifier="uid">'
        '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
        '<dc:identifier id="uid">urn:uuid:ov-test-1</dc:identifier>'
        '<dc:title>Ov</dc:title><dc:language>zh</dc:language></metadata>'
        '<manifest>'
        '<item id="c1" href="c1.xhtml" media-type="application/xhtml+xml"/>'
        '<item id="css" href="s.css" media-type="text/css"/>'
        '</manifest><spine><itemref idref="c1"/></spine></package>',
  );
  add(
    'OEBPS/c1.xhtml',
    '<html xmlns="http://www.w3.org/1999/xhtml"><head>'
        '<link href="s.css" type="text/css" rel="stylesheet"/>'
        '</head><body>${heading ? '<h2>标题</h2>' : ''}$body</body></html>',
  );
  add('OEBPS/s.css', css);
  return Uint8List.fromList(ZipEncoder().encodeBytes(archive));
}

const _bookCss =
    'h2 { font-size: 24px; margin-top: 1em; margin-bottom: 1em; }'
    'p { font-size: 16px; line-height: 130%; '
    'margin-top: 1em; margin-bottom: 1em; }';

Future<List<PageBlock>> _blocks(ReaderOverrides? overrides) async {
  final source = await EpubChapterSource.open(
    _epub(_bookCss, '<p>正文一段${'字' * 40}</p><p>正文二段${'字' * 40}</p>'),
  );
  await source.applyContentSize(width: 300, height: 600);
  if (overrides != null) {
    await source.applyOverrides(overrides);
  }
  return (await source.loadChapter(0))
      .expand((page) => page.slices.map((s) => s.block))
      .toList();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('阅读器字号/行高覆盖作者 CSS（reader origin 优先）', () async {
    const overrides = ReaderOverrides(fontSize: 20, lineHeight: 1.8);
    final blocks = await _blocks(overrides);
    final paragraphs = blocks
        .where((b) => b.layout.text.contains('正文'))
        .toList();
    expect(paragraphs, isNotEmpty);
    for (final block in paragraphs) {
      expect(block.style!.fontSize, 20, reason: '字号覆盖作者声明');
      expect(
        block.style!.lineHeight,
        closeTo(36, 0.01),
        reason: '行高 1.8 × 20dp',
      );
      expect(block.layout.maxWidth, greaterThan(0));
    }
  });

  test('阅读器字号保留容器内的继承比例且不连带放大作者 em 盒', () async {
    for (final readerSize in [12.0, 20.0]) {
      final source = await openCssChapter(
        body:
            '<div class="design-box">'
            '<h1>制作信息</h1><p>作者：测试作者</p>'
            '<p class="ovalnote">制作说明</p></div>',
        css:
            'body { font-size: 16px; } '
            '.design-box { font-size: .75em; border: double 1em #000; '
            'padding: .5em; margin: 1.5em 0; } '
            '.design-box h1 { font-size: 1.2em; margin: 12px auto; } '
            '.design-box p { margin: 4px 1em; } '
            '.ovalnote { font-size: .9em; }',
        overrides: ReaderOverrides(
          fontSize: readerSize,
          lineHeight: 1.3,
          paragraphSpacing: 0,
        ),
      );
      final blocks = (await source.loadChapter(0))
          .expand((page) => page.slices)
          .map((slice) => slice.block)
          .toList();
      final paragraph = blocks.firstWhere(
        (block) => block.layout.text.contains('作者：测试作者'),
      );
      final heading = blocks.firstWhere((block) => block.layout.text == '制作信息');
      final note = blocks.firstWhere((block) => block.layout.text == '制作说明');
      final container = paragraph.containers.single.container.style;

      expect(
        paragraph.style!.fontSize,
        closeTo(readerSize * .75, 0.001),
        reason: '正文继承作者容器的 .75em 比例',
      );
      expect(container.fontSize, closeTo(12, 0.001), reason: '作者 .75em 盒保持源比例');
      expect(container.borders.left.width, closeTo(12, 0.001));
      expect(container.padding.left, closeTo(6, 0.001));
      expect(heading.style!.fontSize, closeTo(readerSize * .75 * 1.2, 0.001));
      expect(note.style!.fontSize, closeTo(readerSize * .75 * .9, 0.001));
    }
  });

  test('普通正文保留作者百分字号且正文基准不变', () async {
    for (final readerSize in [12.0, 20.0]) {
      final source = await openCssChapter(
        body:
            '<p>正文</p>'
            '<div class="copyright">'
            '<p class="subhead">图书在版编目数据</p>'
            '<p class="small">方舟</p>'
            '</div>',
        css:
            'body { font-size: 16px; } p { font-size: 80%; } '
            '.copyright { padding: 1em; border: 1px solid #412938; } '
            '.subhead { font-size: 65%; } '
            '.small { font-size: 60%; }',
        overrides: ReaderOverrides(
          fontSize: readerSize,
          lineHeight: 1.6,
          paragraphSpacing: 0,
        ),
      );
      final blocks = (await source.loadChapter(0))
          .expand((page) => page.slices)
          .map((slice) => slice.block)
          .toList();
      final body = blocks.firstWhere((block) => block.layout.text == '正文');
      final subhead = blocks.firstWhere(
        (block) => block.layout.text == '图书在版编目数据',
      );
      final small = blocks.firstWhere((block) => block.layout.text == '方舟');

      expect(body.style!.fontSize, readerSize, reason: '正文继续跟随阅读器字号');
      expect(
        subhead.style!.fontSize,
        closeTo(readerSize * 0.65, 0.001),
        reason: 'CIP 标题保留作者 65% 相对字号',
      );
      expect(
        small.style!.fontSize,
        closeTo(readerSize * 0.6, 0.001),
        reason: '作者 60% 相对字号不能被提升为正文满字号',
      );
      expect(small.style!.lineHeight, closeTo(readerSize * 0.6 * 1.6, 0.001));
    }
  });

  test('阅读器段距同步应用于分隔线', () async {
    final source = await openCssChapter(
      body: '<div class="design-box"><p>前文</p><hr/><p>后文</p></div>',
      css:
          '.design-box { font-size: .75em; } '
          '.design-box p { margin: 4px 0; } '
          '.design-box hr { margin: 6px 0; border: 1px dashed #000; }',
      overrides: const ReaderOverrides(paragraphSpacing: 0),
    );
    final rule = (await source.loadChapter(0))
        .expand((page) => page.slices)
        .map((slice) => slice.block)
        .firstWhere((block) => block.style?.borders.top.width == 1);

    expect(rule.spaceBefore, 0);
    expect(rule.spaceAfter, 0);
  });

  test('正文字体覆盖作者块与行内样式', () async {
    final source = await openCssChapter(
      body: '<p class="quote">正文<span class="inline">行内</span></p>',
      css:
          '.quote { font-family: "楷体", serif; } '
          '.inline { font-family: "宋体", serif; }',
      overrides: const ReaderOverrides(fontFamily: FontFamilyAliases.hei),
    );
    final block = (await source.loadChapter(0))
        .expand((page) => page.slices)
        .map((slice) => slice.block)
        .firstWhere((block) => block.layout.text.startsWith('正文'));

    expect(block.style!.fontFamily, FontFamilyAliases.hei);
    expect(
      block.layout.runs.map((run) => run.style.fontFamily),
      everyElement(
        predicate<String?>(
          (family) =>
              family == FontFamilyAliases.hei ||
              FontFamilyAliases.sansChain.contains(family) ||
              FontFamilyAliases.resolve(family ?? '') == FontFamilyAliases.hei,
          '映射到黑体回退链',
        ),
      ),
      reason: '行内作者字体也不能把正文换回其他字族',
    );
  });

  test('真书带行内注释的行正文仍使用阅读器字体', () async {
    final bytes = await File(
      '../../test_corpus/real/shiji-yuewei.epub',
    ).readAsBytes();
    final source = await EpubChapterSource.open(bytes);
    await source.applyContentSize(width: 300, height: 600);
    await source.applyOverrides(
      const ReaderOverrides(fontFamily: FontFamilyAliases.hei),
    );
    final blocks = (await source.loadChapter(136))
        .expand((page) => page.slices)
        .map((slice) => slice.block)
        .toList();
    final block = blocks.firstWhere(
      (block) => block.layout.text.contains('驾应龙'),
    );

    expect(block.style!.fontFamily, FontFamilyAliases.hei);
    expect(
      block.layout.runs.map((run) => run.style.fontFamily),
      everyElement(
        predicate<String?>(
          (family) =>
              family == FontFamilyAliases.hei ||
              FontFamilyAliases.sansChain.contains(family) ||
              FontFamilyAliases.resolve(family ?? '') == FontFamilyAliases.hei,
          '映射到黑体回退链',
        ),
      ),
    );
  });

  test('段距设置生效且相邻折叠后等于设置值', () async {
    const overrides = ReaderOverrides(paragraphSpacing: 8);
    final source = await EpubChapterSource.open(
      _epub(
        _bookCss,
        '<p>正文一段${'字' * 40}</p><p>正文二段${'字' * 40}</p>',
        heading: false,
      ),
    );
    await source.applyContentSize(width: 300, height: 600);
    await source.applyOverrides(overrides);
    final pages = await source.loadChapter(0);
    final slices = pages.first.slices
        .where((s) => s.block.layout.text.contains('正文'))
        .toList();
    expect(slices.length, greaterThanOrEqualTo(2));
    expect(slices[0].block.spaceBefore, 8, reason: '首段段前距取设置值');
    expect(slices[0].block.spaceAfter, 0, reason: '段后距折叠并入下段');
    expect(slices[1].block.spaceBefore, 8, reason: '下段段前距折叠结果');
    expect(slices[1].block.spaceAfter, 8, reason: '末段段后距保留设置值');
    expect(slices[1].leadingExtent, 8, reason: '折叠后段距 = 8，而非 8+8');
  });

  test('标题不参与正文字号/段距覆盖', () async {
    const overrides = ReaderOverrides(fontSize: 20, paragraphSpacing: 8);
    final blocks = await _blocks(overrides);
    final heading = blocks.firstWhere((b) => b.layout.text.contains('标题'));
    expect(heading.style!.fontSize, 24, reason: '标题字号跟随书籍样式');
    expect(heading.spaceBefore, 24, reason: '标题段前距保留 1em（24px）');
  });

  test('带左色条的结构化标题保留作者段距', () async {
    final source = await EpubChapterSource.open(
      _epub(
        '.xbt2 { margin: 1.2em auto 1em; padding-left: 10px; '
            'border-left: 15px solid #304598; } '
            'p { margin: 1em 0; }',
        '<div class="xbt2">猫的理想（可升级）</div>'
            '<p>正文一段${'字' * 30}</p>'
            '<p>正文二段${'字' * 30}</p>',
        heading: false,
      ),
    );
    await source.applyContentSize(width: 300, height: 600);
    await source.applyOverrides(
      const ReaderOverrides(paragraphSpacing: 10),
    );
    final blocks = (await source.loadChapter(0))
        .expand((page) => page.slices)
        .map((slice) => slice.block)
        .toList();
    final title = blocks.firstWhere(
      (block) => block.layout.text == '猫的理想（可升级）',
    );
    expect(title.spaceBefore, closeTo(19.2, 0.01));
    expect(title.style!.margin.bottom, closeTo(16, 0.01));
    final secondParagraph = blocks.firstWhere(
      (block) => block.layout.text.startsWith('正文二段'),
    );
    expect(
      secondParagraph.spaceBefore,
      10,
      reason: '普通正文仍使用阅读器段距',
    );
  });

  test('非语义居中短标题保留作者字号和行高', () async {
    final source = await openCssChapter(
      body: '<p class="cover">作\u2002品\u2002\u2002\u2002相\u2002关</p>',
      css:
          'p.cover { font-size: 1.6em; line-height: 1.3; '
          'text-align: center; margin: 15em 0 1em; }',
      overrides: const ReaderOverrides(
        fontSize: 17,
        lineHeight: 1.6,
        paragraphSpacing: 10,
      ),
    );
    final title = (await source.loadChapter(0))
        .expand((page) => page.slices)
        .map((slice) => slice.block)
        .single;
    expect(title.style!.fontSize, closeTo(27.2, 0.001));
    expect(title.style!.lineHeightFactor, closeTo(1.3, 0.001));
    expect(title.spaceBefore, closeTo(408, 0.001));
  });

  test('行内文字与标签继承覆盖后的正文，标题和表格继续采用作者字号', () async {
    final source = await openCssChapter(
      body:
          '<p>正文<span class="relative">行内</span>'
          '<span class="box"><b>标签</b></span>'
          '<span class="fixed">固定</span></p>'
          '<h2><span class="relative">标题</span></h2>'
          '<table><tr><td><span class="box">评级</span></td></tr></table>',
      css:
          'p { font-size: .8em; } h2 { font-size: 24px; } '
          'td { font-size: 12px; } .relative, .box { font-size: .8em; } '
          '.box { display: inline-block; } .box b { font-size: .5em; } '
          '.fixed { font-size: 12px; }',
    );
    for (final size in [17.0, 22.0]) {
      await source.applyOverrides(
        ReaderOverrides(fontSize: size, lineHeight: 1.8),
      );
      final blocks = (await source.loadChapter(0))
          .expand((page) => page.slices)
          .map((slice) => slice.block)
          .toList();
      final body = blocks.firstWhere(
        (block) => block.layout.text.startsWith('正文'),
      );
      expect(body.style!.fontSize, size);
      final relative = body.layout.runs.firstWhere((run) => run.start == 2);
      expect(relative.style.fontSize, closeTo(size * .8, .001));
      expect(body.layout.runs.last.style.fontSize, 12, reason: '绝对字号继续由作者指定');
      final box = body.layout.lines.expand((line) => line.inlineBoxes).single;
      final payload = box.spec.payload! as PageBlock;
      expect(payload.style!.fontSize, closeTo(size * .8, .001));
      expect(
        payload.layout.runs.single.style.fontSize,
        closeTo(size * .8 * .5, .001),
      );
      final heading = blocks.firstWhere((block) => block.layout.text == '标题');
      expect(heading.style!.fontSize, 24);
      expect(heading.layout.runs.single.style.fontSize, closeTo(24 * .8, .001));
      final table = blocks.firstWhere((block) => block.table != null);
      final rank =
          table.table!.cells.single.layout.lines.single.inlineBoxes.single;
      expect(
        (rank.spec.payload! as PageBlock).style!.fontSize,
        closeTo(12 * .8, .001),
      );
    }
  });

  test('紧凑行高容器内的小字号组件保留作者排版', () async {
    final source = await openCssChapter(
      body:
          '<div class="chat">'
          '<div class="name">寻歌</div>'
          '<div class="bubble"><p>我保证帮你弄到</p></div>'
          '</div>'
          '<p class="body">普通正文${'字' * 30}</p>',
      css:
          '.chat { line-height: 100%; } '
          '.name { font-size: 11px; line-height: 100%; } '
          '.bubble p { margin: 0; font-size: .75em; } '
          '.body { font-size: 16px; line-height: 130%; }',
    );
    await source.applyOverrides(
      const ReaderOverrides(fontSize: 20, lineHeight: 1.8),
    );
    final blocks = (await source.loadChapter(0))
        .expand((page) => page.slices)
        .map((slice) => slice.block)
        .toList();
    final name = blocks.firstWhere((block) => block.layout.text == '寻歌');
    final bubble = blocks.firstWhere(
      (block) => block.layout.text == '我保证帮你弄到',
    );
    final paragraph = blocks.firstWhere(
      (block) => block.layout.text.startsWith('普通正文'),
    );

    expect(name.style!.fontSize, 11);
    expect(name.style!.lineHeight, closeTo(11, 0.01));
    expect(
      bubble.style!.fontSize,
      closeTo(15, 0.01),
      reason: '.75em 相对阅读器字号缩放，但不被提升为满字号',
    );
    expect(bubble.style!.lineHeight, closeTo(20, 0.01));
    expect(paragraph.style!.fontSize, 20, reason: '普通正文仍跟随阅读器设置');
  });

  test('段距进排版指纹（设置变更触发重排）', () {
    const a = ReaderOverrides(paragraphSpacing: 8);
    const b = ReaderOverrides(paragraphSpacing: 12);
    expect(a.fingerprint, isNot(b.fingerprint));
    expect(
      ReaderOverrides().fingerprint,
      isNot(a.fingerprint),
      reason: '未设置与设置值必须区分',
    );
  });
}
