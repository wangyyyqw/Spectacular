import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/text_layout.dart';

/// Ahem 16px/1.5：每字宽 16、行高 24。
ComputedStyle _style({
  String? whiteSpace,
  String? display,
  String? textAlign,
}) => ComputedStyle(<String, String>{
  'font-size': '16px',
  'line-height': '1.5',
  'font-family': 'Ahem',
  'white-space': ?whiteSpace,
  'display': ?display,
  'text-align': ?textAlign,
});

TextLayoutResult _layout(
  String text,
  ComputedStyle style, {
  double width = 48,
}) => TextLayoutEngine.layout(text: text, style: style, maxWidth: width);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('normal：窄宽下软换行', () {
    final layout = _layout('aaaaaaaa', _style());
    expect(layout.lineCount, greaterThan(1));
    expect(layout.lines.every((line) => line.width <= 48 + 0.01), isTrue);
  });

  test('nowrap：单行且宽度超过约束（maxWidth 仍是有限内容宽）', () {
    final layout = _layout('aaaaaaaa', _style(whiteSpace: 'nowrap'));
    expect(layout.lineCount, 1);
    expect(layout.width, closeTo(128, 0.01));
    expect(layout.lines.single.width, closeTo(128, 0.01));
    expect(layout.maxWidth, closeTo(48, 0.01), reason: '不再记成 Infinity');
  });

  test('pre：保留硬换行且不软换行', () {
    final layout = _layout('a\nb', _style(whiteSpace: 'pre'));
    expect(layout.lineCount, 2);
    expect(layout.lines[0].end, 1);
    expect(layout.lines[1].start, 2);

    final long = _layout('aaaaaaaa', _style(whiteSpace: 'pre'));
    expect(long.lineCount, 1);
    expect(long.width, closeTo(128, 0.01));
    expect(long.maxWidth, closeTo(48, 0.01), reason: '不软换行也按内容宽记账');
  });

  test('pre：按内容宽对齐（不软换行不再退化为 0 余量）', () {
    // Ahem 16px："ab" = 32，内容宽 48 → 居中偏移 8。
    final layout = _layout(
      'ab',
      _style(whiteSpace: 'pre', textAlign: 'center'),
      width: 200,
    );
    expect(layout.lines.single.offsetX, closeTo(84, 0.01));
    expect(layout.maxWidth, closeTo(200, 0.01));
  });

  test('center：行首 NBSP 不参与可见文字居中计算', () {
    // Ahem 16px：NBSP + "ab" = 48，内容宽 80。忽略 NBSP 后，
    // 可见的 "ab" 应从左缘 8px 处开始才能居中。
    final layout = _layout('\u00A0ab', _style(textAlign: 'center'), width: 80);
    expect(layout.lines.single.width, closeTo(48, 0.01));
    expect(layout.lines.single.offsetX, closeTo(8, 0.01));
  });

  test('pre-wrap：保留空白但允许软换行', () {
    final layout = _layout('aaaaaaaa', _style(whiteSpace: 'pre-wrap'));
    expect(layout.lineCount, greaterThan(1));
  });

  test('pre-line：允许软换行', () {
    final layout = _layout('aaaaaaaa', _style(whiteSpace: 'pre-line'));
    expect(layout.lineCount, greaterThan(1));
  });

  test('pre：换行符是硬断行，且保留连续空格', () {
    // Ahem 16px：每字 16 宽。"ab  cd" = 6 字 = 96；只留一个空格会少 16。
    final spacing = _layout('ab  cd', _style(whiteSpace: 'pre'), width: 200);
    expect(spacing.lineCount, 1);
    expect(spacing.width, closeTo(96, 0.01), reason: '两个连续空格都保留');

    // 用例 06 的形状：pre 文本带换行符 → 逐行硬断，不软换行。
    final broken = _layout('ab  cd\nef', _style(whiteSpace: 'pre'));
    expect(broken.lineCount, 2);
    expect(broken.lines[0].isHardBreak, isTrue);
    expect(broken.lines[0].width, closeTo(96, 0.01));
    expect(broken.lines[0].end, 6, reason: '行尾停在换行符之前');
    expect(broken.lines[1].start, 7, reason: '下一行跳过换行符');
    expect(broken.lines[1].width, closeTo(32, 0.01));
    expect(broken.height, closeTo(48, 0.01));
  });

  test('pre：连续换行产生空行', () {
    final layout = _layout('a\n\nb', _style(whiteSpace: 'pre'));
    expect(layout.lineCount, 3);
    expect(layout.lines[1].start, layout.lines[1].end, reason: '第二行是空行');
    expect(layout.height, closeTo(72, 0.01));
  });

  test('pre-wrap：硬断行与软换行共存，空格保留', () {
    final hard = _layout('aa\nbbbb', _style(whiteSpace: 'pre-wrap'), width: 48);
    expect(hard.lineCount, 3, reason: '先按换行符硬断，再按宽度软换行');
    expect(hard.lines[0].isHardBreak, isTrue);
    expect(hard.lines[0].end, 2);

    final spaces = _layout('a  b', _style(whiteSpace: 'pre-wrap'), width: 200);
    expect(spaces.width, closeTo(64, 0.01));
  });

  test('pre-line：换行符保留为硬断行', () {
    final layout = _layout('ab\ncd', _style(whiteSpace: 'pre-line'));
    expect(layout.lineCount, 2);
    expect(layout.lines[0].isHardBreak, isTrue);
    expect(layout.lines[0].width, closeTo(32, 0.01));
    expect(layout.lines[1].width, closeTo(32, 0.01));
  });

  test('display:none 的块不占位', () {
    final visible = TextLayoutEngine.layout(
      text: 'aa',
      style: _style(),
      maxWidth: 200,
    );
    final hidden = TextLayoutEngine.layout(
      text: 'aa\nbb',
      style: _style(display: 'none'),
      maxWidth: 200,
    );

    final onlyVisible = Paginator(pageHeight: 400).measureChapter(
      blocks: [PageBlock(layout: visible, style: _style())],
    );
    expect(onlyVisible.totalHeight, closeTo(24, 0.01));

    final mixed = Paginator(pageHeight: 400).measureChapter(
      blocks: [
        PageBlock(
          layout: hidden,
          style: _style(display: 'none'),
        ),
        PageBlock(layout: visible, style: _style()),
      ],
    );
    expect(mixed.totalHeight, closeTo(24, 0.01), reason: 'none 块不计入总高');
    expect(mixed.pages.single.usedHeight, closeTo(24, 0.01));
    expect(mixed.pages.single.slices, hasLength(1));

    final onlyHidden = Paginator(pageHeight: 400).measureChapter(
      blocks: [
        PageBlock(
          layout: hidden,
          style: _style(display: 'none'),
        ),
      ],
    );
    expect(onlyHidden.pages, isEmpty, reason: '只有 none 块时没有页面');
  });

  test('visibility:hidden 保持布局尺寸不变', () {
    final visible = _layout('aa', _style());
    final hidden = _layout('aa', _style(display: 'block'));
    expect(hidden.lineCount, visible.lineCount);
    expect(hidden.width, visible.width);
    expect(hidden.height, visible.height);
    expect(_style().visibility, CssVisibility.visible);
    expect(
      ComputedStyle(const {'visibility': 'hidden'}).visibility,
      CssVisibility.hidden,
    );
  });
}
