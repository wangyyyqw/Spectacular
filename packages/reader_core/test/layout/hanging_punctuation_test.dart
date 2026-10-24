import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/line_breaker.dart';

/// P7-18：标点悬挂——`hanging-punctuation: allow-end` 时两端对齐的
/// 非末行行尾句读挂到版心右缘外（justifyExtra = slack + 句读宽）；
/// 默认 none 时输出与现状一致；末行与硬换行不悬挂。
ComputedStyle _style({String? hanging, String align = 'justify', double fontSize = 16}) =>
    ComputedStyle(<String, String>{
      'font-size': '${fontSize}px',
      'line-height': '1.5',
      'font-family': 'Ahem',
      'text-align': align,
      'hanging-punctuation': ?hanging,
    });

TextLayoutResult _layout(String text, double width, ComputedStyle style) =>
    TextLayoutEngine.layout(text: text, style: style, maxWidth: width);

void main() {
  // Ahem 等宽 15px；宽 121 → 8 字/行（121-120=1 slack）。
  // 「中文中文中文中，后续内容」首行 8 字符以句读结尾（实测探针确认）。
  const text = '中文中文中文中，后续内容';
  const width = 121.0;
  final styleBase = _style(fontSize: 15);

  test('默认 none：行尾句读不悬挂（justifyExtra = slack）', () {
    final layout = _layout(text, width, styleBase);
    expect(layout.lineCount, 2, reason: '样本前置：两行');
    final first = layout.lines.first;
    final firstText = text.substring(first.start, first.end);
    expect(firstText.endsWith('，'), isTrue, reason: '样本前置：首行以句读结尾');
    expect(first.isLastLine, isFalse);
    expect(first.isHardBreak, isFalse);
    // slack = 121 - 120 = 1。
    expect(first.justifyExtra, closeTo(1, 0.01));
  });

  test('allow-end：行尾句读悬挂（justifyExtra = slack + 句读宽）', () {
    final layout = _layout(text, width, _style(fontSize: 15, hanging: 'allow-end'));
    final first = layout.lines.first;
    final firstText = text.substring(first.start, first.end);
    expect(firstText.endsWith('，'), isTrue);
    // 句读 advance = 15px（Ahem 全宽）。
    expect(first.justifyExtra, closeTo(1 + 15, 0.01));
    // 末行不悬挂不拉伸。
    expect(layout.lines.last.justifyExtra, 0);
  });

  test('末行与硬换行行不悬挂', () {
    final layout = _layout(
      '中文中文中文中文，\n后续',
      width,
      _style(hanging: 'allow-end'),
    );
    for (final line in layout.lines) {
      final lineText = text.substring(line.start, line.end);
      if (lineText.endsWith('，')) {
        expect(line.isHardBreak || line.isLastLine, isTrue);
        expect(line.justifyExtra, 0, reason: '硬换行/末行不悬挂');
      }
    }
  });

  test('行尾非句读的行不悬挂', () {
    // 「中文中文中文中文后继续内容」首行 8 字以「文」结尾（实测确认）。
    const plainText = '中文中文中文中文后继续内容';
    final layout = _layout(plainText, width, _style(fontSize: 15, hanging: 'allow-end'));
    expect(layout.lineCount, 2);
    final first = layout.lines.first;
    final firstText = plainText.substring(first.start, first.end);
    expect(firstText.endsWith('文'), isTrue, reason: '样本前置：非句读行尾');
    expect(first.isLastLine, isFalse);
    // 非句读行尾不悬挂：extra = slack（1），无句读加成。
    expect(first.justifyExtra, closeTo(1, 0.01));
  });

  test('悬挂集合覆盖句读与省略号', () {
    expect(
      TextLayoutEngine.hangableTrailingPunctuation,
      containsAll(<String>['，', '。', '、', '；', '：', '？', '！', '…']),
    );
  });

  test('hanging-punctuation 解析：allow-end 生效、未知值回退 none、可继承', () {
    expect(_style(hanging: 'allow-end').hangingPunctuation.name, 'allowEnd');
    expect(_style(hanging: 'none').hangingPunctuation, CssHangingPunctuation.none);
    expect(_style(hanging: 'force-end').hangingPunctuation, CssHangingPunctuation.none);
    expect(_style().hangingPunctuation, CssHangingPunctuation.none);
    // 继承：子元素未声明沿用父级。
    final parent = _style(hanging: 'allow-end');
    final child = ComputedStyle(
      const <String, String>{'color': 'red'},
      parent: parent,
      explicitProperties: const <String>{'color'},
    );
    expect(child.hangingPunctuation, CssHangingPunctuation.allowEnd);
  });
}
