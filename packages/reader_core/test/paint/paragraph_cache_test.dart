import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/paint/paragraph_cache.dart';

TextPainter _painter(String text) => TextPainter(
  text: TextSpan(text: text, style: const TextStyle(fontSize: 16)),
  textDirection: TextDirection.ltr,
)..layout();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('同一键命中返回同一 painter', () {
    final cache = ParagraphCache();
    final first = cache.obtain('k', build: () => _painter('a'));
    final second = cache.obtain('k', build: () => _painter('b'));

    expect(identical(first, second), isTrue);
    expect(cache.hits, 1);
    expect(cache.misses, 1);
    expect(cache.length, 1);
    cache.dispose();
  });

  test('超过上限按 LRU 驱逐并释放段落', () {
    final cache = ParagraphCache(maxEntries: 2);
    final created = <TextPainter>[];
    for (var i = 0; i < 4; i++) {
      late TextPainter painter;
      cache.obtain(
        'k$i',
        build: () {
          painter = _painter('$i');
          created.add(painter);
          return painter;
        },
      );
    }
    expect(cache.length, 2);
    expect(created[0].debugDisposed, isTrue);
    expect(created[1].debugDisposed, isTrue);
    expect(created[2].debugDisposed, isFalse);
    expect(created[3].debugDisposed, isFalse);
    cache.dispose();
  });

  test('布局指纹变化后旧缓存全部失效并释放', () {
    final cache = ParagraphCache();
    cache.bindLayout('fp-1');
    final oldPainter = cache.obtain('k', build: () => _painter('old'));
    expect(cache.length, 1);

    cache.bindLayout('fp-2');
    expect(cache.length, 0);
    expect(oldPainter.debugDisposed, isTrue);
    expect(cache.hits, 0);
    expect(cache.misses, 0);

    // 新指纹下重建，旧键不会命中。
    final fresh = cache.obtain('k', build: () => _painter('new'));
    expect(identical(fresh, oldPainter), isFalse);
    expect(cache.length, 1);
    cache.dispose();
  });

  test('相同指纹重复 bindLayout 不清理', () {
    final cache = ParagraphCache();
    cache.bindLayout('fp');
    final painter = cache.obtain('k', build: () => _painter('a'));
    cache.bindLayout('fp');
    expect(cache.length, 1);
    expect(painter.debugDisposed, isFalse);
    cache.dispose();
  });

  test('clear 重置统计并释放全部段落', () {
    final cache = ParagraphCache();
    final painters = <TextPainter>[];
    for (var i = 0; i < 3; i++) {
      late TextPainter painter;
      cache.obtain(
        'k$i',
        build: () {
          painter = _painter('$i');
          painters.add(painter);
          return painter;
        },
      );
    }
    cache.obtain('k0', build: () => _painter('again'));
    expect(cache.hits, 1);
    cache.clear();
    expect(cache.length, 0);
    expect(cache.hits, 0);
    expect(cache.misses, 0);
    expect(painters.every((painter) => painter.debugDisposed), isTrue);
    cache.dispose();
  });

  test('连续插入大量条目后条目数与上限一致（不持续增长）', () {
    final cache = ParagraphCache(maxEntries: 8);
    for (var i = 0; i < 500; i++) {
      cache.obtain('k$i', build: () => _painter('$i'));
      expect(cache.length, lessThanOrEqualTo(8));
    }
    expect(cache.length, 8);
    cache.dispose();
  });
}
