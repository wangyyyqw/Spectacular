import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/parser/document_parser.dart';
import 'package:reader_mobile/reader/epub_chapter_source.dart';

import 'support/css_chapter_book.dart';

Future<List<PageBlock>> blocksOf(
  EpubChapterSource source, [
  int spine = 0,
]) async {
  final pages = await source.loadChapter(spine);
  return pages
      .expand((page) => page.slices)
      .map((slice) => slice.block)
      .toSet()
      .toList();
}

Map<String, String> textCfis(ParsedNode root) {
  final result = <String, String>{};
  void visit(ParsedNode node) {
    if (node is ParsedText) result[node.text] = node.cfi.serialize();
    if (node is ParsedElement) node.children.forEach(visit);
  }

  visit(root);
  return result;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('作者将行内标签改为块：前后兄弟独立排版并保留原文本 CFI', () async {
    final source = await openCssChapter(
      body: '<p>前文<span class="block">块内文字</span>后文</p>',
      css:
          'p { margin: 0; } .block { display: block; padding: 4px; '
          'margin: 8px 0; border-bottom: 1px solid #123456; }',
    );
    final cfis = textCfis(source.document.parseDocument(0).root);
    final blocks = await blocksOf(source);
    expect(blocks.map((block) => block.layout.text), ['前文', '块内文字', '后文']);
    for (final block in blocks) {
      expect(block.startCfi, cfis[block.layout.text]);
    }
    final block = blocks[1];
    expect(block.style!.padding.bottom, 4);
    expect(block.style!.borders.bottom.width, 1);
    expect(block.spaceBefore, 8);
    expect(block.spaceAfter + blocks[2].spaceBefore, 8);
    expect(block.layout.maxWidth, closeTo(292, .01));
  });

  test('嵌套行内包装中的块保留顺序、继承和隐藏规则', () async {
    final source = await openCssChapter(
      body:
          '<p>前<b>外<span class="block">中<i>斜体</i>'
          '<span class="gone">隐藏</span><span class="block">内块</span>尾</span>'
          '后</b><span hidden="hidden">不见</span>终</p>',
      css: 'p { margin: 0; } .block { display: block; } .gone { display: none; }',
    );
    final blocks = await blocksOf(source);
    expect(blocks.map((block) => block.layout.text), [
      '前外',
      '中斜体',
      '内块',
      '尾',
      '后终',
    ]);
    expect(blocks.map((block) => block.layout.text).join(), '前外中斜体内块尾后终');
    expect(blocks[1].style!.fontWeight, 700);
    expect(blocks[2].style!.fontWeight, 700);
  });

  test('媒体条件重排时重新决定行内标签是否成块', () async {
    final source = await openCssChapter(
      body: '<p>前<span>中</span>后</p>',
      css: 'p { margin: 0; } @media (max-width: 320px) { span { display: block; } }',
      contentWidth: 300,
    );
    expect((await blocksOf(source)).map((block) => block.layout.text), [
      '前',
      '中',
      '后',
    ]);
    await source.applyContentSize(width: 400, height: 500);
    expect((await blocksOf(source)).map((block) => block.layout.text), ['前中后']);
  });

  test('结构伪类与兄弟组合器参与聚合前的 display 判定', () async {
    for (final selector in [
      'span:nth-child(2)',
      'span + span',
      'span:last-child',
    ]) {
      final source = await openCssChapter(
        body: '<p><span>前</span><span>中</span>后</p>',
        css: 'p { margin: 0; } $selector { display: block; }',
      );
      expect((await blocksOf(source)).map((block) => block.layout.text), [
        '前',
        '中',
        '后',
      ], reason: selector);
    }
  });

  test('隐藏单图不进入满屏快路', () async {
    const transparentPng =
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8'
        '/x8AAwMCAO+aR2kAAAAASUVORK5CYII=';
    for (final body in [
      '<img src="x.png" hidden="hidden"/>',
      '<img src="x.png" style="display:none"/>',
    ]) {
      final source = await openCssChapter(
        body: body,
        binaryFiles: {'OEBPS/Text/x.png': base64Decode(transparentPng)},
      );
      expect(source.fullBleedAnalysis(0).isFullBleed, isFalse, reason: body);
      final pages = await source.loadChapter(0);
      expect(pages.expand((page) => page.slices), isEmpty, reason: body);
    }
  });

  test('媒体条件改变图片可见性时刷新满屏判定', () async {
    const transparentPng =
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8'
        '/x8AAwMCAO+aR2kAAAAASUVORK5CYII=';
    final source = await openCssChapter(
      body: '<img src="x.png"/>',
      css: '@media (max-width: 320px) { img { display: none; } }',
      contentWidth: 400,
      binaryFiles: {'OEBPS/Text/x.png': base64Decode(transparentPng)},
    );
    expect(source.fullBleedAnalysis(0).isFullBleed, isTrue);
    await source.applyContentSize(width: 300, height: 500);
    expect(source.fullBleedAnalysis(0).isFullBleed, isFalse);
  });

  test('未声明、初始值和无效 display 不会把行内标签提升成块', () async {
    final source = await openCssChapter(
      body:
          '<p>前<span>未声明</span><span style="display:initial">初始</span>'
          '<span style="display:unknown">无效</span>后</p>',
    );
    expect((await blocksOf(source)).single.layout.text, '前未声明初始无效后');
  });

  test('外层段落盒只保留一份，跨块的行内样式在后文继续生效', () async {
    final source = await openCssChapter(
      body: '<p>前<b>粗<span style="display:block">块</span>粗后</b>尾</p>',
      css: 'p { margin: 7px 0; padding: 3px; border: 2px solid red; }',
    );
    final blocks = await blocksOf(source);
    expect(blocks.map((block) => block.layout.text), ['前粗', '块', '粗后尾']);
    final containers = blocks
        .expand((block) => block.containers)
        .map((fragment) => fragment.container)
        .toSet();
    expect(containers, hasLength(1));
    expect(containers.single.style.margin.top, 7);
    expect(blocks.every((block) => !block.style!.borders.hasBorder), isTrue);
    final tailRun = blocks.last.layout.runs.single;
    expect(tailRun.start, 0);
    expect(tailRun.end, 2);
    expect(tailRun.style.fontWeight, 700);
  });

  test('块内保留空白与相邻块空白折叠不互相污染', () async {
    final source = await openCssChapter(
      body: '<p>前 <span class="block"> A  B\nC </span> 后</p>',
      css: 'p { margin: 0; } .block { display: block; white-space: pre; }',
    );
    final blocks = await blocksOf(source);
    expect(blocks.map((block) => block.layout.text), ['前', ' A  B\nC ', '后']);
    expect(blocks[1].layout.lineCount, 2);
  });

  test('用户段距仅作用于原段落，匿名片段与提升块保留作者间距', () async {
    final source = await openCssChapter(
      body: '<p>前<span class="block">中</span>后</p>',
      css: 'p { margin: 30px 0; } .block { display: block; margin-bottom: 8px; }',
      overrides: const ReaderOverrides(paragraphSpacing: 10),
    );
    final blocks = await blocksOf(source);
    expect(blocks.map((block) => block.layout.text), ['前', '中', '后']);
    expect(blocks[0].topInset, 10);
    expect(blocks[2].bottomInset, 10);
    expect(blocks[0].spaceBefore, 0);
    expect(blocks[1].spaceBefore, 0);
    expect(blocks[1].spaceAfter + blocks[2].spaceBefore, 8);
    expect(blocks[2].spaceAfter, 0);
  });

  test('提升为块只改变盒类型，相对字号继续继承最终正文，定位不随字号变化', () async {
    final source = await openCssChapter(
      body:
          '<p>正文<b><span class="relative">相对字号</span></b>'
          '<span class="pixels">固定像素</span><span class="root">根字号</span>尾</p>',
      css:
          'p { font-size: .8em; color: #123456; margin: 0; } '
          'span { display: block; } .relative { font-size: .85em; } '
          '.pixels { font-size: 12px; } .root { font-size: 1.2rem; }',
    );
    final cfis = textCfis(source.document.parseDocument(0).root);
    for (final size in [17.0, 22.0]) {
      await source.applyOverrides(ReaderOverrides(fontSize: size));
      final blocks = await blocksOf(source);
      final relative = blocks.singleWhere(
        (block) => block.layout.text == '相对字号',
      );
      expect(relative.style!.fontSize, closeTo(size * .85, .001));
      expect(relative.style!.fontWeight, 700);
      expect(relative.style!.color.toARGB32(), 0xff123456);
      expect(
        blocks
            .singleWhere((block) => block.layout.text == '固定像素')
            .style!
            .fontSize,
        12,
      );
      expect(
        blocks
            .singleWhere((block) => block.layout.text == '根字号')
            .style!
            .fontSize,
        closeTo(size * 1.2, .001),
      );
      for (final block in blocks) {
        expect(block.startCfi, cfis[block.layout.text]);
      }
    }
  });

  final book = File('../../test_corpus/real/zhushen-yuxi.epub');
  test('诸神愚戏正文第3章：试炼目标标签有独立块盒与完整下边框', () async {
    final source = await EpubChapterSource.open(
      book.readAsBytesSync(),
      verifyCrc: false,
    );
    final blocks = await blocksOf(source, 47);
    final label = blocks.singleWhere(
      (block) => block.layout.text.trim() == '◆ 试炼目标',
    );
    expect(label.style!.padding.bottom, 4);
    expect(label.style!.borders.bottom.width, 1);
    expect(label.style!.borders.bottom.color.toARGB32(), 0xff541c1c);
    expect(label.style!.margin.bottom, 8);
    expect(label.layout.maxWidth, greaterThan(label.layout.lines.single.width));
    final labelIndex = blocks.indexOf(label);
    expect(blocks[labelIndex + 1].layout.text, '在血与火的拷问中，咬紧牙关。');
  }, skip: !book.existsSync() ? '未提供本地真实书' : false);
}
