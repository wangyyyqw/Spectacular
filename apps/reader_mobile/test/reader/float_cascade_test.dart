import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/layout/float_occupancy.dart';
import 'package:reader_core/layout/paginator.dart';

import 'support/css_chapter_book.dart';

/// 浮动识别（f）：`float` 走级联后的计算样式。
///
/// 旧实现只看内联 `style="float:…"` 与 `align` 属性，`.f { float: left }`
/// 这类 class 规则完全识别不到，绕排分支从未进入。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<List<PageBlockSlice>> slicesOf(
    String body,
    String css, {
    double contentWidth = 300,
  }) async {
    final source = await openCssChapter(
      body: body,
      css: css,
      contentWidth: contentWidth,
      contentHeight: 800,
    );
    final pages = await source.loadChapter(0);
    return [for (final page in pages) ...page.slices];
  }

  test('class 规则里的 float: left 被识别，正文右侧绕排', () async {
    final slices = await slicesOf(
      '<div class="f">左浮动</div>'
          '<p>浮动右侧的文字绕排，需要足够长以便观察效果，继续补充一些文字。</p>',
      '.f { float: left; width: 100px; background-color: #cce; }',
    );
    final floated = slices.where((slice) => slice.block.floatSide != null);
    expect(floated, hasLength(1), reason: 'class 里的 float 必须被识别');
    expect(floated.single.block.floatSide, FloatSide.left);
    expect(floated.single.overlay, isTrue, reason: '浮动块按覆盖切片绘制');

    final paragraph = slices.firstWhere(
      (slice) => slice.block.layout.text.startsWith('浮动右侧'),
    );
    // 浮动宽 100 + 无外边距补的呼吸位：首行从浮动右侧开始。
    expect(paragraph.block.layout.lines.first.offsetX, greaterThanOrEqualTo(100));
  });

  test('右浮动贴右缘，正文在其左侧绕排', () async {
    final slices = await slicesOf(
      '<div class="r">右浮动</div>'
          '<p>左侧文字绕排，需要足够长以便观察效果，继续补充一些文字。</p>',
      '.r { float: right; width: 90px; margin-left: 8px; }',
    );
    final floated = slices.firstWhere(
      (slice) => slice.block.floatSide != null,
    );
    expect(floated.block.floatSide, FloatSide.right);
    // 右浮动边框盒贴右缘：300 - 90 = 210（绘制层会另加 margin.left）。
    expect(floated.leftInset, closeTo(210, 8));
    final paragraph = slices.firstWhere(
      (slice) => slice.block.layout.text.startsWith('左侧文字'),
    );
    expect(
      paragraph.block.layout.lines.first.width,
      lessThan(300),
      reason: '右侧被浮动占用，行宽应小于整行',
    );
  });

  test('clear: both 的块从浮动底边之下开始', () async {
    final slices = await slicesOf(
      '<div class="f">左浮动</div>'
          '<p class="cl">清除之后从下方开始，观察起始位置是否在浮动底边之下。</p>',
      '.f { float: left; width: 80px; height: 60px; } .cl { clear: both; }',
    );
    final floated = slices.firstWhere(
      (slice) => slice.block.floatSide != null,
    );
    final cleared = slices.firstWhere(
      (slice) => slice.block.layout.text.startsWith('清除之后'),
    );
    expect(floated.block.height, closeTo(60, 0.01));
    // 清除后整行可用：所有行都不带浮动造成的左偏移。
    expect(
      cleared.block.layout.lines.map((line) => line.offsetX),
      everyElement(0),
      reason: 'clear: both 之后不应再绕排',
    );
  });
}
