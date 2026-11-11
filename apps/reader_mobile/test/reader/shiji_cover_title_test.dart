import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/paint/line_spans.dart';
import 'package:reader_core/epub/epub_chapter_source.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('史记扉页标题完整、自动换行且可见文字居中', () async {
    final file = File('../../test_corpus/real/shiji-yuewei.epub');
    final source = await EpubChapterSource.open(
      file.readAsBytesSync(),
      verifyCrc: false,
    );
    for (final (fontSize, width) in <(double, double)>[(17, 320), (19, 344)]) {
      await source.applyOverrides(
        ReaderOverrides(fontSize: fontSize, lineHeight: 1.6),
      );
      await source.applyContentSize(width: width, height: 640);

      final blocks = (await source.loadChapter(5))
          .expand((page) => page.slices)
          .map((slice) => slice.block)
          .where((block) => block.layout.text.contains('第一册'))
          .toList();
      expect(blocks, hasLength(1), reason: '扉页标题应生成一个 Flex 块');
      final title = blocks.single.table!.cells.single;
      expect(title.layout.text, '第一册\n\u00a0十二本纪');
      final lineTexts = [
        for (final line in title.layout.lines)
          title.layout.text.substring(line.start, line.end),
      ];
      expect(lineTexts, <String>[
        '第一册',
        '\u00a0十二本纪',
      ], reason: '作者标题应保持两行，不能让行尾字距制造单字孤行');
      expect(lineTexts.first, '第一册', reason: '首行不能被第二行的字符区间覆盖');
      expect(
        lineTexts.join(),
        title.layout.text.replaceAll('\n', ''),
        reason: '标题字符必须按原顺序各绘制一次',
      );
      expect(
        [
          for (var i = 1; i < title.layout.lines.length; i++)
            title.layout.lines[i].top > title.layout.lines[i - 1].top,
        ],
        everyElement(isTrue),
        reason: '标题各行应按顺序向下排列',
      );

      final secondLine = title.layout.lines[1];
      final painter = TextPainter(
        text: buildLineSpan(
          layout: title.layout,
          line: secondLine,
          baseStyle: TextLayoutEngine.textStyleFor(
            title.layout.runs.last.style,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final visibleStart = painter
          .getOffsetForCaret(const TextPosition(offset: 1), Rect.zero)
          .dx;
      final caretEnd = painter
          .getOffsetForCaret(
            TextPosition(offset: secondLine.end - secondLine.start),
            Rect.zero,
          )
          .dx;
      final visibleBoxes = painter.getBoxesForSelection(
        TextSelection(
          baseOffset: 1,
          extentOffset: secondLine.end - secondLine.start,
        ),
      );
      final visibleEnd = 2 * caretEnd - visibleBoxes.last.right;
      expect(
        secondLine.offsetX + (visibleStart + visibleEnd) / 2,
        closeTo(title.layout.maxWidth / 2, 0.1),
        reason: '行首 NBSP 不应让“十二本纪”整体偏右',
      );
    }
  });
}
