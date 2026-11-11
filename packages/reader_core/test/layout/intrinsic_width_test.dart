import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/box_model.dart';
import 'package:reader_core/layout/intrinsic_widths.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/layout/text_layout_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('内在宽度先选内容宽，再扣可用盒空间并应用 min/max', () {
    const widths = IntrinsicWidths(minContent: 90, maxContent: 240);
    BoxModel model(String width, [Map<String, String> extra = const {}]) =>
        BoxModel.fromStyle(
          ComputedStyle({
            'width': width,
            'padding': '10px',
            'border': '2px solid',
            'margin': '0 8px',
            ...extra,
          }),
          containingWidth: 200,
        );
    expect(
      model('min-content').resolveContentWidth(200, intrinsicWidths: widths),
      90,
    );
    expect(
      model('max-content').resolveContentWidth(200, intrinsicWidths: widths),
      240,
    );
    expect(
      model('fit-content').resolveContentWidth(200, intrinsicWidths: widths),
      160,
    );
    expect(
      model('fit-content').resolveContentWidth(80, intrinsicWidths: widths),
      90,
    );
    expect(
      model('fit-content').resolveContentWidth(500, intrinsicWidths: widths),
      240,
    );
    expect(
      model('max-content', {
        'min-width': '180px',
        'max-width': '120px',
      }).resolveContentWidth(200, intrinsicWidths: widths),
      180,
    );
    expect(
      model('max-content', {
        'box-sizing': 'border-box',
      }).resolveContentWidth(200, intrinsicWidths: widths),
      240,
    );
    expect(
      model('max-content', {
        'box-sizing': 'border-box',
        'max-width': '150px',
      }).resolveContentWidth(200, intrinsicWidths: widths),
      126,
    );
  });

  test('预测值不会改变旧 auto/像素路径；未提供测量时保留旧可用宽', () {
    const widths = IntrinsicWidths(minContent: 90, maxContent: 240);
    for (final width in ['auto', '140px', 'min-content']) {
      final model = BoxModel.fromStyle(
        ComputedStyle({'width': width, 'padding': '10px'}),
        containingWidth: 200,
      );
      final expected = width == '140px' ? 140 : 180;
      expect(model.resolveContentWidth(200), expected);
      if (width != 'min-content') {
        expect(
          model.resolveContentWidth(200, intrinsicWidths: widths),
          expected,
        );
      }
    }
  });

  test('最小内容宽保留英文词与硬换行，按现有字体度量 CJK', () async {
    final style = ComputedStyle({'font-size': '16px', 'font-family': 'Ahem'});
    Future<double> width(String text) =>
        TextLayoutEngine.minContentTextWidthAsync(text: text, style: style);
    expect(await width('longword short'), closeTo(128, .01));
    expect(await width('longword\nshort'), closeTo(128, .01));
    expect(await width('天地玄黄'), closeTo(16, .01));
    expect(await width('right/bottom'), closeTo(192, .01));
  });

  test('anywhere 计入最小宽，紧急 break-word 不计入；混合字号实际测量', () async {
    Future<double> width(Map<String, String> extra) =>
        TextLayoutEngine.minContentTextWidthAsync(
          text: 'abcdefgh',
          style: ComputedStyle({'font-size': '16px', ...extra}),
        );
    expect(await width({'overflow-wrap': 'anywhere'}), closeTo(16, .01));
    expect(await width({'overflow-wrap': 'break-word'}), closeTo(128, .01));
    expect(await width({'white-space': 'nowrap'}), closeTo(128, .01));
    final style = ComputedStyle({'font-size': '16px'});
    expect(
      await TextLayoutEngine.minContentTextWidthAsync(
        text: 'ab cd',
        style: style,
        runs: [
          StyledRun(
            start: 3,
            end: 5,
            style: style.withTypography(fontSize: 24),
          ),
        ],
      ),
      closeTo(48, .01),
    );
  });

  test('内在尺寸预测可在断点遍历取消，后续测量仍正常', () async {
    final style = ComputedStyle({'font-size': '16px', 'hyphens': 'auto'});
    var checks = 0;
    await expectLater(
      TextLayoutEngine.minContentTextWidthAsync(
        text: List.filled(300, 'extraordinary').join(' '),
        style: style,
        checkpoint: () async {
          if (++checks == 6) throw StateError('取消内在尺寸测量');
        },
      ),
      throwsStateError,
    );
    expect(checks, 6);
    expect(
      await TextLayoutEngine.minContentTextWidthAsync(
        text: 'abc',
        style: style,
      ),
      closeTo(48, .01),
    );
  });

  test('测量副本保留禁则与软连字符，缩进只影响首个不可断区间', () async {
    Future<double> width(String text, [Map<String, String> extra = const {}]) =>
        TextLayoutEngine.minContentTextWidthAsync(
          text: text,
          style: ComputedStyle({
            'font-family': 'Ahem',
            'font-size': '16px',
            ...extra,
          }),
        );
    expect(await width('「天」地'), closeTo(48, .01));
    expect(await width('天\u200B地'), closeTo(16, .01));
    expect(await width('ab\u00ADcd', {'hyphens': 'manual'}), closeTo(48, .01));
    expect(await width('AB CD', {'text-indent': '32px'}), closeTo(64, .01));
    expect(
      await width('A BBBBBBBB', {'text-indent': '32px'}),
      closeTo(128, .01),
    );
    expect(await width('ABC', {'text-indent': '-16px'}), closeTo(32, .01));
  });

  test('内在容器窄宽与正文下限分别缓存，同步异步返回相同几何', () async {
    final style = ComputedStyle({'font-size': '16px', 'font-family': 'Ahem'});
    final cache = TextLayoutCache();
    final prose = cache.layout(text: '天地', style: style, maxWidth: 16);
    final narrow = await cache.layoutAsync(
      text: '天地',
      style: style,
      maxWidth: 16,
      preserveContentWidth: true,
    );
    final reused = cache.layout(
      text: '天地',
      style: style,
      maxWidth: 16,
      preserveContentWidth: true,
    );
    expect(prose.maxWidth, 48);
    expect(prose.lineCount, 1);
    expect(narrow.maxWidth, 16);
    expect(narrow.lineCount, 2);
    expect(reused.maxWidth, narrow.maxWidth);
    expect(
      reused.lines.map((line) => line.end),
      narrow.lines.map((line) => line.end),
    );
  });
}
