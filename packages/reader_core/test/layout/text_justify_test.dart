import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/cjk_justify.dart';
import 'package:reader_core/layout/line_breaker.dart';

/// P7-21：text-justify 四值与 text-align-last。
void main() {
  TextLayoutResult layoutOf(String text, Map<String, String> extra) =>
      TextLayoutEngine.layout(
        text: text,
        style: ComputedStyle(<String, String>{
          'font-size': '16px',
          'line-height': '1.5',
          'font-family': 'Ahem',
          'text-align': 'justify',
          ...extra,
        }),
        maxWidth: 121,
      );

  // 西文行：'one two three four five six'（含 5 个词间空格）。
  const latin = 'one two three four five six';

  test('auto：西文行只拉伸词间空格（现状行为不变）', () {
    final layout = layoutOf(latin, const <String, String>{});
    expect(layout.lines.first.justifyExtra, greaterThan(0));
    final gaps = cjkJustifyGapOffsets(
      latin.substring(layout.lines.first.start, layout.lines.first.end),
    );
    expect(gaps, everyElement(isIn(const <int>[3, 7, 11, 15, 19])),
        reason: 'auto 模式西文行 gap 全部落在空格处');
  });

  test('inter-word：含 CJK 的行也只拉伸空格', () {
    // 混排行 auto 模式：CJK 与拉丁相邻处也是 gap；inter-word 只剩空格。
    final autoLayout = layoutOf('中文Abc中文', const <String, String>{});
    final wordLayout = layoutOf('中文Abc中文', <String, String>{
      'text-justify': 'inter-word',
    });
    // 单行即末行，无拉伸；改用两行文本验证 gap 集合差异。
    final autoGaps = cjkJustifyGapOffsets(
      '中文 Abc 中文',
      mode: CssTextJustify.auto,
    );
    final wordGaps = cjkJustifyGapOffsets(
      '中文 Abc 中文',
      mode: CssTextJustify.interWord,
    );
    expect(autoGaps.length, greaterThan(wordGaps.length));
    expect(wordGaps, <int>[2, 6], reason: 'inter-word 只有空格间隙');
    expect(autoLayout.lineCount, wordLayout.lineCount);
  });

  test('distribute：拉丁词内也可拉伸（全 gap）', () {
    final autoGaps = cjkJustifyGapOffsets(
      'abc def',
      mode: CssTextJustify.auto,
    );
    final distributeGaps = cjkJustifyGapOffsets(
      'abc def',
      mode: CssTextJustify.distribute,
    );
    expect(autoGaps, <int>[3], reason: 'auto 西文行只有空格 gap');
    expect(distributeGaps.length, greaterThan(autoGaps.length),
        reason: 'distribute 词内也有 gap');
  });

  test('inter-character 与 distribute 行为一致（全 gap）', () {
    expect(
      cjkJustifyGapOffsets('abc def', mode: CssTextJustify.interCharacter),
      cjkJustifyGapOffsets('abc def', mode: CssTextJustify.distribute),
    );
  });

  test('text-align-last: justify 时末行参与拉伸', () {
    const text = '中文中文中文中，后续内容';
    final layout = layoutOf(text, <String, String>{
      'text-align-last': 'justify',
    });
    expect(layout.lines.last.isLastLine, isTrue);
    expect(
      layout.lines.last.justifyExtra,
      greaterThan(0),
      reason: '末行在 align-last: justify 下参与拉伸',
    );
  });

  test('text-justify: justify-all 时末行参与拉伸（align-last 未设置）', () {
    const text = '中文中文中文中，后续内容';
    final layout = layoutOf(text, <String, String>{
      'text-justify': 'justify-all',
    });
    expect(layout.lines.last.justifyExtra, greaterThan(0));
  });

  test('默认（未设置）末行不拉伸、非末行拉伸到 slack（含 justify 预留）', () {
    const text = '中文中文中文中，后续内容';
    final layout = layoutOf(text, const <String, String>{});
    expect(layout.lines.last.justifyExtra, 0);
    final first = layout.lines.first;
    expect(first.justifyExtra, closeTo(121 - first.width, 0.01),
        reason: '非末行拉伸余量 = 行宽之外的 slack');
  });

  test('text-align-last: center 控制末行居中', () {
    const text = '中文中文中文中，后续内容';
    final layout = TextLayoutEngine.layout(
      text: text,
      style: ComputedStyle(<String, String>{
        'font-size': '16px',
        'line-height': '1.5',
        'font-family': 'Ahem',
        'text-align': 'justify',
        'text-align-last': 'center',
      }),
      maxWidth: 121,
    );
    final last = layout.lines.last;
    // 末行居中：偏移 = (121 - 末行宽) / 2（分行随 justify 预留而定，
    // 断言相对化）。
    expect(last.offsetX, closeTo((121 - last.width) / 2, 0.01));
    expect(last.justifyExtra, 0, reason: 'center 不拉伸');
  });

  test('text-justify 解析：四值与回退', () {
    CssTextJustify parse(String value) => ComputedStyle(<String, String>{
      'font-size': '16px',
      'text-justify': value,
    }).textJustify;
    expect(parse('inter-word'), CssTextJustify.interWord);
    expect(parse('inter-character'), CssTextJustify.interCharacter);
    expect(parse('distribute'), CssTextJustify.distribute);
    expect(parse('justify-all'), CssTextJustify.justifyAll);
    expect(parse('auto'), CssTextJustify.auto);
    expect(parse('none'), CssTextJustify.auto);
  });
}
