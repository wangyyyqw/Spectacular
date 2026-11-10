import 'package:flutter_test/flutter_test.dart';

import 'support/css_chapter_book.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('前言上下 95% 外边距不把放得下的三行文字拆到两页', () async {
    final source = await openCssChapter(
      body: '<p>前言首行<br/>前言第二行<br/>前言最后一行</p>',
      css:
          'body {margin:0;line-height:1.3;} '
          'p {margin:95% 0;font-size:100%;text-align:center;text-indent:0;}',
      contentWidth: 344,
      contentHeight: 685.2,
    );
    addTearDown(source.close);
    final pages = await source.loadChapter(0);
    expect(pages, hasLength(1));
    expect(pages.single.slices.single.endLine, 3);
    expect(pages.single.slices.single.block.leadingExtent, closeTo(326.8, .01));
    expect(pages.single.usedHeight, lessThanOrEqualTo(685.2));
  });
}
