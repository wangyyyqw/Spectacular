import 'package:flutter_test/flutter_test.dart';
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  test('命中率统计', () {
    final cache = TextLayoutCache();
    cache.layout(text: 'x', style: _style(), maxWidth: 100);
    cache.layout(text: 'x', style: _style(), maxWidth: 100);
    cache.layout(text: 'x', style: _style(), maxWidth: 100);
    expect(cache.hits, 2);
    expect(cache.misses, 1);
    expect(cache.hitRate, closeTo(2 / 3, 1e-9));
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
  final trim = _style(const {'text-spacing-trim': 'trim-adjacent'});
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
