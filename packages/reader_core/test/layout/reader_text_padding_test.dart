import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/epub/epub_chapter_source.dart';
import 'package:reader_core/epub/epub_format_opener.dart';
import 'package:reader_core/paint/hit_test.dart';
import 'package:reader_core/source/format_opener.dart';
import 'package:reader_core/text/reader_text_overlay.dart';

import '../audit/audit_epub_fixture.dart';

const _padding = EdgeInsets.fromLTRB(0.4, 0.6, 0.5, 0.7);

Future<EpubChapterSource> _source(
  String text, {
  double width = 240,
  double height = 100,
}) async {
  final source = await const EpubFormatOpener().openBytes(
    auditZip({
      'mimetype': 'application/epub+zip',
      'META-INF/container.xml':
          '<container><rootfiles><rootfile full-path="book.opf"/>'
          '</rootfiles></container>',
      'book.opf':
          '<package version="3.0" unique-identifier="id" '
          'xmlns="http://www.idpf.org/2007/opf"><metadata '
          'xmlns:dc="http://purl.org/dc/elements/1.1/">'
          '<dc:identifier id="id">text-padding</dc:identifier>'
          '<dc:title>点九占位回归</dc:title></metadata><manifest>'
          '<item id="c" href="c.xhtml" media-type="application/xhtml+xml"/>'
          '</manifest><spine><itemref idref="c"/></spine></package>',
      'c.xhtml':
          '<html xmlns="http://www.w3.org/1999/xhtml"><head><style>'
          'body{margin:0;font:20px/1.2 Ahem}'
          'p{margin:0;text-indent:0;text-align:left}'
          '</style></head><body><p>$text</p></body></html>',
    }),
    options: ReaderOpenOptions(contentWidth: width, contentHeight: height),
  );
  addTearDown(source.close);
  return source;
}

Future<ReaderTextOverlay> _apply(
  EpubChapterSource source,
  int start,
  int end,
) async {
  final block = (await source.loadAnchorChapter(0)).blocks.single;
  final overlay = ReaderTextOverlay(
    startCfi: block.cfiAt(start)!,
    endCfi: block.cfiAt(end, end: true)!,
    paddingByTextHeight: _padding,
  );
  expect(await source.applyTextOverlays([overlay]), isTrue);
  return overlay;
}

Rect _bounds(PageLineBox line, int start, int end) {
  final text = TextHitTester.selectionRects(
    line,
    start,
    end,
  ).single.shift(line.rect.topLeft);
  final padding = _padding * text.height;
  return Rect.fromLTRB(
    text.left - padding.left,
    text.top - padding.top,
    text.right + padding.right,
    text.bottom + padding.bottom,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('四字背景的左右占位避开邻字，上下边角参与行高与页首尾裁边', () async {
    final source = await _source('前文彻底消失后文');
    final overlay = await _apply(source, 2, 6);
    final page = (await source.loadChapter(0)).single;
    final line = TextHitTester.lineBoxes(page).single;
    final bounds = _bounds(line, 2, 6);
    final before = TextHitTester.selectionRects(line, 0, 2).single;
    final after = TextHitTester.selectionRects(line, 6, 8).single;
    expect(bounds.left, greaterThanOrEqualTo(line.rect.left + before.right));
    expect(bounds.right, lessThanOrEqualTo(line.rect.left + after.left));
    expect(bounds.top, greaterThanOrEqualTo(-0.01));
    expect(bounds.bottom, lessThanOrEqualTo(page.usedHeight + 0.01));
    expect(page.usedHeight, greaterThan(24));
    expect(line.slice.block.offsetForCfi(overlay.startCfi), 2);
    expect(line.slice.block.offsetForCfi(overlay.endCfi), 6);
    expect(line.slice.block.layout.text, '前文彻底消失后文');
  });

  test('跨行背景每行预留两侧边角，跨页后仍完整且 CFI 不变', () async {
    const text = '甲乙丙丁戊己庚辛壬癸甲乙丙丁戊己庚辛壬癸甲乙丙丁';
    final source = await _source(text, width: 100);
    final overlay = await _apply(source, 0, text.length);
    final pages = await source.loadChapter(0);
    expect(pages.length, greaterThan(1));
    final lines = [for (final page in pages) ...TextHitTester.lineBoxes(page)];
    expect(lines.map((line) => line.text).join(), text);
    for (final page in pages) {
      for (final line in TextHitTester.lineBoxes(page)) {
        final bounds = _bounds(line, 0, line.text.length);
        expect(bounds.left, greaterThanOrEqualTo(-0.01));
        expect(bounds.right, lessThanOrEqualTo(100.01));
        expect(bounds.top, greaterThanOrEqualTo(-0.01));
        expect(bounds.bottom, lessThanOrEqualTo(page.usedHeight + 0.01));
      }
    }
    expect(lines.first.slice.block.offsetForCfi(overlay.startCfi), 0);
    expect(lines.last.slice.block.offsetForCfi(overlay.endCfi), text.length);
  });

  test('四字命中靠近行尾时重新断行，每个片段不覆盖未命中文字', () async {
    final source = await _source('前文彻底消失后文', width: 90);
    await _apply(source, 2, 6);
    final pages = await source.loadChapter(0);
    for (final page in pages) {
      for (final line in TextHitTester.lineBoxes(page)) {
        final start = (2 - line.blockTextOffset).clamp(0, line.text.length);
        final end = (6 - line.blockTextOffset).clamp(0, line.text.length);
        if (start == end) continue;
        final bounds = _bounds(line, start, end);
        expect(bounds.left, greaterThanOrEqualTo(-0.01));
        expect(bounds.right, lessThanOrEqualTo(90.01));
        if (start > 0) {
          final before = TextHitTester.selectionRects(line, 0, start).single;
          expect(
            bounds.left + 0.01,
            greaterThanOrEqualTo(line.rect.left + before.right),
          );
        }
        if (end < line.text.length) {
          final after = TextHitTester.selectionRects(
            line,
            end,
            line.text.length,
          ).single;
          expect(
            bounds.right - 0.01,
            lessThanOrEqualTo(line.rect.left + after.left),
          );
        }
      }
    }
  });

  test('只改颜色复用占位几何，移除点九占位恢复原排版', () async {
    final source = await _source('前文彻底消失后文');
    final original = (await source.loadChapter(0)).single;
    final overlay = await _apply(source, 2, 6);
    final padded = (await source.loadChapter(0)).single;
    expect(
      await source.applyTextOverlays([
        ReaderTextOverlay(
          startCfi: overlay.startCfi,
          endCfi: overlay.endCfi,
          paddingByTextHeight: _padding,
          color: 0xFFFF0000,
        ),
      ]),
      isFalse,
    );
    expect((await source.loadChapter(0)).single, same(padded));
    expect(await source.applyTextOverlays(const []), isTrue);
    final restored = (await source.loadChapter(0)).single;
    expect(restored.usedHeight, original.usedHeight);
    expect(restored.slices.single.block.layout.text, '前文彻底消失后文');
  });
}
