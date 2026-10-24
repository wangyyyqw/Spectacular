import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/text_layout.dart';

/// Ahem 16px/1.5：每字宽 16、行高 24。
ComputedStyle _style({String? whiteSpace, String? display}) =>
    ComputedStyle(<String, String>{
      'font-size': '16px',
      'line-height': '1.5',
      'font-family': 'Ahem',
      'white-space': ?whiteSpace,
      'display': ?display,
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

  test('nowrap：单行且宽度超过约束', () {
    final layout = _layout('aaaaaaaa', _style(whiteSpace: 'nowrap'));
    expect(layout.lineCount, 1);
    expect(layout.width, closeTo(128, 0.01));
    expect(layout.lines.single.width, closeTo(128, 0.01));
  });

  test('pre：保留硬换行且不软换行', () {
    final layout = _layout('a\nb', _style(whiteSpace: 'pre'));
    expect(layout.lineCount, 2);
    expect(layout.lines[0].end, 1);
    expect(layout.lines[1].start, 2);

    final long = _layout('aaaaaaaa', _style(whiteSpace: 'pre'));
    expect(long.lineCount, 1);
    expect(long.width, closeTo(128, 0.01));
  });

  test('pre-wrap：保留空白但允许软换行', () {
    final layout = _layout('aaaaaaaa', _style(whiteSpace: 'pre-wrap'));
    expect(layout.lineCount, greaterThan(1));
  });

  test('pre-line：允许软换行', () {
    final layout = _layout('aaaaaaaa', _style(whiteSpace: 'pre-line'));
    expect(layout.lineCount, greaterThan(1));
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
