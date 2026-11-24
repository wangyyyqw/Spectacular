import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/home/book_cover_image.dart';

void main() {
  test('番茄封面统一原图路径，移除时效签名和尺寸模板', () {
    const url =
        'https://p9-reading-sign.fqnovelpic.com/novel-pic/abcdef~tplv-snk2bdmkp8.image?x-expires=1747703018&x-signature=expired';
    expect(
      normalizeBookCoverUrl(url, now: DateTime(2026)),
      'https://p6-novel.byteimg.com/origin/novel-pic/abcdef',
    );
    expect(
      normalizeBookCoverUrl(url, now: DateTime(2024)),
      'https://p6-novel.byteimg.com/origin/novel-pic/abcdef',
    );
  });
  test('豆瓣保留接口节点，兼容省略协议并拒绝无效地址', () {
    expect(
      normalizeBookCoverUrl(
        '//img9.doubanio.com/view/subject/l/public/s35665964.jpg',
      ),
      'https://img9.doubanio.com/view/subject/l/public/s35665964.jpg',
    );
    expect(normalizeBookCoverUrl('file:///private/cover.png'), isNull);
    expect(normalizeBookCoverUrl(''), isNull);
  });
  test('豆瓣失败备用节点保留原图片路径，晚风旧代理从书号解析起点原图', () {
    expect(
      bookCoverCandidates(
        'https://img3.doubanio.com/view/subject/l/public/a.jpg',
      ),
      [
        'https://img3.doubanio.com/view/subject/l/public/a.jpg',
        'https://img1.doubanio.com/view/subject/l/public/a.jpg',
        'https://img2.doubanio.com/view/subject/l/public/a.jpg',
        'https://img9.doubanio.com/view/subject/l/public/a.jpg',
      ],
    );
    expect(
      normalizeBookCoverUrl('https://shenmoxs.top/cover?bookId=1041234567'),
      'https://bookcover.yuewen.com/qdbimg/349573/1041234567/600',
    );
  });
}
