import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/layout/paginator.dart';

import 'support/css_chapter_book.dart';

/// `position: absolute / fixed` 章节源接线（W18）。
///
/// 章节源只负责：摘出流（不推进 y、不计页高）、按声明宽测量、把
/// `resolveAbsoluteBox` 的 left/top 写进 `PageBlock.absoluteLeft/Top`
///（都 auto 时留空 → 分页层回退静态位置）；right/bottom 残留由分页层
/// 用真实页高解算。`fixed` 分页后每页追加一份覆盖切片。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<List<PageContent>> pagesOf(
    String body, {
    double contentWidth = 350,
    double contentHeight = 800,
  }) async {
    final source = await openCssChapter(
      body: body,
      css: 'body { margin: 0; padding: 0; font-size: 17px; } '
          'p { margin: 6px 0; line-height: 1.6; } '
          '.abs { position: absolute; top: 12px; left: 220px; width: 90px; } '
          '.abs2 { position: absolute; right: 12px; bottom: 16px; '
          'width: 80px; } '
          '.abs3 { position: absolute; width: 120px; } '
          '.fix { position: fixed; left: 10px; bottom: 8px; width: 60px; }',
      contentWidth: contentWidth,
      contentHeight: contentHeight,
    );
    return source.loadChapter(0);
  }

  Future<List<PageBlockSlice>> slicesOf(
    String body, {
    double contentWidth = 350,
    double contentHeight = 800,
  }) async {
    final source = await openCssChapter(
      body: body,
      css: 'body { margin: 0; padding: 0; font-size: 17px; } '
          'p { margin: 6px 0; line-height: 1.6; } '
          '.abs { position: absolute; top: 12px; left: 220px; width: 90px; } '
          '.abs2 { position: absolute; right: 12px; bottom: 16px; '
          'width: 80px; } '
          '.abs3 { position: absolute; width: 120px; } '
          '.fix { position: fixed; left: 10px; bottom: 8px; width: 60px; }',
      contentWidth: contentWidth,
      contentHeight: contentHeight,
    );
    final pages = await source.loadChapter(0);
    return [for (final page in pages) ...page.slices];
  }

  /// 块之前的流游标（非覆盖切片高度之和）。
  double flowCursorOf(List<PageBlockSlice> slices, String prefix) {
    var flow = 0.0;
    for (final slice in slices) {
      if (slice.block.layout.text.startsWith(prefix)) {
        return flow;
      }
      if (!slice.overlay) {
        flow += slice.height;
      }
    }
    throw StateError('找不到 $prefix');
  }

  PageBlockSlice blockOf(List<PageBlockSlice> slices, String prefix) =>
      slices.firstWhere(
        (slice) => slice.block.layout.text.startsWith(prefix),
        orElse: () => throw StateError('找不到块 $prefix'),
      );

  test('top/left 定位：块矩形 = (220, 12)，且不占流高', () async {
    final withAbs = await slicesOf(
      '<p>前一段</p><div class="abs">绝对定位块</div><p>后一段</p>',
    );
    final abs = blockOf(withAbs, '绝对定位块');
    expect(abs.absoluteTop, 12);
    expect(abs.leftInset, 220);
    expect(abs.overlay, isTrue, reason: '绝对定位走覆盖切片');
    final plain = await slicesOf('<p>前一段</p><p>后一段</p>');
    // 不占流：后一段的流位置与没有绝对定位块时一致。
    // 流游标：只累加非覆盖切片（绝对定位走 overlay，不计流高）。
    double flowTopOf(List<PageBlockSlice> slices, String prefix) {
      var flow = 0.0;
      for (final slice in slices) {
        if (slice.block.layout.text.startsWith(prefix)) {
          return flow;
        }
        if (!slice.overlay) {
          flow += slice.height;
        }
      }
      throw StateError('找不到 $prefix');
    }

    expect(
      flowTopOf(withAbs, '后一段'),
      closeTo(flowTopOf(plain, '后一段'), 0.01),
      reason: '绝对定位不推进流',
    );
  });

  test('right/bottom 定位：x = 版心 − right − 宽，底边距页底 bottom', () async {
    final slices = await slicesOf(
      '<p>一段正文</p><div class="abs2">右下角</div>',
      contentHeight: 800,
    );
    final abs = blockOf(slices, '右下角');
    expect(abs.leftInset, closeTo(258, 0.01), reason: '350 − 12 − 80');
    // bottom 由分页层按真实页高解算：块底 = 页高 − 16。
    final bottom = abs.absoluteTop! + abs.block.height;
    expect(bottom, closeTo(800 - 16, 0.5));
  });

  test('左右上下都 auto：回退静态位置（本来会被排到的位置）', () async {
    final slices = await slicesOf(
      '<p>前一段</p><div class="abs3">静态位置块</div><p>后一段</p>',
    );
    final abs = blockOf(slices, '静态位置块');
    expect(abs.absoluteTop, isNotNull);
    expect(abs.leftInset, 0, reason: '静态位置 x 取包含块左缘');
    // 静态 y = 该块本来会被排到的位置（前一段之后的流游标，不含覆盖切片）。
    expect(
      abs.absoluteTop,
      closeTo(flowCursorOf(slices, '静态位置块'), 1),
      reason: '静态位置接在流游标处',
    );
  });

  test('fixed：每页重复、位置相同、不占流高', () async {
    const longBody =
        '<p>第一段文字比较长，用于把内容铺开到两页以上，方便观察固定定位块'
        '是否在每一页都出现。</p>'
        '<p>第二段文字接着写，继续拉长内容，让分页至少产生三页，'
        '这样固定定位的重复性才能被观察到。</p>'
        '<p>第三段文字同样需要一定长度，避免整章只有一页而看不出重复。</p>'
        '<p>第四段文字收尾，重量与前面几段相当，保证章节内容足够高。</p>'
        '<div class="fix">固定块</div>';
    final withFixedPages = await pagesOf(
      longBody,
      contentWidth: 200,
      contentHeight: 120,
    );
    final plainPages = await pagesOf(
      longBody.replaceAll('<div class="fix">固定块</div>', ''),
      contentWidth: 200,
      contentHeight: 120,
    );
    expect(plainPages.length, greaterThanOrEqualTo(2), reason: '需要多页');
    expect(
      withFixedPages.length,
      plainPages.length,
      reason: '固定定位不占流高：页数不变',
    );
    final fixedTops = <double>{};
    for (final page in withFixedPages) {
      final fixed = page.slices.where(
        (slice) => slice.block.layout.text.startsWith('固定块'),
      );
      expect(fixed, hasLength(1), reason: '每页恰好一份固定块');
      fixedTops.add(fixed.single.absoluteTop!);
      expect(fixed.single.leftInset, 10, reason: 'left: 10px');
    }
    expect(fixedTops, hasLength(1), reason: '每页位置相同');
  });
}
