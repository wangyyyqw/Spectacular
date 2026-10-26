import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/layout/paginator.dart';

import 'support/css_chapter_book.dart';

/// 浮动块的静态位置（38-float-clear 残差）：浮动框的外边距盒顶不得高于
/// 所在行盒顶——定位要算「当前位置 + 下一个在流块段前距」，再叠加自己的
/// margin-top；浮动的 margin 本身不参与相邻折叠，也不能被折叠挪走。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<List<PageBlockSlice>> slicesOf(String body, String css) async {
    final source = await openCssChapter(
      body: body,
      css: css,
      contentWidth: 320,
      contentHeight: 800,
    );
    final pages = await source.loadChapter(0);
    return [for (final page in pages) ...page.slices];
  }

  test('浮动块落在「行盒顶 + 自身 margin-top」', () async {
    final slices = await slicesOf(
      '<p>前一段</p>'
          '<p class="fl">浮动段落本身较长文字，用于观察块级元素浮动后的位置。</p>'
          '<p>紧随浮动之后的正文段落，用于确定行盒顶的位置并观察绕排。</p>',
      'p { margin: 16px 0; } .fl { float: left; width: 90px; }',
    );
    final floated = slices.firstWhere(
      (slice) => slice.block.floatSide != null,
    );
    // 浮动之前的在流块总占高 → 浮动块处；再往后第一个在流块的块顶
    //（= 行盒顶）= 累计占高 + 它的段前距（相邻折叠后的 16 落在这里）。
    var flow = 0.0;
    var lineBoxTop = 0.0;
    var seenFloat = false;
    for (final slice in slices) {
      if (identical(slice, floated)) {
        seenFloat = true;
        continue;
      }
      if (slice.overlay) {
        continue;
      }
      if (seenFloat) {
        lineBoxTop = flow + slice.leadingExtent;
        break;
      }
      flow += slice.height;
    }
    expect(
      floated.absoluteTop,
      closeTo(lineBoxTop + 16, 0.5),
      reason: '浮动边框盒顶 = 行盒顶 + 自身 margin-top 16（浮动 margin 不折叠）',
    );
  });

  test('浮动不参与相邻 margin 折叠（两侧段距不被挪走）', () async {
    final slices = await slicesOf(
      '<p>前一段</p>'
          '<div class="fl">浮动块</div>'
          '<p>后一段</p>',
      'p { margin: 20px 0; } .fl { float: left; width: 80px; }',
    );
    final flow = slices.where((slice) => !slice.overlay).toList();
    expect(flow, hasLength(2));
    // 两个在流块仍按相邻折叠：段距取 max(20, 20) = 20，而不是 40。
    final leading = flow[1].leadingExtent;
    final trailing = flow[0].trailingExtent;
    expect(leading + trailing, closeTo(20, 0.5));
  });

  test('页首浮动与首个在流块的行首对齐（叠加自身 margin）', () async {
    final slices = await slicesOf(
      '<div class="fl">浮动</div><p>正文首段</p>',
      'p { margin: 12px 0; } .fl { float: left; width: 60px; }',
    );
    final floated = slices.firstWhere(
      (slice) => slice.block.floatSide != null,
    );
    // 首个在流块的段前距 12 塌陷到正文顶部；浮动再叠加自身 margin（0）。
    expect(floated.absoluteTop, closeTo(12, 0.5));
  });
}
