import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/painting.dart'
    show Color, TextDirection, TextLeadingDistribution, TextPainter, TextSpan;
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/layout/text_layout_cache.dart';

ComputedStyle _style([Map<String, String> overrides = const {}]) =>
    ComputedStyle(<String, String>{
      'font-size': '16px',
      'line-height': '1.6',
      'font-family': 'Ahem',
      ...overrides,
    });

void _expectFirstLineMode(
  TextLayoutResult result,
  bool explicitEmpty,
  Color firstColor,
  Color spanColor,
) {
  final end = explicitEmpty ? 4 : 5;
  final width = explicitEmpty ? 128.0 : 120.0;
  expect(result.lines.first.end, end);
  expect(result.lines.first.width, closeTo(width, .01));
  expect(result.lines[1].start, end);
  expect(result.firstLineRuns, explicitEmpty ? isEmpty : isNull);
  expect(result.runs.first.end, end);
  expect(result.runs.first.style.fontSize, explicitEmpty ? 32 : 24);
  expect(result.runs.first.style.color, explicitEmpty ? firstColor : spanColor);
  expect(result.runs.last.start, end);
  expect(result.runs.last.style.fontSize, 24);
  expect(result.runs.last.style.color, spanColor);
  expect(result.inputRuns.single.style.color, spanColor);
  final painter = TextPainter(
    text: TextSpan(
      text: result.text.substring(0, end),
      style: TextLayoutEngine.textStyleFor(result.runs.first.style),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  try {
    expect(painter.width, closeTo(width, .01));
  } finally {
    painter.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('完整布局复用核对测量条件与注音，缓存命中的新 runs 保留记录', () async {
    final cache = TextLayoutCache();
    final style = _style();
    final rubies = [const RubyAnnotation(start: 0, end: 2, text: 'zhengwen')];
    Future<TextLayoutResult> measure(String color) => cache.layoutAsync(
      text: '正文混排',
      style: style,
      maxWidth: 200,
      runs: [
        StyledRun(start: 2, end: 4, style: _style({'color': color})),
      ],
      rubies: rubies,
      hasGlyph: (_, _) => true,
      fontDependency: '字体1',
    );
    bool matches(
      TextLayoutResult result, {
      ComputedStyle? measuredStyle,
      double width = 200,
      String fonts = '字体1',
      List<RubyAnnotation>? annotations,
    }) => cache.canReuseUnchanged(
      result,
      style: measuredStyle ?? style,
      maxWidth: width,
      fontDependency: fonts,
      rubies: annotations ?? rubies,
    );
    final first = await measure('red');
    final current = await measure('blue');
    expect(current, isNot(same(first)));
    expect(cache.hits, 1);
    expect(matches(current), isTrue);
    expect(matches(current, width: 180), isFalse);
    expect(matches(current, fonts: '字体2'), isFalse);
    expect(
      matches(current, measuredStyle: _style({'text-indent': '20px'})),
      isFalse,
    );
    expect(
      matches(
        current,
        annotations: const [RubyAnnotation(start: 0, end: 2, text: 'zhengwen')],
      ),
      isTrue,
    );
    expect(
      matches(
        current,
        annotations: const [RubyAnnotation(start: 0, end: 1, text: 'zhengwen')],
      ),
      isFalse,
    );
    expect(
      matches(
        current,
        annotations: const [RubyAnnotation(start: 0, end: 2, text: '不同注音')],
      ),
      isFalse,
    );
    expect(
      matches(
        current,
        annotations: [
          RubyAnnotation(start: 0, end: 2, text: 'zhengwen', style: _style()),
        ],
      ),
      isFalse,
    );
    rubies.clear();
    expect(matches(current), isFalse, reason: '测量记录保留注音快照');
    cache.clear();
    expect(matches(first), isFalse);
  });

  test('特殊测量选项与未经本缓存登记的布局不能直接复用', () async {
    final cache = TextLayoutCache();
    final style = _style();
    bool matches(TextLayoutResult result) => cache.canReuseUnchanged(
      result,
      style: style,
      maxWidth: 200,
      fontDependency: '',
    );
    TextLayoutResult measure({
      double scale = 1,
      TextLeadingDistribution leading = TextLeadingDistribution.even,
      bool glyphs = true,
      bool preserve = false,
    }) => cache.layout(
      text: '测量选项',
      style: style,
      maxWidth: 200,
      textScaleFactor: scale,
      leadingDistribution: leading,
      hasGlyph: glyphs ? (_, _) => true : null,
      preserveContentWidth: preserve,
    );
    expect(matches(measure()), isTrue);
    expect(matches(measure(scale: 1.2)), isFalse);
    expect(
      matches(measure(leading: TextLeadingDistribution.proportional)),
      isFalse,
    );
    expect(matches(measure(glyphs: false)), isFalse);
    expect(matches(measure(preserve: true)), isFalse);
    expect(
      matches(
        TextLayoutEngine.layout(
          text: '测量选项',
          style: style,
          maxWidth: 200,
          hasGlyph: (_, _) => true,
        ),
      ),
      isFalse,
    );
    for (final count in [64, 65]) {
      final rubies = [
        for (var i = 0; i < count; i++)
          RubyAnnotation(start: i * 2, end: i * 2 + 2, text: 'zhengwen'),
      ];
      final result = await cache.layoutAsync(
        text: '正文' * count,
        style: style,
        maxWidth: 200,
        rubies: rubies,
        hasGlyph: (_, _) => true,
      );
      expect(
        cache.canReuseUnchanged(
          result,
          style: style,
          maxWidth: 200,
          fontDependency: '',
          rubies: rubies,
        ),
        count <= 64,
        reason: '超过 64 条注音回到带检查点的重排',
      );
    }
  });

  test('测量快照不随调用方字体列表和注音样式的可变别名变化', () {
    final cache = TextLayoutCache();
    final families = ['Ahem'];
    final style = _style().withTypography(fontFamilyList: families);
    final rubyFamilies = ['Ahem'];
    final rubies = [
      RubyAnnotation(
        start: 0,
        end: 2,
        text: 'zhengwen',
        style: _style().withTypography(fontFamilyList: rubyFamilies),
      ),
    ];
    final result = cache.layout(
      text: '正文',
      style: style,
      maxWidth: 200,
      rubies: rubies,
      hasGlyph: (_, _) => true,
    );
    bool matches() => cache.canReuseUnchanged(
      result,
      style: style,
      maxWidth: 200,
      fontDependency: '',
      rubies: rubies,
    );
    expect(matches(), isTrue);
    families[0] = 'serif';
    expect(matches(), isFalse);
    families[0] = 'Ahem';
    rubyFamilies[0] = 'serif';
    expect(matches(), isFalse);
  });

  test('同文字样式但原行内盒首尾占宽不同不会复用分页几何', () {
    final cache = TextLayoutCache();
    final style = _style();
    TextLayoutResult layout(double leading, double trailing) => cache.layout(
      text: '甲乙',
      style: style,
      maxWidth: 200,
      runs: [
        StyledRun(
          start: 0,
          end: 2,
          style: style,
          inlineLeadingInset: leading,
          inlineTrailingInset: trailing,
        ),
      ],
    );
    final plain = layout(0, 0);
    final padded = layout(4, 6);
    expect(
      padded.lines.single.width - plain.lines.single.width,
      closeTo(10, .01),
    );
    expect(cache.misses, 2);
    layout(4, 6);
    expect(cache.hits, 1);
  });

  test('相同输入第二次命中缓存并返回同一结果对象', () {
    final cache = TextLayoutCache();
    final style = _style();
    final first = cache.layout(text: '缓存段落', style: style, maxWidth: 200);
    final second = cache.layout(text: '缓存段落', style: style, maxWidth: 200);

    expect(identical(first, second), isTrue);
    expect(cache.hits, 1);
    expect(cache.misses, 1);
    expect(cache.length, 1);
    expect(first.text, '缓存段落');
    expect(first.lines, isNotEmpty);
  });

  test('宽度、字号、字距、行高、对齐、文本、runs 变化均不命中', () {
    final cache = TextLayoutCache();
    final base = cache.layout(text: 'abc', style: _style(), maxWidth: 200);

    expect(
      identical(
        base,
        cache.layout(text: 'abc', style: _style(), maxWidth: 180),
      ),
      isFalse,
      reason: '宽度变化',
    );
    expect(
      identical(
        base,
        cache.layout(
          text: 'abc',
          style: _style(const {'font-size': '18px'}),
          maxWidth: 200,
        ),
      ),
      isFalse,
      reason: '字号变化',
    );
    expect(
      identical(
        base,
        cache.layout(
          text: 'abc',
          style: _style(const {'letter-spacing': '2px'}),
          maxWidth: 200,
        ),
      ),
      isFalse,
      reason: '字距变化',
    );
    expect(
      identical(
        base,
        cache.layout(
          text: 'abc',
          style: _style(const {'line-height': '2.0'}),
          maxWidth: 200,
        ),
      ),
      isFalse,
      reason: '行高变化',
    );
    expect(
      identical(
        base,
        cache.layout(
          text: 'abc',
          style: _style(const {'text-align': 'justify'}),
          maxWidth: 200,
        ),
      ),
      isFalse,
      reason: '对齐变化',
    );
    expect(
      identical(
        base,
        cache.layout(text: 'abd', style: _style(), maxWidth: 200),
      ),
      isFalse,
      reason: '文本变化',
    );
    expect(
      identical(
        base,
        cache.layout(
          text: 'abc',
          style: _style(),
          maxWidth: 200,
          runs: [
            StyledRun(
              start: 0,
              end: 1,
              style: _style(const {'font-size': '12px'}),
            ),
          ],
        ),
      ),
      isFalse,
      reason: '行内 run 变化',
    );
    expect(cache.misses, 8);
  });

  test('clear 清空条目与统计', () {
    final cache = TextLayoutCache();
    cache.layout(text: 'a', style: _style(), maxWidth: 100);
    cache.layout(text: 'a', style: _style(), maxWidth: 100);
    expect(cache.length, 1);
    cache.clear();
    expect(cache.length, 0);
    expect(cache.hits, 0);
    expect(cache.misses, 0);
  });

  test('LRU 淘汰最久未用', () {
    final cache = TextLayoutCache(maxEntries: 2);
    cache.layout(text: 'a', style: _style(), maxWidth: 100);
    cache.layout(text: 'b', style: _style(), maxWidth: 100);
    cache.layout(text: 'c', style: _style(), maxWidth: 100);
    expect(cache.length, 2);
    // a 已被淘汰：再次访问是 miss。
    final missesBefore = cache.misses;
    cache.layout(text: 'a', style: _style(), maxWidth: 100);
    expect(cache.misses, missesBefore + 1);
  });

  test('缓存结果与直接布局一致', () {
    final cache = TextLayoutCache();
    final style = _style(const {'text-align': 'justify'});
    final cached = cache.layout(
      text: '一二三四五六七八九十',
      style: style,
      maxWidth: 120,
    );
    final direct = TextLayoutEngine.layout(
      text: '一二三四五六七八九十',
      style: style,
      maxWidth: 120,
    );
    expect(cached.text, direct.text);
    expect(cached.lineCount, direct.lineCount);
    expect(cached.width, closeTo(direct.width, 0.001));
    expect(cached.height, closeTo(direct.height, 0.001));
  });

  test('OpenType 排版输入变化不撞键', () {
    final cache = TextLayoutCache();
    const text = 'Typeface AVATAR To.';
    final base = _style(const {'font-family': 'builtin_song'});
    final variants = <ComputedStyle>[
      _style(const {
        'font-family': 'builtin_song',
        'font-variant-caps': 'small-caps',
      }),
      _style(const {
        'font-family': 'builtin_song',
        'font-variant-ligatures': 'none',
      }),
      _style(const {'font-family': 'builtin_song', 'font-kerning': 'none'}),
      _style(const {
        'font-family': 'builtin_song',
        'font-stretch': 'condensed',
      }),
      _style(const {'font-family': 'builtin_song', 'font-size-adjust': '0.5'}),
    ];

    for (final style in variants) {
      cache.layout(text: text, style: style, maxWidth: 300);
    }
    cache.layout(text: text, style: base, maxWidth: 300);

    expect(cache.misses, variants.length + 1);
    expect({
      base.layoutFingerprint,
      for (final style in variants) style.layoutFingerprint,
    }, hasLength(variants.length + 1));
  });

  test('命中率统计', () {
    final cache = TextLayoutCache();
    cache.layout(text: 'x', style: _style(), maxWidth: 100);
    cache.layout(text: 'x', style: _style(), maxWidth: 100);
    cache.layout(text: 'x', style: _style(), maxWidth: 100);
    expect(cache.hits, 2);
    expect(cache.misses, 1);
    expect(cache.hitRate, closeTo(2 / 3, 1e-9));
  });

  test('首行颜色变化跨同步异步复用几何，并重绑定当前首行和原文 runs', () async {
    const text = 'abcdefghijklmnopqrstuvwx';
    final body = _style({'word-break': 'break-all'});
    List<StyledRun> runs(ComputedStyle style) => [
      StyledRun(start: 0, end: text.length, style: style),
    ];

    for (final asyncFirst in [false, true]) {
      final cache = TextLayoutCache();
      Future<TextLayoutResult> measure(
        bool asynchronous,
        ComputedStyle firstStyle,
        String color,
      ) async {
        final sourceRuns = runs(_style({'color': color}));
        final firstRuns = runs(firstStyle);
        if (asynchronous) {
          return cache.layoutAsync(
            text: text,
            style: body,
            maxWidth: 128,
            runs: sourceRuns,
            firstLineStyle: firstStyle,
            firstLineRuns: firstRuns,
          );
        }
        return cache.layout(
          text: text,
          style: body,
          maxWidth: 128,
          runs: sourceRuns,
          firstLineStyle: firstStyle,
          firstLineRuns: firstRuns,
        );
      }

      final oldFirst = _style({'font-size': '32px', 'color': 'red'});
      final first = await measure(asyncFirst, oldFirst, 'green');
      final currentFirst = _style({'font-size': '32px', 'color': 'blue'});
      final current = await measure(!asyncFirst, currentFirst, 'orange');

      expect(cache.hits, 1);
      expect(cache.misses, 1);
      expect(current.lines, same(first.lines));
      expect(current.lines.first.end, 4);
      expect(current.firstLineStyle!.color, const Color(0xff0000ff));
      expect(
        current.firstLineRuns!.single.style.color,
        const Color(0xff0000ff),
      );
      expect(current.firstLineRuns!.single.end, text.length);
      expect(current.inputRuns.single.style.color, const Color(0xffffa500));
      expect(current.inputRuns.single.start, 0);
      expect(current.inputRuns.single.end, text.length);
      expect(current.runs.first.style.color, const Color(0xff0000ff));
      expect(current.runs.first.end, 4);
      expect(current.runs.last.start, 4);
      expect(current.runs.last.style.color, const Color(0xffffa500));
      expect(current.runs.last.style.fontSize, 16);
      expect(first.runs.first.style.color, const Color(0xffff0000));
      expect(first.inputRuns.single.style.color, const Color(0xff008000));
    }
  });

  test('首行字号、首行 run 度量和可用宽度变化均重新断行', () async {
    final cache = TextLayoutCache();
    const text = 'abcdefghijklmnopqrstuvwx';
    final body = _style({'word-break': 'break-all'});
    final first = _style({'font-size': '32px'});
    Future<TextLayoutResult> measure({
      ComputedStyle? firstStyle,
      double width = 128,
      List<StyledRun>? firstRuns,
    }) => cache.layoutAsync(
      text: text,
      style: body,
      maxWidth: width,
      firstLineStyle: firstStyle ?? first,
      firstLineRuns: firstRuns,
      hasGlyph: (_, _) => true,
    );

    final original = await measure();
    final smaller = await measure(firstStyle: _style({'font-size': '24px'}));
    final narrow = await measure(width: 96);
    final explicit = await measure(
      firstRuns: [
        StyledRun(
          start: 0,
          end: text.length,
          style: _style({'font-size': '40px'}),
        ),
      ],
    );
    expect(original.lines.first.end, 4);
    expect(smaller.lines.first.end, 5);
    expect(narrow.lines.first.end, 3);
    expect(explicit.lines.first.end, 3);
    expect(smaller.lines.first.height, lessThan(original.lines.first.height));
    expect(
      explicit.lines.first.height,
      greaterThan(original.lines.first.height),
    );
    expect(cache.hits, 0);
    expect(cache.misses, 4);
    expect(
      cache.canReuseUnchanged(
        original,
        style: body,
        maxWidth: 128,
        fontDependency: '',
      ),
      isFalse,
      reason: '首行输入不能走只检查正文测量条件的完整复用路径',
    );
  });

  test('首行自动继承与显式空列表双向缓存命中保留各自断点和实际绘制宽度', () async {
    const text = 'abcdefghijklmnopqrstuvwx';
    final body = _style({'word-break': 'break-all'});
    for (final emptyFirst in [false, true]) {
      final cache = TextLayoutCache();
      final previous = <bool, TextLayoutResult>{};
      final modes = [emptyFirst, !emptyFirst, emptyFirst, !emptyFirst];
      for (var step = 0; step < modes.length; step++) {
        final rebound = step >= 2;
        final first = ComputedStyle({
          'font-size': '32px',
          'color': rebound ? 'blue' : 'red',
        }, parent: body);
        final runs = [
          StyledRun(
            start: 0,
            end: text.length,
            style: ComputedStyle({
              'font-size': '24px',
              'color': rebound ? 'orange' : 'green',
            }, parent: body),
          ),
        ];
        final firstRuns = modes[step] ? const <StyledRun>[] : null;
        final result = step == 1 || step == 2
            ? await cache.layoutAsync(
                text: text,
                style: body,
                maxWidth: 128,
                runs: runs,
                firstLineStyle: first,
                firstLineRuns: firstRuns,
              )
            : cache.layout(
                text: text,
                style: body,
                maxWidth: 128,
                runs: runs,
                firstLineStyle: first,
                firstLineRuns: firstRuns,
              );
        _expectFirstLineMode(
          result,
          modes[step],
          rebound ? const Color(0xff0000ff) : const Color(0xffff0000),
          rebound ? const Color(0xffffa500) : const Color(0xff008000),
        );
        expect(result.firstLineStyle, same(first));
        expect(result.inputRuns, same(runs));
        if (previous[modes[step]] case final cached?) {
          expect(result.lines, same(cached.lines));
        }
        previous[modes[step]] = result;
        expect(cache.misses, step == 0 ? 1 : 2);
        expect(cache.hits, step < 2 ? 0 : step - 1);
      }
      expect(cache.length, 2);
    }
  });

  test('首行自动继承区分相同正文度量的继承字号与显式字号', () async {
    const text = 'abcdefghijklmnopqrstuvwx';
    final body = _style({'word-break': 'break-all'});
    final first = ComputedStyle({'font-size': '32px'}, parent: body);
    for (final explicitFirst in [false, true]) {
      final cache = TextLayoutCache();
      final previous = <bool, TextLayoutResult>{};
      final modes = [
        explicitFirst,
        !explicitFirst,
        explicitFirst,
        !explicitFirst,
      ];
      for (var step = 0; step < modes.length; step++) {
        final source = ComputedStyle({
          if (modes[step]) 'font-size': '16px',
          'color': step < 2 ? 'green' : 'orange',
        }, parent: body);
        final runs = [StyledRun(start: 0, end: text.length, style: source)];
        expect(source.fontSize, 16);
        final result = step == 1 || step == 2
            ? await cache.layoutAsync(
                text: text,
                style: body,
                maxWidth: 128,
                runs: runs,
                firstLineStyle: first,
              )
            : cache.layout(
                text: text,
                style: body,
                maxWidth: 128,
                runs: runs,
                firstLineStyle: first,
              );
        final end = modes[step] ? 8 : 4;
        expect(result.lines.first.end, end);
        expect(result.lines.first.width, closeTo(128, .01));
        expect(result.lines[1].start, end);
        expect(result.firstLineRuns, isNull);
        expect(result.inputRuns, same(runs));
        expect(result.runs.first.end, end);
        expect(result.runs.first.style.fontSize, modes[step] ? 16 : 32);
        expect(result.runs.first.style.color, source.color);
        expect(result.runs.last.start, end);
        expect(result.runs.last.style.fontSize, 16);
        expect(result.runs.last.style.color, source.color);
        final painter = TextPainter(
          text: TextSpan(
            text: text.substring(0, end),
            style: TextLayoutEngine.textStyleFor(result.runs.first.style),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        try {
          expect(painter.width, closeTo(result.lines.first.width, .01));
        } finally {
          painter.dispose();
        }
        if (previous[modes[step]] case final cached?) {
          expect(result.lines, same(cached.lines));
        }
        previous[modes[step]] = result;
        expect(cache.misses, step == 0 ? 1 : 2);
        expect(cache.hits, step < 2 ? 0 : step - 1);
      }
      expect(cache.length, 2);
    }
  });

  test('绘制 runs 重绑定可用显式 null 清除旧首行列表和级联输入', () {
    final body = _style();
    final first = _style({'font-size': '32px'});
    final original = TextLayoutEngine.layout(
      text: 'abcdefghijklmnop',
      style: body,
      maxWidth: 128,
      firstLineStyle: first,
      firstLineRuns: const [],
    );
    final inherited = original.withRuns(
      original.runs,
      firstLineStyle: first,
      firstLineRuns: null,
      sourceRuns: original.sourceRuns,
    );
    expect(inherited.firstLineRuns, isNull);
    expect(inherited.firstLineStyle, same(first));
    expect(inherited.inputRuns, same(original.inputRuns));
    expect(inherited.lines, same(original.lines));
    final cleared = inherited.withRuns(
      inherited.runs,
      firstLineStyle: null,
      firstLineRuns: null,
      sourceRuns: null,
    );
    expect(cleared.firstLineStyle, isNull);
    expect(cleared.firstLineRuns, isNull);
    expect(cleared.sourceRuns, isNull);
    expect(cleared.inputRuns, same(cleared.runs));
    expect(cleared.lines, same(original.lines));
  });
  _p729KeyIntegrity();
}

/// P7-29 键完整性：P7-18~21 新增排版输入必须改变缓存键（否则挤压/
/// 悬挂等开关变化会命中旧宽度）。
void _p729KeyIntegrity() {
  test('P7-29 键完整性：P7-18~21 排版输入变化不撞键', () {
    final cache = TextLayoutCache();
    const text = '中文，中文「引号」与 English 混排';
    final base = _style();
    // 默认已是 trim-adjacent，用 space-all（不挤压）作为反向输入。
    final trim = _style(const {'text-spacing-trim': 'space-all'});
    final autospace = _style(const {'text-autospace': 'normal'});
    final justifyAll = _style(const {'text-justify': 'justify-all'});
    final hanging = _style(const {'hanging-punctuation': 'allow-end'});

    cache.layout(text: text, style: base, maxWidth: 200);
    // 每种新输入首次都应 miss（不命中 base 的缓存）。
    expect(
      cache.layout(text: text, style: trim, maxWidth: 200).lineCount,
      greaterThanOrEqualTo(1),
    );
    expect(
      cache.layout(text: text, style: autospace, maxWidth: 200).lineCount,
      greaterThanOrEqualTo(1),
    );
    expect(
      cache.layout(text: text, style: justifyAll, maxWidth: 200).lineCount,
      greaterThanOrEqualTo(1),
    );
    expect(
      cache.layout(text: text, style: hanging, maxWidth: 200).lineCount,
      greaterThanOrEqualTo(1),
    );
    // 回到 base 再命中（键区分成功）。
    cache.layout(text: text, style: base, maxWidth: 200);
    expect(cache.misses, greaterThanOrEqualTo(5));
    // 指纹本身可区分。
    final fingerprints = <String>{
      base.layoutFingerprint,
      trim.layoutFingerprint,
      autospace.layoutFingerprint,
      justifyAll.layoutFingerprint,
      hanging.layoutFingerprint,
    };
    expect(fingerprints, hasLength(5));
  });
}
