import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/api.dart'
    show ReaderTextOverlay, ReaderTextOverlayResolver;
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/paint/hit_test.dart';
import 'package:reader_core/paint/page_renderer.dart';
import 'package:reader_core/position/cfi.dart';

const _baseCfi = 'epubcfi(/6/2!/4/2/1:9)';
const _size = Size(200, 200);

ComputedStyle _style() => ComputedStyle(const {
  'font-size': '16px',
  'line-height': '1.5',
  'font-family': 'Ahem',
  'column-count': '2',
  'column-gap': '16px',
});

List<PageContent> _pages(String text, {double pageHeight = 200}) {
  final style = _style();
  return Paginator(pageHeight: pageHeight)
      .measureChapter(
        blocks: [
          PageBlock.styled(
            layout: TextLayoutEngine.layout(
              text: text,
              style: style,
              maxWidth: _size.width,
            ),
            style: style,
            startCfi: _baseCfi,
            containingWidth: _size.width,
            textRuleEligible: false,
          ),
        ],
      )
      .pages;
}

Future<ByteData> _paint(PageContent page, ReaderTextOverlay overlay) async {
  final recorder = ui.PictureRecorder();
  PagePainter(textOverlays: [overlay])
      .paint(Canvas(recorder), page, pageSize: _size);
  final picture = recorder.endRecording();
  final image = await picture.toImage(
    _size.width.round(),
    _size.height.round(),
  );
  picture.dispose();
  final pixels = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  return pixels!;
}

int _redPixels(ByteData pixels, int left, int right) {
  var count = 0;
  for (var y = 0; y < _size.height; y++) {
    for (var x = left; x < right; x++) {
      final offset = (y * _size.width.round() + x) * 4;
      if (pixels.getUint32(offset) == 0xff0000ff) count += 1;
    }
  }
  return count;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('列片段 CFI 起止累加原块偏移，跨页列流仍对应完整原文', () {
    final text = 'ABCDEFGHIJ' * 10;
    final pages = _pages(text, pageHeight: 60);
    expect(pages.length, greaterThan(1));
    var consumed = 0;
    for (final slice in pages.expand((page) => page.slices)) {
      final fragment = slice.block;
      expect(cfiCharOffset(fragment.startCfi!), 9 + consumed);
      expect(fragment.textRuleEligible, isFalse);
      final until = consumed + fragment.layout.text.length;
      expect(cfiCharOffset(fragment.endCfi!), 9 + until);
      expect(fragment.layout.text, text.substring(consumed, until));
      consumed = until;
    }
    expect(consumed, text.length);
  });

  test('第二列命中与选区 CFI 对应原文，不回退到第一列', () {
    const text = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcd';
    final page = _pages(text).single;
    final secondSlice = page.slices[1];
    final lineBox = TextHitTester.lineBoxes(page)
        .firstWhere((box) => box.sliceIndex == 1);
    final hit = TextHitTester.hitTest(
      page,
      Offset(lineBox.rect.left + 16.2, lineBox.rect.center.dy),
    )!;
    expect(hit.sliceIndex, 1);
    final fragmentStart = page.slices.first.block.layout.text.length;
    final localOffset = hit.lineBox.blockTextOffset + hit.charOffset;
    final offset = cfiCharOffset(secondSlice.block.startCfi!)! + localOffset;
    expect(offset, 9 + fragmentStart + localOffset);
    expect(
      secondSlice.block.layout.text.substring(localOffset, localOffset + 1),
      text.substring(offset - 9, offset - 8),
    );
    final selection = ReaderTextOverlay(
      startCfi: cfiWithCharOffset(_baseCfi, offset),
      endCfi: cfiWithCharOffset(_baseCfi, offset + 1),
      color: 0xffff0000,
    );
    final resolver = ReaderTextOverlayResolver([selection], typography: false);
    final first = page.slices.first.block;
    expect(
      resolver.resolve(
        blockCfi: first.startCfi,
        text: first.layout.text,
        style: first.style!,
        runs: first.layout.runs,
      ),
      same(first.layout.runs),
    );
    final second = secondSlice.block;
    final runs = resolver.resolve(
      blockCfi: second.startCfi,
      text: second.layout.text,
      style: second.style!,
      runs: second.layout.runs,
    );
    expect(runs.single.start, localOffset);
    expect(runs.single.end, localOffset + 1);
  });

  test('原文第二列区间仅给第二列着色', () async {
    final page = _pages('ABCDEFGHIJKLMNOPQRSTUVWXYZabcd').single;
    final start = cfiCharOffset(page.slices[1].block.startCfi!)!;
    final pixels = await _paint(
      page,
      ReaderTextOverlay(
        startCfi: cfiWithCharOffset(_baseCfi, start + 1),
        endCfi: cfiWithCharOffset(_baseCfi, start + 3),
        color: 0xffff0000,
      ),
    );
    final secondColumnLeft = page.slices[1].leftInset.round();
    expect(_redPixels(pixels, 0, secondColumnLeft), 0);
    expect(
      _redPixels(pixels, secondColumnLeft, _size.width.round()),
      greaterThan(0),
    );
  });
}
