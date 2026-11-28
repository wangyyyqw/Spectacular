import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/paint/page_renderer.dart';
import 'package:reader_core/epub/epub_chapter_source.dart';
import 'package:reader_ui/panels/settings_panel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final book = File('../../test_corpus/real/zhushen-yuxi.epub');

  for (final readerSettings in [false, true]) {
    test('诸神愚戏天赋：${readerSettings ? "手机默认设置" : "作者样式"}下62张卡片完整排版', () async {
      final source = await EpubChapterSource.open(
        book.readAsBytesSync(),
        contentWidth: 350,
        contentHeight: 800,
        verifyCrc: false,
      );
      if (readerSettings) {
        await source.applyOverrides(ReaderSettingsDefaults.overrides);
      }
      final pages = await source.loadChapter(29);
      final blocks = <PageBlock>{
        for (final page in pages)
          for (final slice in page.slices) slice.block,
      };
      final tags = <InlineBoxPlacement>[
        for (final block in blocks)
          for (final line in block.layout.lines)
            ...line.inlineBoxes.where((box) => box.spec.payload is PageBlock),
      ];
      final ranks = <InlineBoxPlacement>[
        for (final block in blocks)
          if (block.table != null)
            for (final cell in block.table!.cells)
              for (final line in cell.layout.lines)
                ...line.inlineBoxes.where(
                  (box) => box.spec.payload is PageBlock,
                ),
      ];
      expect(tags, hasLength(62));
      expect(ranks, hasLength(62));
      final first = tags.first.spec.payload! as PageBlock;
      expect(first.layout.text, '【虚无】命途 / 主动');
      final description = blocks.firstWhere(
        (block) => block.layout.text.startsWith('你与你的影子'),
      );
      expect(
        first.style!.fontSize,
        closeTo(description.style!.fontSize * .8, .001),
      );
      expect(first.style!.padding.horizontal, 8);
      expect(tags.first.spec.marginRight, 5);
      for (final block in blocks) {
        for (final line in block.layout.lines) {
          for (final tag in line.inlineBoxes.where(
            (box) => box.spec.payload is PageBlock,
          )) {
            expect(tag.spec.verticalAlign, InlineBoxVerticalAlign.middle);
            final baseline = line.baseline - line.top;
            final midpoint = baseline - tag.ascent + tag.spec.outerHeight / 2;
            final parent = block.style!;
            final halfXHeight =
                parent.fontSize * (parent.fontSizeAdjust ?? .5) / 2;
            expect(midpoint, closeTo(baseline - halfXHeight, .01));
            expect(
              line.height - baseline,
              greaterThanOrEqualTo(tag.descent - .001),
            );
          }
        }
      }
      for (final box in [...tags, ...ranks]) {
        final payload = box.spec.payload! as PageBlock;
        expect(payload.style!.borders.hasBorder, isTrue);
        expect(payload.layout.lineCount, 1);
        expect(box.width, greaterThan(payload.layout.width));
        expect(box.height, greaterThan(payload.layout.height));
      }
      for (final page in pages) {
        // 章首出血页可用负 topPadding 回收顶部空间，应校验内容底部而非
        // 单独比较 usedHeight。
        expect(
          page.topPadding + page.usedHeight,
          lessThanOrEqualTo(source.contentHeight + 2),
        );
      }
      // 仅审计时导出真实章节图像，常规回归不产生工作区文件。
      if (const bool.fromEnvironment('CSS_AUDIT_RENDER')) {
        for (var i = 0; i < 4 && i < pages.length; i++) {
          final recorder = ui.PictureRecorder();
          const PagePainter(background: ui.Color(0xfff4f0e7)).paint(
            ui.Canvas(recorder),
            pages[i],
            pageSize: const ui.Size(350, 800),
          );
          final image = await recorder.endRecording().toImage(350, 800);
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('/tmp/zhushen-talent-page-${i + 1}.png')
              .writeAsBytes(png!.buffer.asUint8List());
          image.dispose();
        }
      }
    }, skip: !book.existsSync());
  }
}
