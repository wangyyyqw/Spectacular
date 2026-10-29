import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/layout/paginator.dart';

import 'support/css_chapter_book.dart';

/// `position: relative`（W17）：视觉偏移、不占流。
///
/// 章节源把 `left` 折算成「左右外边距等量搬移」（内容宽不变，盒子与文字
/// 一起右移），把 `top` 折算成「段前距 +top / 段后距 −top」（块的流内占高
/// 不变，内容与盒子一起下移）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<List<PageBlockSlice>> slicesOf(String css) async {
    final source = await openCssChapter(
      body: '<p class="before">前一段</p>'
          '<p class="rel">相对定位的段落，用来观察视觉偏移。</p>'
          '<p class="after">后一段</p>',
      css: 'p { margin: 6px 0; line-height: 1.5; } $css',
      contentWidth: 320,
      contentHeight: 700,
    );
    final pages = await source.loadChapter(0);
    return [for (final page in pages) ...page.slices];
  }

  /// 切片在流中的块顶（= 之前所有切片高之和 + 本切片段前距）。
  ({double flowTop, double leading}) flowOf(
    List<PageBlockSlice> slices,
    String textPrefix,
  ) {
    var flow = 0.0;
    for (final slice in slices) {
      if (slice.block.layout.text.startsWith(textPrefix)) {
        return (flowTop: flow, leading: slice.leadingExtent);
      }
      if (!slice.overlay) {
        flow += slice.height;
      }
    }
    throw StateError('找不到块 $textPrefix');
  }

  test('left: 18px 让块与行文字右移 18，后续块位置不变', () async {
    final plain = await slicesOf('');
    final shifted = await slicesOf('.rel { position: relative; left: 18px; }');
    final plainRel = shifted.firstWhere(
      (slice) => slice.block.layout.text.startsWith('相对定位'),
    );
    expect(plainRel.leftInset, closeTo(18, 0.01));
    expect(plainRel.block.style!.margin.left, 0, reason: '盒子声明宽不变');
    // 后续块在两种书里流位置一致（相对定位不占流）。
    final plainAfter = flowOf(plain, '后一段');
    final shiftedAfter = flowOf(shifted, '后一段');
    expect(shiftedAfter.flowTop, closeTo(plainAfter.flowTop, 0.01));
    expect(shiftedAfter.leading, closeTo(plainAfter.leading, 0.01));
  });

  test('top: 6px 让块顶下移 6，块的流内占高与后续块位置不变', () async {
    final plain = await slicesOf('');
    final shifted = await slicesOf('.rel { position: relative; top: 6px; }');
    final plainRel = flowOf(plain, '相对定位');
    final shiftedRel = flowOf(shifted, '相对定位');
    // 块顶 = 流位置 + 段前距。
    expect(
      shiftedRel.flowTop + shiftedRel.leading,
      closeTo(plainRel.flowTop + plainRel.leading + 6, 0.01),
    );
    // 流内占高不变：后续块的内容位置一致（下移量由「下一个块段前距抵扣」
    // 吸收，所以块顶相同、流游标起点相差这一段）。
    final plainAfter = flowOf(plain, '后一段');
    final shiftedAfter = flowOf(shifted, '后一段');
    expect(
      shiftedAfter.flowTop + shiftedAfter.leading,
      closeTo(plainAfter.flowTop + plainAfter.leading, 0.01),
    );
  });

  test('left/top 同时生效（left 百分比按版心宽解算）', () async {
    final plain = await slicesOf('');
    final slices = await slicesOf(
      '.rel { position: relative; left: 10%; top: 4px; }',
    );
    final rel = slices.firstWhere(
      (slice) => slice.block.layout.text.startsWith('相对定位'),
    );
    expect(rel.leftInset, closeTo(32, 0.5), reason: '10% × 320');
    final plainRel = flowOf(plain, '相对定位');
    final shiftedRel = flowOf(slices, '相对定位');
    expect(
      shiftedRel.leading - plainRel.leading,
      closeTo(4, 0.01),
      reason: 'top 折算成段前距增量',
    );
  });

  test('position: static 不受影响', () async {
    final plain = await slicesOf('');
    final rel = plain.firstWhere(
      (slice) => slice.block.layout.text.startsWith('相对定位'),
    );
    expect(rel.leftInset, 0);
  });

  test('相对定位后的绝对定位块不吞掉后续段前抵扣', () async {
    final plain = await slicesOf('');
    final shiftedSource = await openCssChapter(
      body: '<p class="before">前一段</p>'
          '<p class="rel">相对定位的段落，用来观察视觉偏移。</p>'
          '<div class="abs">绝对定位</div>'
          '<p class="after">后一段</p>',
      css: '''
        p { margin: 6px 0; line-height: 1.5; }
        .rel { position: relative; top: 6px; }
        .abs { position: absolute; top: 20px; left: 20px; }
      ''',
      contentWidth: 320,
      contentHeight: 700,
    );
    final shifted = [
      for (final page in await shiftedSource.loadChapter(0)) ...page.slices,
    ];
    final expected = flowOf(plain, '后一段');
    final actual = flowOf(shifted, '后一段');
    expect(
      actual.flowTop + actual.leading,
      closeTo(expected.flowTop + expected.leading, 0.01),
      reason: '相对定位偏移不占流，绝对定位块也不影响后续流位置',
    );
  });
}
