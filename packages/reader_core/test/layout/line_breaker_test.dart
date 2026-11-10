import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/line_breaker.dart';

ComputedStyle _style({double fontSize = 16}) => ComputedStyle(<String, String>{
  'font-size': '${fontSize}px',
  'line-height': '1.5',
  'font-family': 'Ahem',
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final file = File('../../test_fonts/SourceHanSerifSC-Regular.otf');
    if (!file.existsSync()) {
      return;
    }
    final bytes = ByteData.view(file.readAsBytesSync().buffer);
    final loader = FontLoader('P202Kinsoku')
      ..addFont(Future<ByteData>.value(bytes));
    await loader.load();
  });
  test('窄宽钳制到 3em 并只告警一次', () {
    final warnings = <LineBreakWarning>[];
    final breaker = LineBreaker(onWarning: warnings.add);
    final style = _style();
    final first = breaker.layout(
      text: '中文窄宽样本，用于验证三 em 下限。',
      style: style,
      maxWidth: 20,
    );
    expect(first.maxWidth, 48);
    expect(breaker.tooNarrow, isTrue);
    expect(breaker.warningCount, 1);
    expect(warnings, hasLength(1));
    expect(warnings.single.code, 'layout.tooNarrow');
    expect(warnings.single.requestedWidth, 20);
    expect(warnings.single.minimumWidth, 48);
    expect(first.lines, isNotEmpty);
    expect(
      first.lines.every((line) => line.width <= first.maxWidth + 0.001),
      isTrue,
    );

    breaker.layout(text: '再次窄宽', style: style, maxWidth: 10);
    expect(warnings, hasLength(1), reason: '同一断行器只记录一次告警');
    expect(breaker.lastWarning, same(warnings.single));
  });

  test('正常宽度不钳制、不告警', () {
    final warnings = <LineBreakWarning>[];
    final breaker = LineBreaker(onWarning: warnings.add);
    final result = breaker.layout(
      text: '正常宽度文本',
      style: _style(),
      maxWidth: 320,
    );
    expect(result.maxWidth, 320);
    expect(breaker.tooNarrow, isFalse);
    expect(breaker.warningCount, 0);
    expect(warnings, isEmpty);
  });

  test('行内块保留窄内容宽和右对齐，不触发正文 3em 告警', () {
    final warnings = <LineBreakWarning>[];
    final breaker = LineBreaker(onWarning: warnings.add);
    for (final whiteSpace in ['normal', 'nowrap']) {
      final result = breaker.layout(
        text: 'S',
        style: ComputedStyle({
          'display': 'inline-block',
          'font-family': 'Ahem',
          'font-size': '16px',
          'text-align': 'right',
          'white-space': whiteSpace,
        }),
        maxWidth: 20,
      );
      expect(result.maxWidth, 20);
      final line = result.lines.single;
      expect(line.offsetX + line.width, closeTo(20, .01));
    }
    expect(breaker.tooNarrow, isFalse);
    expect(warnings, isEmpty);
  });

  test('无限宽不触发下限', () {
    final breaker = LineBreaker();
    final result = breaker.layout(
      text: 'short',
      style: _style(),
      maxWidth: double.infinity,
    );
    expect(result.maxWidth, double.infinity);
    expect(result.lineCount, 1);
    expect(breaker.tooNarrow, isFalse);
  });

  test('作者声明的一字宽块保留请求宽，自动宽正文仍受下限保护', () {
    final breaker = LineBreaker();
    for (final width in ['1em', '20px', '10%']) {
      final style = ComputedStyle({..._style().values, 'width': width});
      final layout = breaker.layout(text: 'ABCD', style: style, maxWidth: 20);
      expect(layout.maxWidth, 20);
      expect(layout.lines, hasLength(4));
    }
    expect(breaker.tooNarrow, isFalse);
    final automatic = ComputedStyle({..._style().values, 'width': 'auto'});
    expect(breaker.effectiveWidth(automatic, 20), 48);
    expect(breaker.tooNarrow, isTrue);
  });

  test('字号变化时下限按 3em 折算', () {
    final breaker = LineBreaker();
    final result = breaker.layout(
      text: '字号 20',
      style: _style(fontSize: 20),
      maxWidth: 30,
    );
    expect(result.maxWidth, 60);
    expect(breaker.lastWarning!.minimumWidth, 60);
  });

  test('TextLayoutEngine 可注入断行器观察钳制', () {
    final warnings = <LineBreakWarning>[];
    final breaker = LineBreaker(onWarning: warnings.add);
    final result = TextLayoutEngine.layout(
      text: '引擎断行',
      style: _style(),
      maxWidth: 1,
      lineBreaker: breaker,
    );
    expect(result.maxWidth, 48);
    expect(warnings, hasLength(1));
  });
  test('行内图片占位符不拆', () {
    const text = '甲\uFFFC乙丙';
    final layout = TextLayoutEngine.layout(
      text: text,
      style: _style(),
      maxWidth: 48,
    );
    expect(
      layout.lines.map((line) => text.substring(line.start, line.end)).join(),
      text,
    );
    expect(text.substring(0, text.length), contains('\uFFFC'));
  });

  test('禁则：标点不落行首（S4 字体）', () {
    const text = '一二三四五六七八九十，后续内容';
    final style = ComputedStyle(const <String, String>{
      'font-size': '16px',
      'line-height': '1.5',
      'font-family': 'P202Kinsoku',
    });
    final layout = TextLayoutEngine.layout(
      text: text,
      style: style,
      maxWidth: 160,
    );
    for (final line in layout.lines) {
      final lineText = text.substring(line.start, line.end);
      expect(lineText.startsWith('，'), isFalse, reason: '标点落行首: $lineText');
      expect(lineText.startsWith('。'), isFalse);
    }
  });

  for (final punct in <String>['，', '。', '？']) {
    test('行内盒之后的 $punct 不落行首', () {
      final text = '一二三四五六七八九十$punct后续内容';
      final style = ComputedStyle(const <String, String>{
        'font-size': '16px',
        'line-height': '1.5',
        'font-family': 'P202Kinsoku',
      });
      final layout = TextLayoutEngine.layout(
        text: text,
        style: style,
        maxWidth: 160,
        inlineBoxes: const <InlineBoxSpec>[
          InlineBoxSpec(offset: 10, width: 12, height: 12),
        ],
      );
      for (final line in layout.lines) {
        final lineText = text.substring(line.start, line.end);
        expect(
          lineText.startsWith(punct),
          isFalse,
          reason: '标点落行首: $lineText',
        );
      }
    });
  }

  _p202BoundaryTests();
  _p205BoundaryTests();
}

void _p202BoundaryTests() {
  test('首行缩进与尾段重排', () {
    final style = ComputedStyle(const <String, String>{
      'font-size': '16px',
      'line-height': '1.5',
      'font-family': 'Ahem',
      'text-indent': '32px',
    });
    final layout = TextLayoutEngine.layout(
      text: 'abcdefghijklmnop',
      style: style,
      maxWidth: 160,
    );
    expect(layout.lines, hasLength(2));
    expect(layout.lines.first.end, 8);
    expect(layout.lines.first.indent, 32);
    expect(layout.lines.first.isLastLine, isFalse);
    expect(layout.lines.last.isLastLine, isTrue);
    expect(
      layout.lines
          .map((line) => layout.text.substring(line.start, line.end))
          .join(),
      'abcdefghijklmnop',
    );
  });

  test('硬换行标记与末行判定', () {
    final layout = TextLayoutEngine.layout(
      text: 'a\nb',
      style: _style(),
      maxWidth: 200,
    );
    expect(layout.lineCount, 2);
    expect(layout.lines[0].isHardBreak, isTrue);
    expect(layout.lines[0].isLastLine, isFalse);
    expect(layout.lines[1].isHardBreak, isFalse);
    expect(layout.lines[1].isLastLine, isTrue);
  });

  test('负 letter-spacing 允许且行宽非负', () {
    final style = ComputedStyle(const <String, String>{
      'font-size': '16px',
      'line-height': '1.5',
      'font-family': 'Ahem',
      'letter-spacing': '-4px',
    });
    final layout = TextLayoutEngine.layout(
      text: 'abcdef',
      style: style,
      maxWidth: 200,
    );
    expect(layout.lines, isNotEmpty);
    expect(layout.lines.every((line) => line.width >= 0), isTrue);
    expect(style.letterSpacing, -4);
  });

  test('极大字号不崩溃且按行切分', () {
    final style = ComputedStyle(const <String, String>{
      'font-size': '200px',
      'line-height': '1',
      'font-family': 'Ahem',
    });
    final layout = TextLayoutEngine.layout(
      text: '中文',
      style: style,
      maxWidth: 48,
    );
    expect(layout.lineCount, greaterThanOrEqualTo(1));
    expect(layout.lines.every((line) => line.end - line.start <= 3), isTrue);
  });
}

void _p205BoundaryTests() {
  // ---- P2-05 行切分边界用例 ----
  group('中英混排', () {
    test('中英混排在词边界断开', () {
      const text = '中文English混排测试继续';
      final layout = _cjkLayout(text, 100);
      expect(_texts(layout), <String>['中文English', '混排测试继续']);
      _expectCoverage(layout, text);
    });

    test('空格分隔的英文词不拆', () {
      const text = '中文 English 混排';
      final layout = _cjkLayout(text, 96);
      expect(_texts(layout), <String>['中文 English ', '混排']);
      expect(layout.lines.last.isLastLine, isTrue);
    });

    test('数字串整串搬运', () {
      const text = '中文123456中文';
      final layout = _cjkLayout(text, 64);
      expect(_texts(layout), <String>['中文', '123456', '中文']);
      _expectCoverage(layout, text);
    });

    test('混排字符不丢不重', () {
      const text = '中文abc中文';
      final layout = _cjkLayout(text, 64);
      expect(_texts(layout), <String>['中文abc', '中文']);
      _expectCoverage(layout, text);
    });

    test('混排标点不落行首', () {
      const text = '中文English，混排';
      final layout = _cjkLayout(text, 96);
      expect(
        layout.lines.every(
          (line) => !text.substring(line.start, line.end).startsWith('，'),
        ),
        isTrue,
      );
      _expectCoverage(layout, text);
    });
  });

  group('标点禁则', () {
    for (final punct in <String>['，', '。', '、', '；', '：', '？', '！']) {
      test('$punct 不落行首', () {
        final text = '中文中文$punct中文';
        final layout = _cjkLayout(text, 64);
        expect(layout.lineCount, 2);
        expect(
          layout.lines.every(
            (line) => !text.substring(line.start, line.end).startsWith(punct),
          ),
          isTrue,
          reason: '行首出现 $punct',
        );
        _expectCoverage(layout, text);
      });
    }

    test('省略号对不拆（S4 历史缺陷复现）', () {
      // S4 实测：2em 宽时省略号会被拆到两行；3em 钳制后不再发生。
      const text = '中文……中文';
      final layout = _cjkLayout(text, 20);
      expect(layout.maxWidth, 48, reason: '钳制到 3em');
      for (final line in layout.lines) {
        final lineText = text.substring(line.start, line.end);
        expect(lineText.startsWith('…'), isFalse, reason: '省略号落行首');
        expect(
          lineText.codeUnits.where((unit) => unit == 0x2026).length,
          isNot(1),
          reason: '省略号对被拆开',
        );
      }
      _expectCoverage(layout, text);
    });

    test('破折号对不拆', () {
      const text = '中文——中文';
      final layout = _cjkLayout(text, 64);
      final lines = _texts(layout);
      expect(lines, <String>['中文——', '中文']);
      expect(lines.first.endsWith('——'), isTrue);
    });

    test('闭合引号不落行首', () {
      const text = '「中文」中文';
      final layout = _cjkLayout(text, 48);
      expect(
        layout.lines.every(
          (line) => !text.substring(line.start, line.end).startsWith('」'),
        ),
        isTrue,
      );
      _expectCoverage(layout, text);
    });

    test('开口符不落行尾（D22 后移，P7-07）', () {
      // D22 strict：开口符不在行尾。三字行宽下断点恰在开口符之后，
      // 引擎应把开口符一并移到下一行（S4 场景 3）。
      for (final open in <String>['（', '「', '『', '【', '《']) {
        final text = '中文$open内文';
        final layout = _cjkLayout(text, 48);
        final lines = _texts(layout);
        expect(
          lines.every((line) => !line.endsWith(open)),
          isTrue,
          reason: '$open 落行尾: $lines',
        );
        _expectCoverage(layout, text);
      }
    });
  });

  group('长词与空格', () {
    test('长英文单词强制断行', () {
      const text = 'internationalization';
      final layout = _cjkLayout(text, 100);
      expect(_texts(layout), <String>['internationa', 'lization']);
      expect(layout.lines.every((line) => line.width <= 100 + 0.01), isTrue);
      _expectCoverage(layout, text);
    });

    test('长数字串强制断行', () {
      const text = '12345678901234567890';
      final layout = _cjkLayout(text, 100);
      expect(_texts(layout), <String>['12345678901', '234567890']);
      _expectCoverage(layout, text);
    });

    test('长 URL 不在 token 内断行（与 Chrome 一致：整段溢出）', () {
      // Chrome 对无断行机会的 token 不做逐字紧急断行（溢出可见）；
      // `/`（UAX#14 SY）在 ICU 里会给断点，排版层用 WORD JOINER 压掉。
      const text = 'https://example.com/path/to/page';
      final layout = _cjkLayout(text, 100);
      expect(_texts(layout), <String>[text]);
      expect(layout.lines.single.width, greaterThan(100));
      _expectCoverage(layout, text);
    });

    test('overflow-wrap: break-word 时长 URL 仍可逐字断行（作者显式选择）', () {
      const text = 'https://example.com/path/to/page';
      final layout = TextLayoutEngine.layout(
        text: text,
        style: ComputedStyle(<String, String>{
          'font-size': '16px',
          'line-height': '1.5',
          'font-family': 'P202Kinsoku',
          'overflow-wrap': 'break-word',
        }),
        maxWidth: 100,
      );
      expect(layout.lineCount, greaterThan(1));
      _expectCoverage(layout, text);
    });

    test('连字符词在连字符后断行', () {
      const text = 'well-known-word';
      final layout = _cjkLayout(text, 80);
      expect(_texts(layout), <String>['well-', 'known-', 'word']);
      _expectCoverage(layout, text);
    });

    test('断行优先落在空格处', () {
      const text = 'aaa bbb ccc ddd';
      final layout = _layout(text, 80);
      expect(_texts(layout), <String>['aaa ', 'bbb ', 'ccc ', 'ddd']);
    });

    test('除首行外下一行不以空格开头', () {
      const text = '中文 English 混排';
      final layout = _cjkLayout(text, 96);
      expect(
        layout.lines
            .skip(1)
            .every(
              (line) => !text.substring(line.start, line.end).startsWith(' '),
            ),
        isTrue,
      );
    });

    test('首行保留行首空格', () {
      const text = ' 中文中文中文';
      final layout = _cjkLayout(text, 64);
      expect(_texts(layout).first.startsWith(' '), isTrue);
      _expectCoverage(layout, text);
    });

    test('NBSP 不落行首', () {
      const text = '中文中文\u00A0中文';
      final layout = _cjkLayout(text, 64);
      expect(
        layout.lines.every(
          (line) => !text.substring(line.start, line.end).startsWith('\u00A0'),
        ),
        isTrue,
      );
      _expectCoverage(layout, text);
    });
  });

  group('历史缺陷回归', () {
    test('首行缩进尾段偏移不回退（P2-02 缺陷）', () {
      // 旧实现尾段未重基偏移，拼接会得到 'abcdefghabcdefgh'。
      const text = 'abcdefghijklmnop';
      final layout = _cjkLayout(text, 160, indent: '32px');
      expect(layout.lineCount, 2);
      expect(
        layout.lines.map((line) => text.substring(line.start, line.end)).join(),
        text,
      );
      expect(layout.lines.first.indent, 32);
      _expectCoverage(layout, text);
    });

    test('硬换行与空行边界不回退（P1-23 缺陷）', () {
      // 旧实现用“上一行 end”取位置，空行会退回上一行边界。
      const text = 'a\n\nb';
      final layout = _layout(text, 100);
      expect(
        layout.lines.map((line) => (line.start, line.end)).toList(),
        <(int, int)>[(0, 1), (2, 2), (3, 4)],
      );
      _expectCoverage(layout, text);
    });

    test('段尾换行不产生空行（P2-04 缺陷）', () {
      final layout = _layout('a\n', 100);
      expect(layout.lineCount, 1);
      expect(layout.lines.single.end, 1);
    });
  });
}

/// 行文本列表。
List<String> _texts(TextLayoutResult layout) => [
  for (final line in layout.lines) layout.text.substring(line.start, line.end),
];

/// CJK 样本布局（SourceHanSerif，P2-05 边界用例使用）。
TextLayoutResult _cjkLayout(String text, double width, {String? indent}) =>
    TextLayoutEngine.layout(
      text: text,
      style: ComputedStyle(<String, String>{
        'font-size': '16px',
        'line-height': '1.5',
        'font-family': 'P202Kinsoku',
        'text-indent': ?indent,
      }),
      maxWidth: width,
    );

/// 行区间必须单调、不重叠，除换行符外所有字符都被行覆盖。
void _expectCoverage(TextLayoutResult layout, String text) {
  var previousEnd = 0;
  final covered = <int>{};
  for (final line in layout.lines) {
    expect(line.start, greaterThanOrEqualTo(previousEnd), reason: '行区间重叠');
    expect(line.end, greaterThanOrEqualTo(line.start));
    for (var i = line.start; i < line.end; i++) {
      covered.add(i);
    }
    previousEnd = line.end;
  }
  final visible = <int>{
    for (var i = 0; i < text.length; i++)
      if (text[i] != '\n') i,
  };
  expect(covered, visible, reason: '字符被漏掉或重复');
}

/// 默认样式（Ahem）布局。
TextLayoutResult _layout(String text, double width) =>
    TextLayoutEngine.layout(text: text, style: _style(), maxWidth: width);
