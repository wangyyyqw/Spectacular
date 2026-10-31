import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/reader/bounded_cache.dart';

void main() {
  test('BoundedCache 按最近访问顺序淘汰最久未用条目', () {
    final cache = BoundedCache<String, int>(2)
      ..['a'] = 1
      ..['b'] = 2;

    expect(cache['a'], 1);
    cache['c'] = 3;

    expect(cache.containsKey('a'), isTrue);
    expect(cache.containsKey('b'), isFalse);
    expect(cache.containsKey('c'), isTrue);
  });

  test('BoundedCache 命中会提升顺序且不重复创建', () {
    var created = 0;
    final cache = BoundedCache<String, int>(2);
    int create() => ++created;

    expect(cache.putIfAbsent('a', create), 1);
    expect(cache.putIfAbsent('a', create), 1);
    expect(cache.putIfAbsent('b', create), 2);
    expect(cache.putIfAbsent('a', create), 1);
    cache['c'] = 3;

    expect(created, 2);
    expect(cache.containsKey('a'), isTrue);
    expect(cache.containsKey('b'), isFalse);
  });

  test('BoundedCache 支持删除与清空', () {
    final cache = BoundedCache<String, int>(2)
      ..['a'] = 1
      ..['b'] = 2;

    expect(cache.remove('a'), 1);
    expect(cache.remove('missing'), isNull);
    expect(cache.length, 1);
    cache.clear();
    expect(cache.length, 0);
  });
}
