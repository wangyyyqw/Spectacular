import 'package:flutter_test/flutter_test.dart';

import 'support/css_chapter_book.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('页面根 column flex 按 100vh 将版权卡片上下居中', () async {
    final source = await openCssChapter(
      body:
          '<div class="card">'
          '<p>制作信息</p>'
          '<p>书名：资治通鉴</p>'
          '</div>',
      css:
          'html, body { margin: 0; } '
          'body { padding: 5px; } '
          'body { min-height: 100vh; display: flex; flex-direction: column; '
          'justify-content: center; align-items: center; } '
          '.card { width: 80%; padding: 10px; background: #eee; } '
          'p { margin: 0; font: 20px/1.6 serif; text-align: center; }',
      contentWidth: 360,
      contentHeight: 600,
    );

    final pages = await source.loadChapter(0);
    expect(pages, hasLength(1));
    final page = pages.single;
    var y = page.topPadding;
    double? contentTop;
    double? contentBottom;
    for (final slice in page.slices) {
      if (slice.block.layout.text.trim().isNotEmpty) {
        contentTop ??= y;
        contentBottom = y + slice.height;
      }
      y += slice.height;
    }

    expect(contentTop, isNotNull);
    expect(contentBottom, isNotNull);
    expect(
      contentTop! - page.topPadding,
      closeTo(page.pageHeight - contentBottom!, 0.5),
      reason: '版权卡片上下留白必须相等',
    );
  });
}
