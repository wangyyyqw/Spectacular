import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/home/book_cover_image.dart';

void main() {
  test('过期番茄签名封面保留图片身份并切换至可访问原图，有效签名保留', () {
    const url =
        'https://p9-reading-sign.fqnovelpic.com/novel-pic/abcdef~tplv-snk2bdmkp8.image?x-expires=1747703018&x-signature=expired';
    expect(
      normalizeBookCoverUrl(url, now: DateTime(2026)),
      'https://p3-novel.byteimg.com/origin/novel-pic/abcdef',
    );
    expect(normalizeBookCoverUrl(url, now: DateTime(2024)), url);
  });
  test('豆瓣统一可访问图片节点，兼容省略协议并拒绝无效地址', () {
    expect(
      normalizeBookCoverUrl(
        '//img9.doubanio.com/view/subject/l/public/s35665964.jpg',
      ),
      'https://img1.doubanio.com/view/subject/l/public/s35665964.jpg',
    );
    expect(normalizeBookCoverUrl('file:///private/cover.png'), isNull);
    expect(normalizeBookCoverUrl(''), isNull);
  });
}
