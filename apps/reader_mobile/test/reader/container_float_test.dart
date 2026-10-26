import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/layout/float_occupancy.dart';
import 'package:reader_core/layout/paginator.dart';

import 'package:reader_mobile/reader/epub_chapter_source.dart';

import 'support/css_chapter_book.dart';

/// 容器级浮动传导（W12）：flat 管线把容器拆成子块后，容器上的
/// `float`/`width` 要像 bleed 一样传给子块，整组当一个浮动盒排布。
/// 真书对应：zhushen-yuxi 的 `.dk-toc-item { float: left; width: 48% }`
/// 双列目录（spine 3）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<List<PageBlockSlice>> slicesOf(
    String body,
    String css, {
    double contentWidth = 320,
  }) async {
    final source = await openCssChapter(
      body: body,
      css: css,
      contentWidth: contentWidth,
      contentHeight: 900,
    );
    final pages = await source.loadChapter(0);
    return [for (final page in pages) ...page.slices];
  }

  const tocBody =
      '<div class="item"><p class="en">ZERO</p><p class="cn">第零卷 附录</p></div>'
      '<div class="item"><p class="en">ONE</p><p class="cn">第一卷 信仰游戏</p></div>'
      '<div class="item"><p class="en">TWO</p><p class="cn">第二卷 虚无行者</p></div>'
      '<div class="item"><p class="en">THREE</p><p class="cn">第三卷 假面非面</p></div>';
  const tocCss =
      '.item { float: left; width: 48%; margin-right: 2%; margin-bottom: 1em; } '
      '.item p { margin: 0; }';

  test('双列目录：同列内竖向堆叠，第二列 x 右移、y 与首列对齐', () async {
    final slices = await slicesOf(tocBody, tocCss);
    final floats = slices.where((slice) => slice.block.floatSide != null);
    expect(floats, hasLength(8), reason: '4 个容器各 2 个块，全部进浮动');

    final first = slices.firstWhere(
      (slice) => slice.block.layout.text == 'ZERO',
    );
    final secondColumn = slices.firstWhere(
      (slice) => slice.block.layout.text == 'ONE',
    );
    final firstCn = slices.firstWhere(
      (slice) => slice.block.layout.text.startsWith('第零卷'),
    );
    final secondCn = slices.firstWhere(
      (slice) => slice.block.layout.text.startsWith('第一卷'),
    );

    // 同列内堆叠：容器第二段落在第一段下方。
    expect(firstCn.absoluteTop!, greaterThan(first.absoluteTop!));
    // 第二列在第一列右侧（48% 宽 → x ≈ 0.5 版心宽）。
    expect(
      secondColumn.leftInset - first.leftInset,
      greaterThan(140),
      reason: '双列：第二列应右移半版心',
    );
    // 两列块 y 相近（同一行）。
    expect(
      (secondColumn.absoluteTop! - first.absoluteTop!).abs(),
      lessThan(1),
      reason: '两列块 y 应对齐',
    );
    expect((secondCn.absoluteTop! - firstCn.absoluteTop!).abs(), lessThan(1));
    expect(
      secondColumn.block.floatSide,
      FloatSide.left,
      reason: '容器 float 传导给子块',
    );
  });

  test('第二行容器落到首行底边之下（不重叠）', () async {
    final slices = await slicesOf(tocBody, tocCss);
    final secondRow = slices.firstWhere(
      (slice) => slice.block.layout.text == 'TWO',
    );
    final firstRowCn = slices.firstWhere(
      (slice) => slice.block.layout.text.startsWith('第一卷'),
    );
    expect(
      secondRow.absoluteTop!,
      greaterThanOrEqualTo(firstRowCn.absoluteTop! + firstRowCn.height - 0.5),
      reason: '放不下就换行到首行底边之下',
    );
  });

  test('容器浮动里的图片同样收进浮动列（宽按容器内容宽收窄）', () async {
    final slices = await slicesOf(
      '<div class="item"><img src="../Images/a.png" width="300"/></div>',
      '.item { float: left; width: 48%; }',
    );
    final image = slices.firstWhere(
      (slice) => slice.block.layout.text.isEmpty,
    );
    expect(image.block.floatSide, FloatSide.left);
    expect(image.block.layout.width, lessThanOrEqualTo(320 * 0.48 + 0.5));
  });

  test('没有 float 的容器不产生浮动块', () async {
    final slices = await slicesOf(
      '<div class="box"><p>第一段</p><p>第二段</p></div>',
      '.box { width: 48%; } p { margin: 0; }',
    );
    expect(slices.where((slice) => slice.block.floatSide != null), isEmpty);
  });

  test('真书取证：zhushen-yuxi 目录章（spine 3）排成双列', () async {
    // 语料 CSS：`.dk-toc-item { float: left; width: 48%; margin-right: 2% }`
    // ——每个目录项是一个浮动容器，内部两个 <p>（英文名 + 中文卷名）。
    final file = File('../../test_corpus/real/zhushen-yuxi.epub');
    if (!file.existsSync()) {
      return;
    }
    final source = await EpubChapterSource.open(
      file.readAsBytesSync(),
      verifyCrc: false,
    );
    final pages = await source.loadChapter(3);
    final floats = pages
        .expand((page) => page.slices)
        .where((slice) => slice.block.floatSide != null)
        .toList();
    expect(floats.length, greaterThanOrEqualTo(10), reason: '目录项全部进浮动');
    // 双列：至少两个块同一行、x 相差约半版心。
    final firstRow = <double, List<double>>{};
    for (final slice in floats) {
      final y = (slice.absoluteTop! * 10).round() / 10;
      firstRow.putIfAbsent(y, () => <double>[]).add(slice.leftInset);
    }
    final paired = firstRow.values.where((xs) => xs.length >= 2);
    expect(paired, isNotEmpty, reason: '同一行出现两列浮块');
    final columns = paired.first..sort();
    expect(
      columns.last - columns.first,
      greaterThan(140),
      reason: '两列间距约半版心（48% 宽）',
    );
  });

  test('层级更深的块沿用同一浮动组（不会各自成为独立浮块）', () async {
    final slices = await slicesOf(
      '<div class="item"><div class="inner"><p>深层文字一</p>'
          '<p>深层文字二</p></div></div>',
      '.item { float: left; width: 48%; } .inner p { margin: 0; }',
    );
    final blocks = slices.where((slice) => slice.block.floatSide != null);
    expect(blocks, hasLength(2));
    expect(
      blocks.first.block.groupId,
      blocks.last.block.groupId,
      reason: '同一容器的子块共享组号',
    );
    expect(
      blocks.first.block.groupId,
      greaterThanOrEqualTo(500000),
      reason: '容器浮动组号在保留区间',
    );
    expect(
      (blocks.last.absoluteTop! - blocks.first.absoluteTop!).abs(),
      greaterThan(0),
      reason: '组内块竖向堆叠而不是并排',
    );
  });
}
