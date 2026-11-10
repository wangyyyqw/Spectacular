import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/paint/page_renderer.dart';
import 'package:reader_core/parser/document_parser.dart';
import 'package:reader_mobile/reader/epub_chapter_source.dart';
import 'package:reader_ui/panels/settings_panel.dart';

Iterable<ParsedElement> _elements(ParsedElement node) sync* {
  yield node;
  for (final child in node.children.whereType<ParsedElement>()) {
    yield* _elements(child);
  }
}

String _text(ParsedNode node) => switch (node) {
  ParsedText() => node.text,
  ParsedElement() => node.children.map(_text).join(),
};

String _visibleText(PageBlockSlice slice) => [
  for (final line in slice.lines)
    slice.block.layout.text.substring(line.start, line.end),
].join();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final book = File('../../test_corpus/real/zhushen-yuxi.epub');

  for (final readerSettings in [false, true]) {
    test('职业章${readerSettings ? '手机设置' : '作者样式'}：63张卡片续框且正文完整', () async {
      final source = await EpubChapterSource.open(
        book.readAsBytesSync(),
        contentWidth: 350,
        contentHeight: 800,
        verifyCrc: false,
      );
      addTearDown(source.close);
      if (readerSettings) {
        await source.applyOverrides(ReaderSettingsDefaults.overrides);
      }
      final pages = await source.loadChapter(28);
      final slices = pages.expand((page) => page.slices).toList();
      final tags = slices.where((slice) => slice.block.floatSide != null);
      expect(tags, hasLength(63));
      final descriptions = _elements(source.document.parseDocument(28).root)
          .where((node) => node.attributes['class'] == 'job-desc');
      expect(descriptions, hasLength(63));
      for (final description in descriptions) {
        final cfi = description.children
            .whereType<ParsedText>()
            .first
            .cfi
            .serialize();
        final text = slices
            .where((slice) => slice.block.startCfi == cfi)
            .map(_visibleText)
            .join();
        expect(text, _text(description).trim());
      }
      for (final page in pages) {
        expect(
          page.topPadding + page.usedHeight,
          lessThanOrEqualTo(source.contentHeight),
          reason: '首页顶部出血的负偏移参与实际页底坐标',
        );
        expect(
          page.slices.every(
            (slice) => slice.block.containers.every(
              (fragment) =>
                  !fragment.container.style.borders.hasBorder ||
                  fragment.container.cloneDecoration,
            ),
          ),
          isTrue,
        );
      }
      if (const bool.fromEnvironment('CSS_AUDIT_RENDER')) {
        for (var i = 0; i < 8 && i < pages.length; i++) {
          final recorder = ui.PictureRecorder();
          const PagePainter().paint(
            ui.Canvas(recorder),
            pages[i],
            pageSize: const ui.Size(350, 800),
          );
          final picture = recorder.endRecording();
          final image = await picture.toImage(350, 800);
          picture.dispose();
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            '/tmp/zhushen-job-${readerSettings ? 'reader' : 'author'}-${i + 1}.png',
          ).writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        }
      }
    }, skip: !book.existsSync());
  }
}
