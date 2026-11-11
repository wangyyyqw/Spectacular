import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/reader_overrides.dart';

import 'support/css_chapter_book.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const bookFontSize = 16.0;
  const titleRatio = 1.2;
  const authorEm = bookFontSize * titleRatio;
  for (final fontSize in [16.0, 20.0]) {
    test('作者一字宽浮动标题不被正文宽下限撑开，字号 $fontSize', () async {
      final source = await openCssChapter(
        body: '<h1>第一卷<br/>再见当年潮</h1>',
        css:
            'body {font-size:${bookFontSize}px;} '
            'h1 {font-family:Ahem; font-size:${titleRatio}em; width:1em; '
            'margin:27% 32% .25em .725em; padding:.5em 10px .5em 2px; '
            'float:right; line-height:1.2em; border-right:3px double #3e372e;}',
        contentWidth: 350,
        contentHeight: 700,
        overrides: ReaderOverrides(fontSize: fontSize),
      );
      addTearDown(source.close);
      final pages = await source.loadChapter(0);
      final slice = pages.expand((page) => page.slices).single;
      // 作者 1em 宽始终按书籍 16px × 1.2 解算，阅读字号只改变字形。
      expect(slice.block.layout.maxWidth, closeTo(authorEm, .01));
      expect(slice.block.style!.fontSize, closeTo(fontSize * titleRatio, .01));
      expect(slice.block.style!.padding.top, closeTo(authorEm * .5, .01));
      final titleEm = fontSize * titleRatio;
      // 标题相对外边距沿用随文字缩放的阅读策略，不改变作者内容宽。
      expect(slice.block.style!.margin.left, closeTo(titleEm * .725, .01));
      final layout = slice.block.layout;
      final lines = layout.lines
          .map((line) => layout.text.substring(line.start, line.end).trim())
          .where((text) => text.isNotEmpty);
      expect(lines, ['第', '一', '卷', '再', '见', '当', '年', '潮']);
      expect(
        slice.leftInset,
        closeTo(350 - 350 * .32 - titleEm * .725 - 15 - authorEm, .01),
      );
    });
  }
}
