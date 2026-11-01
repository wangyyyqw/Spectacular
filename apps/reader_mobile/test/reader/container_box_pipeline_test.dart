import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/paint/hit_test.dart';
import 'package:reader_mobile/reader/epub_chapter_source.dart';

import 'support/css_chapter_book.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('效果名和段落共用容器，三层背景不合并到正文', () async {
    final source = await openCssChapter(
      body:
          '<div class="outer"><div class="card"><div class="effect">'
          '<span>效果名称</span><p>效果说明</p></div></div></div>',
      css:
          '.outer { background: rgba(0,0,0,.5); padding: 10px; }'
          '.card { background: rgba(0,0,0,.5); padding: 12px; }'
          '.effect { background: rgba(0,0,0,.8); padding: 6px 8px; '
          'border: 1px solid black; border-left: 2px solid gold; }',
    );
    final blocks = (await source.loadChapter(0))
        .expand((page) => page.slices)
        .map((slice) => slice.block)
        .toList();
    expect(blocks, hasLength(2));
    for (final block in blocks) {
      expect(block.containers, hasLength(3));
      expect(block.style!.borders.hasBorder, isFalse);
      expect(block.style!.backgroundColor.a, 0);
      expect(block.style!.margin.left, 32);
    }
    expect(blocks.first.containers.last.startsHere, isTrue);
    expect(blocks.first.containers.last.endsHere, isFalse);
    expect(blocks.last.containers.last.startsHere, isFalse);
    expect(blocks.last.containers.last.endsHere, isTrue);
  });

  test('标题表宽按卡片内容区解析，单元格不重复继承祖先内缩', () async {
    final source = await openCssChapter(
      body:
          '<div class="card"><table><tr><td>道具</td><td>SSS</td>'
          '</tr></table><p>说明</p></div>',
      css:
          '.card { padding: 12px; border: 2px solid black; }'
          'table { width: 100%; table-layout: fixed; border-collapse: collapse; }'
          'td { padding: 0; border: none; }',
      contentWidth: 350,
    );
    final table = (await source.loadChapter(0))
        .expand((page) => page.slices)
        .map((slice) => slice.block)
        .firstWhere((block) => block.table != null);
    expect(table.table!.tableWidth, 322);
    expect(table.style!.margin.left, 14);
    expect(table.table!.cells.first.style.margin.left, 0);
  });

  test('嵌套容器的百分比内边距按父内容宽度计算', () async {
    final source = await openCssChapter(
      body: '<div class="outer"><div class="inner"><p>正文</p></div></div>',
      css: '.outer { width: 200px; } .inner { padding: 10%; }',
      contentWidth: 350,
    );
    final block = (await source.loadChapter(0)).first.slices.first.block;
    expect(block.containers.last.container.style.padding.left, 20);
    expect(block.style!.margin.left, 20);
    expect(block.layout.maxWidth, 160);
  });

  test('纯图块保留祖先百分比宽，并按 auto 外边距居中', () async {
    final source = await openCssChapter(
      body:
          '<div class="intor"><img class="cover" '
          'src="../Images/cover.jpg"/></div><p>制作说明</p>',
      css:
          'div.intor { width: 35%; margin: 1em auto; } '
          'img.cover { width: 100%; }',
      contentWidth: 350,
      contentHeight: 800,
    );
    final blocks = (await source.loadChapter(0))
        .expand((page) => page.slices)
        .map((slice) => slice.block)
        .toList();
    final image = blocks.firstWhere((block) => block.layout.text.isEmpty);
    expect(image.style!.values['width'], '122.5px');
    expect(image.style!.margin.left, closeTo(113.75, 0.01));
  });

  test('纯图块按父级 text-align 居中', () async {
    final source = await openCssChapter(
      body:
          '<div class="gallery"><div class="cell">'
          '<img src="../Images/chart.jpg"/>'
          '</div></div><p>正文</p>',
      css:
          'div.gallery { width: 100%; text-align: center; } '
          'div.cell img { width: 80%; margin: 0.35em 0; }',
      contentWidth: 350,
      contentHeight: 800,
    );
    final blocks = (await source.loadChapter(0))
        .expand((page) => page.slices)
        .map((slice) => slice.block)
        .toList();
    final image = blocks.firstWhere((block) => block.layout.text.isEmpty);
    expect(image.style!.values['width'], '280.0px');
    expect(image.style!.margin.left, closeTo(35, 0.01));
  });

  test('嵌套定宽画廊中的图片同时叠加外层居中与内层行内居中', () async {
    final source = await openCssChapter(
      body:
          '<div class="duokan-image-gallery">'
          '<div class="duokan-image-gallery-cell">'
          '<img src="../Images/gallery.jpg"/>'
          '</div></div><p>正文</p>',
      css:
          'div.duokan-image-gallery { width: 65%; margin: 5% auto; '
          'text-align: center; } '
          'div.duokan-image-gallery-cell img { width: 80%; '
          'margin: 0.35em 0; }',
      contentWidth: 344,
      contentHeight: 800,
    );
    final blocks = (await source.loadChapter(0))
        .expand((page) => page.slices)
        .map((slice) => slice.block)
        .toList();
    final image = blocks.firstWhere((block) => block.layout.text.isEmpty);
    expect(
      image.style!.margin.left + image.style!.width!.resolve(344)! / 2,
      closeTo(source.contentWidth / 2, 0.01),
    );
  });

  test('定宽标题的 auto margin 让文字与盒一起水平居中', () async {
    final source = await openCssChapter(
      body:
          '<div class="bookcoverdA1">'
          '<b>人</b> <b>物</b> <b>关</b> <b>系</b> <b>图</b>'
          '</div>',
      css:
          'body { margin: 0; } '
          'div.bookcoverdA1 { width: 160px; margin: 20% auto 0 auto; '
          'font-size: 20px; text-align: center; } '
          'div.bookcoverdA1 b { background: #fff; }',
      contentWidth: 320,
      contentHeight: 800,
    );
    final page = (await source.loadChapter(0)).first;
    final block = page.slices.single.block;
    expect(block.layout.maxWidth, 160);
    expect(block.style!.margin.left, 80);
    expect(block.style!.margin.right, 80);
    final line = TextHitTester.lineBoxes(page).single;
    expect(line.rect.center.dx, closeTo(160, 1));
  });

  test('卡片之间不折叠各自容器内部的段距', () async {
    final source = await openCssChapter(
      body: '<div><p>一</p></div><div><p>二</p></div>',
      css: 'div { padding: 6px; } p { margin: 10px 0; }',
    );
    final slices = (await source.loadChapter(0)).first.slices;
    final distance =
        slices.first.height +
        slices.last.leadingExtent -
        slices.first.leadingExtent -
        slices.first.block.layout.height;
    expect(distance, 32);
  });

  test('含浮动的章节跨页后每页封框，仍保留真实容器首末标记', () async {
    final source = await openCssChapter(
      body:
          '<p class="float">浮</p><div class="card"><p>'
          '${'跨页容器正文。' * 50}</p></div>',
      css:
          '.float { float: left; width: 20px; } '
          '.card { padding: 6px; border: 1px solid black; background: #123456; }',
      contentHeight: 150,
      contentWidth: 200,
    );
    final pages = await source.loadChapter(0);
    expect(pages.length, greaterThan(1));
    final blocks = pages
        .expand((page) => page.slices)
        .where((slice) => !slice.overlay)
        .map((slice) => slice.block)
        .toList();
    expect(blocks.every((block) => block.containers.length == 1), isTrue);
    final fragments = blocks.map((block) => block.containers.single).toList();
    expect(fragments.every((f) => f.container.cloneDecoration), isTrue);
    expect(fragments.where((f) => f.startsHere), hasLength(1));
    expect(fragments.where((f) => f.endsHere), hasLength(1));
    expect(
      fragments.every((f) => identical(f.container, fragments.first.container)),
      isTrue,
    );
  });

  test('窄卡片内部的媒体查询仍以阅读视口判断', () async {
    final source = await openCssChapter(
      body: '<div class="card"><p>正文</p></div>',
      css:
          '.card { width: 200px; } p { color: blue; } '
          '@media (min-width: 300px) { p { color: red; } }',
      contentWidth: 350,
    );
    final block = (await source.loadChapter(0)).first.slices.first.block;
    expect(block.style!.color.toARGB32(), 0xffff0000);
    expect(block.layout.maxWidth, 200);
  });

  final realBook = File('../../test_corpus/real/zhushen-yuxi.epub');
  test('诸神愚戏第六章：完整卡片、效果容器及不越界的评级表', () async {
    final source = await EpubChapterSource.open(
      realBook.readAsBytesSync(),
      contentWidth: 350,
      contentHeight: 800,
      verifyCrc: false,
    );
    final pages = await source.loadChapter(32);
    final blocks = <PageBlock>{
      for (final page in pages)
        for (final slice in page.slices) slice.block,
    };
    final name = blocks.firstWhere(
      (block) => block.layout.lines
          .expand((line) => line.inlineBoxes)
          .any(
            (box) => (box.spec.payload! as PageBlock).layout.text == '【恐惧养料】',
          ),
    );
    final description = blocks.firstWhere(
      (b) => b.layout.text.startsWith('你可以吸收周围的恐惧情绪'),
    );
    expect(name.containers, hasLength(3));
    expect(
      identical(
        name.containers.last.container,
        description.containers.last.container,
      ),
      isTrue,
    );
    expect(name.style!.borders.hasBorder, isFalse);
    expect(description.style!.borders.hasBorder, isFalse);
    for (final block in blocks.where((b) => b.table != null)) {
      expect(
        block.table!.tableWidth + block.style!.margin.horizontal,
        lessThanOrEqualTo(source.contentWidth + 0.01),
      );
    }
    expect(
      blocks
          .expand((block) => block.containers)
          .every((fragment) => fragment.container.cloneDecoration),
      isTrue,
    );
    for (final page in pages) {
      expect(page.usedHeight, lessThanOrEqualTo(source.contentHeight + 0.01));
      final first = page.slices.first;
      final last = page.slices.last;
      final top = first.block.containers
          .where((fragment) => !fragment.startsHere || first.continuesBefore)
          .fold(
            0.0,
            (sum, fragment) =>
                sum +
                fragment.container.style.padding.top +
                fragment.container.style.borders.top.width,
          );
      final bottom = last.block.containers
          .where((fragment) => !fragment.endsHere || last.continuesAfter)
          .fold(
            0.0,
            (sum, fragment) =>
                sum +
                fragment.container.style.padding.bottom +
                fragment.container.style.borders.bottom.width,
          );
      expect(first.leadingExtent, greaterThanOrEqualTo(top));
      expect(last.trailingExtent, greaterThanOrEqualTo(bottom));
      expect(last.block.breakAfterAvoid, isFalse, reason: '道具或效果标题不得孤立在页底');
    }
    int stableExtent(double value) => (value * 1000000).round();
    List<Object> geometry(List<PageContent> result) => [
      for (final page in result)
        [
          stableExtent(page.usedHeight),
          for (final slice in page.slices)
            [
              slice.block.layout.text,
              slice.startLine,
              slice.endLine,
              stableExtent(slice.height),
              stableExtent(slice.leadingExtent),
              stableExtent(slice.trailingExtent),
            ],
        ],
    ];
    source.clearPaginationCache();
    final replayed = await source.loadChapter(32);
    expect(
      geometry(replayed),
      geometry(pages),
      reason: '清页缓存后的索引重放必须保留续框占高与分页边界',
    );
  }, skip: !realBook.existsSync());

  test('诸神愚戏画廊一：图片中心落在正文中心', () async {
    final source = await EpubChapterSource.open(
      realBook.readAsBytesSync(),
      contentWidth: 344,
      contentHeight: 800,
      verifyCrc: false,
    );
    final page = (await source.loadChapter(20)).first;
    final image = page.slices
        .map((slice) => slice.block)
        .firstWhere(
          (block) =>
              block.layout.text.isEmpty && block.style?.backgroundImage != null,
        );
    final width = image.style!.width!.resolve(344)!;
    expect(image.style!.margin.left + width / 2, closeTo(172, 0.01));
  }, skip: !realBook.existsSync());
}
