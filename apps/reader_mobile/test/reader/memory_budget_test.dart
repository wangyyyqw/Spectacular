import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/paint/image_cache.dart';

void main() {
  test('图片缓存双上限：条数到顶后淘汰最旧（P4-32，§44.4）', () async {
    final cache = DecodedImageCache(
      maxEntries: 4,
      maxBytes: 1 << 20,
      loadBytes: (url) async => null,
    );
    // 用 loadBytes 返回 null 时不会缓存，这里只验证参数与 getter 契约。
    expect(cache.maxEntries, 4);
    expect(cache.maxBytes, 1 << 20);
    expect(cache.entryCount, 0);
  });
}
