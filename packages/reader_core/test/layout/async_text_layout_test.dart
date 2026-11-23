import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/layout/text_edges.dart';
import 'package:reader_core/layout/text_layout_cache.dart';

const _family = 'AsyncSourceHan';

ComputedStyle _style([Map<String, String> values = const {}]) => ComputedStyle({
  'font-family': _family,
  'font-size': '20px',
  'line-height': '1.6',
  'text-spacing-trim': 'trim-both',
  ...values,
});

Future<void> _loadFonts() async {
  final loader = FontLoader(_family);
  for (final weight in ['Regular', 'Bold']) {
    final bytes = await File(
      '../../apps/reader_mobile/assets/fonts/MoyuSerif-$weight.otf',
    ).readAsBytes();
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
}

List<Object?> _geometry(TextLayoutResult result) => [
  result.text,
  result.width,
  result.height,
  result.maxWidth,
  result.isRtl,
  result.writingMode,
  result.plainTextLayout,
  for (final line in result.lines)
    [
      line.start,
      line.end,
      line.top,
      line.height,
      line.baseline,
      line.width,
      line.indent,
      line.isLastLine,
      line.isHardBreak,
      line.offsetX,
      line.justifyExtra,
      line.justifyMode,
      line.spacing?.fingerprint,
      line.ellipsized,
      line.ellipsisWidth,
      line.hyphenated,
      line.hyphenWidth,
      line.columnIndex,
      line.columnX,
      line.vertical,
      for (final box in line.inlineBoxes)
        [box.offset, box.left, box.width, box.height, box.ascent, box.descent],
    ],
  for (final run in result.runs)
    [run.start, run.end, run.baselineShift, run.style.layoutFingerprint],
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_loadFonts);

  test('同步和异步的正文、行几何与原文坐标完全等价', () async {
    for (final css in [
      <String, String>{},
      {'text-spacing-trim': 'trim-all', 'text-align': 'justify'},
      {'text-spacing-trim': 'space-all'},
      {'text-indent': '2em', 'letter-spacing': '0.2px'},
      {'white-space': 'nowrap', 'text-overflow': 'ellipsis'},
      {'text-transform': 'uppercase', 'text-autospace': 'normal'},
      {'hyphens': 'auto'},
      {'direction': 'rtl'},
      {'writing-mode': 'vertical-rl'},
    ]) {
      for (final width in [70.0, 137.0, 320.0]) {
        final style = _style(css);
        const text =
            '（甲乙丙，丁戊己。）\n中文 English representation！'
            'a\u0301 与 👨‍👩‍👧‍👦，末段。';
        final synchronous = TextLayoutEngine.layout(
          text: text,
          style: style,
          maxWidth: width,
        );
        final asynchronous = await TextLayoutEngine.layoutAsync(
          text: text,
          style: style,
          maxWidth: width,
        );
        expect(
          _geometry(asynchronous),
          _geometry(synchronous),
          reason: '$css/$width',
        );
      }
    }
  });

  test('混合字体、字号、上下标、原子盒与注音边界共用几何', () async {
    final style = _style({'text-align': 'justify', 'text-indent': '1em'});
    const text = '甲》，「乙。混合 Arial 字体，原子盒与注音不跨边界挤压。';
    final runs = [
      StyledRun(
        start: 1,
        end: 4,
        style: _style({'font-size': '30px', 'font-weight': '700'}),
      ),
      StyledRun(
        start: 8,
        end: 13,
        style: _style({'font-family': 'Ahem', 'font-size': '14px'}),
      ),
      StyledRun(
        start: 15,
        end: 17,
        style: _style({'font-size': '12px'}),
        baselineShift: -5,
      ),
    ];
    const boxes = [InlineBoxSpec(offset: 20, width: 35, height: 25)];
    const rubies = [RubyAnnotation(start: 23, end: 25, text: '注音')];
    final sync = TextLayoutEngine.layout(
      text: text,
      style: style,
      maxWidth: 140,
      runs: runs,
      inlineBoxes: boxes,
      rubies: rubies,
      textScaleFactor: 1.25,
    );
    final async = await TextLayoutEngine.layoutAsync(
      text: text,
      style: style,
      maxWidth: 140,
      runs: runs,
      inlineBoxes: boxes,
      rubies: rubies,
      textScaleFactor: 1.25,
      checkpoint: () async {},
    );
    expect(_geometry(async), _geometry(sync));
  });

  test('纯长段和标点长段均逐行经过取消检查点', () async {
    for (final text in ['中文正文' * 500, '甲乙丙，丁戊己。' * 250]) {
      var checks = 0;
      final result = await TextLayoutEngine.layoutAsync(
        text: text,
        style: _style(),
        maxWidth: 200,
        checkpoint: () async {
          checks++;
        },
      );
      expect(result.lineCount, greaterThan(50));
      expect(checks, greaterThanOrEqualTo(result.lineCount));
    }
  });

  test('取消测量后不写缓存，随后重试可正常完成', () async {
    final cache = TextLayoutCache();
    final style = _style();
    final cancelled = StateError('任务已取消');
    var checks = 0;
    await expectLater(
      cache.layoutAsync(
        text: '甲乙丙，丁戊己。' * 200,
        style: style,
        maxWidth: 200,
        checkpoint: () async {
          if (++checks == 8) throw cancelled;
        },
      ),
      throwsA(same(cancelled)),
    );
    expect(cache.length, 0);
    final retry = await cache.layoutAsync(
      text: '甲乙丙，丁戊己。' * 200,
      style: style,
      maxWidth: 200,
    );
    expect(retry.lineCount, greaterThan(50));
    expect(cache.length, 1);
    expect(cache.misses, 2);
  });

  test('外部取消能在下一批测量前处理，未完成任务不返回旧结果', () async {
    var cancelled = false;
    var checks = 0;
    final future = TextLayoutEngine.layoutAsync(
      text: '甲乙丙，丁戊己。' * 300,
      style: _style(),
      maxWidth: 200,
      checkpoint: () async {
        if (cancelled) throw StateError('任务已取消');
        if (++checks == 5) {
          Timer.run(() => cancelled = true);
          await Future<void>.delayed(Duration.zero);
        }
      },
    );
    await expectLater(future, throwsStateError);
    expect(checks, lessThan(10));
  });

  test('测量期间清缓存不能被较早任务重新填入', () async {
    final cache = TextLayoutCache();
    var checks = 0;
    final result = await cache.layoutAsync(
      text: '甲乙丙，丁戊己。' * 100,
      style: _style(),
      maxWidth: 200,
      checkpoint: () async {
        if (++checks == 8) cache.clear();
      },
    );
    expect(result.lines, isNotEmpty);
    expect(cache.length, 0);
  });

  test('同步和异步共享完成缓存，实际字体依赖变化不能串用', () async {
    final cache = TextLayoutCache();
    final style = _style();
    final first = await cache.layoutAsync(
      text: '缓存正文。',
      style: style,
      maxWidth: 200,
      fontDependency: '字体版本一',
    );
    final reused = cache.layout(
      text: '缓存正文。',
      style: style,
      maxWidth: 200,
      fontDependency: '字体版本一',
    );
    expect(reused, same(first));
    final changed = await cache.layoutAsync(
      text: '缓存正文。',
      style: style,
      maxWidth: 200,
      fontDependency: '字体版本二',
    );
    expect(identical(first, changed), isFalse);
    expect(cache.misses, 2);
    expect(cache.hits, 1);
  });

  test('仅绘制颜色变化复用已实测留白，不再次塑形同一行', () {
    final cache = TextLayoutCache();
    final base = _style({'font-family': 'Ahem', 'line-height': '2'});
    final blue = ComputedStyle({'color': 'blue'}, parent: base);
    final red = ComputedStyle({'color': 'red'}, parent: base);
    final first = cache.layout(
      text: 'abc',
      style: base,
      maxWidth: 200,
      runs: [StyledRun(start: 0, end: 3, style: blue)],
    );
    final edges = textLineEdges(first, first.lines.single, base);
    final second = cache.layout(
      text: 'abc',
      style: base,
      maxWidth: 200,
      runs: [StyledRun(start: 0, end: 3, style: red)],
    );
    expect(second.runs.single.style.color, red.color);
    expect(textLineEdges(second, second.lines.single, red), same(edges));
    expect(cache.hits, 1);
    expect(cache.misses, 1);
  });

  test('实际宽度和小数行高开关均进入缓存键', () {
    final cache = TextLayoutCache();
    final previous = LineBreaker.preserveFractionalLineHeight;
    addTearDown(() => LineBreaker.preserveFractionalLineHeight = previous);
    final style = _style();
    LineBreaker.preserveFractionalLineHeight = false;
    cache.layout(text: '几何输入。', style: style, maxWidth: 200.001);
    cache.layout(text: '几何输入。', style: style, maxWidth: 200.002);
    LineBreaker.preserveFractionalLineHeight = true;
    cache.layout(text: '几何输入。', style: style, maxWidth: 200.002);
    expect(cache.misses, 3);
  });
}
