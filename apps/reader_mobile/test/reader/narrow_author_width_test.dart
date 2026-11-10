import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/reader_overrides.dart';

import 'support/css_chapter_book.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final fontSize in [16.0, 20.0]) {
    test('作者一字宽浮动标题不被正文宽下限撑开，字号 $fontSize', () async {
      final source = await openCssChapter(
        body: '<h1>第一卷<br/>再见当年潮</h1>',
        css:
            'h1 {font-family:Ahem; font-size:1.2em; width:1em; '
            'margin:27% 32% .25em .725em; padding:.5em 10px .5em 2px; '
            'float:right; line-height:1.2em; border-right:3px double #3e372e;}',
        contentWidth: 350,
        contentHeight: 700,
        overrides: ReaderOverrides(fontSize: fontSize),
      );
      addTearDown(source.close);
      final pages = await source.loadChapter(0);
      final slice = pages.expand((page) => page.slices).single;
      final em = fontSize * 1.2;
      expect(slice.block.layout.maxWidth, closeTo(em, .01));
      final layout = slice.block.layout;
      final lines = layout.lines
          .map((line) => layout.text.substring(line.start, line.end).trim())
          .where((text) => text.isNotEmpty);
      expect(lines, ['第', '一', '卷', '再', '见', '当', '年', '潮']);
      expect(slice.leftInset, closeTo(350 - 112 - em * .725 - 15 - em, .01));
    });
  }
}
