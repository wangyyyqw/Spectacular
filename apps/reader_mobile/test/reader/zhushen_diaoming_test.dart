import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/epub/epub_chapter_source.dart';
import 'package:reader_ui/panels/settings_panel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final book = File('../../test_corpus/real/zhushen-yuxi.epub');

  test('天赋吊命：默认和大字设置下标签保留完整文字、字号、颜色与占宽', () async {
    final source = await EpubChapterSource.open(
      book.readAsBytesSync(),
      verifyCrc: false,
    );
    // 固定内容视口便于复现；USB 应按标题/正文查实际页号。
    await source.applyContentSize(width: 344, height: 700);
    final reports = <Map<String, Object>>[];
    for (final size in [17.0, 22.0]) {
      await source.applyOverrides(
        ReaderSettingsDefaults.overrides.copyWith(fontSize: size),
      );
      final pages = await source.loadChapter(29);
      final titlePage = pages.indexWhere(
        (page) => page.slices.any(
          (slice) =>
              slice.block.table?.cells.any(
                (cell) => cell.layout.text == '吊命',
              ) ??
              false,
        ),
      );
      final bodyPage = pages.indexWhere(
        (page) => page.slices.any(
          (slice) => slice.block.layout.text.startsWith('专属于守墓人，作为【死亡】的牧师'),
        ),
      );
      expect(titlePage, greaterThanOrEqualTo(0));
      expect(bodyPage, titlePage, reason: '吊命标题至少跟随正文首行');
      final slice = pages[bodyPage].slices.firstWhere(
        (slice) => slice.block.layout.text.startsWith('专属于守墓人，作为【死亡】的牧师'),
      );
      final body = slice.block;
      final line = body.layout.lines.first;
      final tag = line.inlineBoxes.single;
      final payload = tag.spec.payload! as PageBlock;
      // 原书 p.t-desc 和 span.t-tag 各声明 .8em，标签继承已缩放的父段落。
      expect(body.style!.fontSize, closeTo(size * .8, .001));
      expect(payload.layout.text, '【死亡】信仰');
      expect(payload.style!.fontSize, closeTo(size * .8 * .8, .001));
      expect(payload.style!.color.toARGB32(), 0xff9bb0d1);
      expect(payload.layout.lineCount, 1);
      expect(tag.spec.marginRight, 5);
      expect(tag.width, closeTo(payload.layout.width + 10, .01));
      expect(tag.left + tag.spec.outerWidth, lessThan(line.width));
      final baseline = line.baseline - line.top;
      final midpoint = baseline - tag.ascent + tag.spec.outerHeight / 2;
      expect(midpoint, closeTo(baseline - size * .8 / 4, .01));
      expect(line.height - baseline, greaterThanOrEqualTo(tag.descent - .001));
      expect(body.layout.text, endsWith('是否可以死去。'));
      expect(
        body.layout.lines.skip(1).every((line) => line.inlineBoxes.isEmpty),
        isTrue,
      );
      reports.add({
        'fontSize': size,
        'contentWidth': source.contentWidth,
        'contentHeight': source.contentHeight,
        'chapterPages': pages.length,
        'titlePageIndex': titlePage,
        'bodyPageIndex': bodyPage,
        'text': body.layout.text,
        'firstLineEnd': line.end,
        'lineWidth': line.width,
        'lineHeight': line.height,
        'tagLeft': tag.left,
        'tagWidth': tag.width,
        'tagHeight': tag.height,
        'tagMarginRight': tag.spec.marginRight,
        'tagFontSize': payload.style!.fontSize,
        'tagColor': payload.style!.color.toARGB32(),
      });
    }
    if (const bool.fromEnvironment('CSS_AUDIT_RENDER')) {
      await File('/tmp/zhushen-diaoming-layout.json')
          .writeAsString(const JsonEncoder.withIndent('  ').convert(reports));
    }
  }, skip: !book.existsSync());
}
