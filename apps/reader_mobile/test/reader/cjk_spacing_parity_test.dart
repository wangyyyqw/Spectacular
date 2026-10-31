import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';

import 'support/css_chapter_book.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final song = FontLoader('builtin_song')
      ..addFont(rootBundle.load('assets/fonts/SourceHanSerifCN-Regular.otf'))
      ..addFont(rootBundle.load('assets/fonts/SourceHanSerifCN-Bold.otf'));
    await song.load();
  });

  test('行首连续全角标点按浏览器 trim-adjacent 折叠', () async {
    final source = await openCssChapter(
      contentWidth: 350,
      contentHeight: 800,
      body:
          '<p>字号与行高对照 ABC abc 123，中文标点：、。！？</p>'
          '<p>第二段用于观察段间距，letter-spacing: 0.1em 下面单独测。</p>',
      css:
          'body { margin: 0; padding: 0; font-family: "builtin_song"; '
          'font-size: 17px; } p { margin: 8px 0; line-height: 1.6; }',
    );
    final pages = await source.loadChapter(0);
    final block = pages.first.slices.first.block;

    expect(block.style!.textSpacingTrim, CssTextSpacingTrim.trimAdjacent);
    expect(block.layout.runs, hasLength(1));
    expect(
      block.layout.runs.single.style.layoutFingerprint,
      block.style!.layoutFingerprint,
    );
    expect(block.layout.plainTextLayout, isTrue);
    expect(block.layout.lines, hasLength(2));
    expect(
      block.layout.text.substring(
        block.layout.lines[1].start,
        block.layout.lines[1].end,
      ),
      '点：、。！？',
    );
    expect(block.layout.lines[1].width, closeTo(85, 0.01));
  });
}
