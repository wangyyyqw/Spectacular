import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/epub/epub_chapter_source.dart';
import 'package:reader_core/epub/epub_format_opener.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/paint/hit_test.dart';
import 'package:reader_core/paint/page_renderer.dart';
import 'package:reader_core/position/cfi.dart';
import 'package:reader_core/source/format_opener.dart';

import '../audit/audit_epub_fixture.dart';

const _size = Size(384, 853.3333333333334);
const _insets = EdgeInsets.fromLTRB(
  8.8,
  56.07500000000001,
  8.53333333333336,
  24.08888888888893,
);
final _paragraphs = [
  for (final word in ['ABCDE', 'FGHIJ', 'KLMNO', 'PQRST', 'UVWXY']) word * 5,
];

String _body(List<String> texts) =>
    '<div class="columns">${[for (final (i, text) in texts.indexed) '<p${i.isOdd ? ' style="font-family:monospace;"' : ''}>'
          '${i == 2 ? '<span style="font-weight:bold;">$text</span>' : text}</p>'].join()}</div><p>后续正文</p>';

Future<EpubChapterSource> _open(
  String body, {
  String css = '',
  ui.Image? image,
}) async {
  final files = <String, Object>{
    'mimetype': 'application/epub+zip',
    'META-INF/container.xml': '<container><rootfiles><rootfile full-path="book.opf"/></rootfiles></container>',
    'book.opf':
        '<package version="3.0" unique-identifier="id" xmlns="http://www.idpf.org/2007/opf">'
        '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="id">multicol</dc:identifier>'
        '<dc:title>多栏连续容器回归</dc:title></metadata><manifest>'
        '<item id="c" href="c.xhtml" media-type="application/xhtml+xml"/>'
        '<item id="i" href="red.png" media-type="image/png"/>'
        '</manifest><spine><itemref idref="c"/></spine></package>',
    'c.xhtml':
        '<html xmlns="http://www.w3.org/1999/xhtml"><head><style>'
        'body{margin:0;padding:0;font-family:Ahem;font-size:21px;color:black;}'
        'p{margin:0;padding:0;text-indent:0;text-align:left;}'
        '.columns{column-count:3;column-gap:1em;} $css'
        '</style></head><body>$body</body></html>',
  };
  if (image != null) {
    files['red.png'] = (await image.toByteData(format: ui.ImageByteFormat.png))!
        .buffer
        .asUint8List();
  }
  final source = await const EpubFormatOpener().openBytes(
    auditZip(files),
    options: ReaderOpenOptions(
      contentWidth: _size.width - _insets.horizontal,
      contentHeight: _size.height - _insets.vertical,
    ),
  );
  addTearDown(source.close);
  await source.applyOverrides(
    const ReaderOverrides(fontSize: 21, lineHeight: 1.6, paragraphSpacing: 10),
  );
  await source.applyContentSize(
    width: _size.width - _insets.horizontal,
    height: _size.height - _insets.vertical,
    topInset: _insets.top,
    sideInsets: (left: _insets.left, right: _insets.right),
  );
  return source;
}

Iterable<PageBlockSlice> _columnText(List<PageContent> pages) => [
  for (final page in pages)
    for (final slice in page.slices)
      if (slice.block.columnFragment != null) slice,
];

Future<ByteData> _paint(PageContent page, {ui.Image? image}) async {
  final recorder = ui.PictureRecorder();
  PagePainter(
    background: const Color(0xffffffff),
    imageLookup: (_) => image,
  ).paint(Canvas(recorder), page, pageSize: _size, pageInsets: _insets);
  final picture = recorder.endRecording();
  final rendered = await picture.toImage(384, 854);
  try {
    return (await rendered.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  } finally {
    rendered.dispose();
    picture.dispose();
  }
}

bool _colorAt(ByteData pixels, int x, int y, Color color) =>
    pixels.getUint32((y * 384 + x) * 4) ==
    ((color.r * 255).round() << 24 |
        (color.g * 255).round() << 16 |
        (color.b * 255).round() << 8 |
        (color.a * 255).round());

// 分隔线吸附到像素后，实色像素可能落在逻辑中心的相邻位置。
bool _lineColorAt(ByteData pixels, int x, int y, Color color) =>
    [for (var dx = -1; dx <= 1; dx++) _colorAt(pixels, x + dx, y, color)]
        .any((matches) => matches);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('五段作为一个容器连续排三列，保留字体、span、CFI与字符命中', () async {
    final source = await _open(_body(_paragraphs));
    final before = await source.loadAnchorChapter(0);
    final pages = await source.loadChapter(0);
    final page = pages.single;
    final bands = page.slices
        .where((slice) => slice.block.multicolContent != null)
        .toList();
    expect(bands, hasLength(1));
    expect(bands.single.block.multicol!.count, 3);
    final pieces = _columnText(pages).toList();
    expect(
      pieces.map((piece) => piece.block.layout.text).join(),
      _paragraphs.join(),
    );
    final lefts = pieces.map((piece) => piece.leftInset).toSet().toList()
      ..sort();
    expect(lefts, hasLength(3), reason: '段落流连续进入下一列');
    expect(lefts[1], closeTo(bands.single.block.multicol!.leftOf(1), .01));
    expect(
      pieces.any(
        (piece) => piece.block.style!.fontFamilies.contains('monospace'),
      ),
      isTrue,
    );
    expect(
      pieces.any(
        (piece) =>
            piece.block.layout.runs.any((run) => run.style.fontWeight == 700),
      ),
      isTrue,
    );
    var searchedThrough = 0;
    for (final piece in pieces) {
      final at = before.text.indexOf(piece.block.layout.text, searchedThrough);
      expect(at, greaterThanOrEqualTo(searchedThrough));
      searchedThrough = at + piece.block.layout.text.length;
      expect(
        EpubCfi.parse(piece.block.startCfi!)!
            .compareTo(EpubCfi.parse(before.cfiAt(at)!)!),
        0,
        reason: '原文位置 $at：${piece.block.startCfi} 应为 ${before.cfiAt(at)}',
      );
    }
    final boxes = TextHitTester.lineBoxes(page);
    final right = boxes.firstWhere(
      (box) =>
          box.slice.block.columnFragment != null &&
          box.rect.left > lefts[1] + 1,
    );
    final hit = TextHitTester.hitTest(page, right.rect.center)!;
    expect(hit.lineBox.sliceIndex, right.sliceIndex);
    expect((await source.loadAnchorChapter(0)).text, before.text);
    await _paint(page);
  });

  test('多栏两字对齐行不因画笔首端字距溢入列间距，选区与命中跟随文字', () async {
    final source = await _open(
      '<div class="columns"><p>${'率为ABCD' * 12}</p></div>',
      css: '.columns p{color:red;text-align:justify;word-break:normal;}',
    );
    final page = (await source.loadChapter(0)).single;
    final first = _columnText([page]).first;
    final layout = first.block.layout;
    final line = layout.lines.first;
    expect(layout.text.substring(line.start, line.end), '率为');
    expect(line.justifyExtra, greaterThan(21));
    final box = TextHitTester.lineBoxes(page)
        .firstWhere((box) => box.slice == first && box.lineIndex == 0);
    final selection = TextHitTester.selectionRects(box, 0, 2);
    expect(selection, isNotEmpty);
    expect(
      selection.map((rect) => rect.right).reduce((a, b) => a > b ? a : b),
      lessThanOrEqualTo(layout.maxWidth + .01),
      reason: '底层画笔的首端半字距不能成为额外的整行偏移',
    );
    final lastChar = TextHitTester.selectionRects(box, 1, 2).single;
    final hit = TextHitTester.hitTest(
      page,
      box.rect.topLeft + lastChar.center,
    )!;
    expect(hit.lineBox.slice, first);
    expect(hit.charOffset, greaterThanOrEqualTo(1));
    final pixels = await _paint(page);
    final gapStart = (_insets.left + box.rect.left + layout.maxWidth).ceil();
    final gapEnd = (_insets.left + _columnText([page]).skip(1).first.leftInset)
        .floor();
    final top = (_insets.top + box.rect.top).ceil();
    final bottom = (_insets.top + box.rect.bottom).floor();
    for (var y = top; y < bottom; y++) {
      for (var x = gapStart; x < gapEnd; x++) {
        expect(
          _colorAt(pixels, x, y, const Color(0xffff0000)),
          isFalse,
          reason: '行首的半字距不能把末字画进列距（$x,$y）',
        );
      }
    }
  });

  test('半em列距与分隔线使用整列带高度，最后短列不缩短外框', () async {
    final source = await _open(
      _body([..._paragraphs.take(4), 'UVWXY' * 2]),
      css:
          '.columns{column-gap:.5em;padding:6px;border:2px solid green;'
          'background:#ddf5ff;column-rule:2px solid red;}',
    );
    final page = (await source.loadChapter(0)).single;
    final band = page.slices.firstWhere(
      (slice) => slice.block.multicolContent != null,
    );
    final content = band.block.multicolContent!;
    expect(content.geometry.gap, closeTo(10.5, .001));
    final pixels = await _paint(page);
    final top = _insets.top + band.leadingExtent;
    final bottom = top + band.block.layout.height;
    final pieces = _columnText([page]).toList();
    final tallest = pieces
        .map((piece) => piece.absoluteTop! + piece.height)
        .reduce((a, b) => a > b ? a : b);
    expect(
      pieces.last.absoluteTop! + pieces.last.height,
      lessThan(tallest),
      reason: '末列确实比完整列带短，外框仍需覆盖完整列高',
    );
    for (var column = 1; column < 3; column++) {
      final x =
          (_insets.left +
                  content.container.contentLeft +
                  content.geometry.leftOf(column) -
                  content.geometry.gap / 2)
              .floor();
      expect(
        _colorAt(pixels, x, (top + 10).round(), const Color(0xffff0000)),
        isTrue,
        reason: '第 $column 条分隔线顶部 ($x, ${(top + 10).round()})',
      );
      expect(
        _colorAt(pixels, x, (bottom - 10).round(), const Color(0xffff0000)),
        isTrue,
        reason: '第 $column 条分隔线底部 ($x, ${(bottom - 10).round()})',
      );
    }
    final lastX =
        (_insets.left + content.container.left + content.container.width - 1)
            .floor();
    expect(
      _colorAt(pixels, lastX, (bottom - 2).floor(), const Color(0xff008000)),
      isTrue,
    );
    final after = TextHitTester.lineBoxes(page)
        .firstWhere((box) => box.text.contains('后续'));
    expect(after.rect.top, greaterThanOrEqualTo(bottom - _insets.top));
  });

  test('零列距不回退normal，column-width在手机宽度不足两列时保持单列', () async {
    final zero = await _open(
      _body(_paragraphs),
      css: '.columns{column-gap:0;}',
    );
    final zeroPage = (await zero.loadChapter(0)).single;
    final geometry = zeroPage.slices.first.block.multicol!;
    expect(geometry.gap, 0);
    expect(
      geometry.columnWidth,
      closeTo((_size.width - _insets.horizontal) / 3, .001),
    );
    final narrow = await _open(
      _body(_paragraphs.take(2).toList()),
      css: '.columns{column-count:auto;column-width:200px;}',
    );
    final pages = await narrow.loadChapter(0);
    expect(
      pages
          .expand((page) => page.slices)
          .every((slice) => slice.block.multicol == null),
      isTrue,
    );
    await _paint(zeroPage);
    await _paint(pages.first);
  });

  test('跨页列流不丢不重原文，首行样式只出现一次并保留续页文本位置', () async {
    final text = 'ABCDE' * 180;
    final source = await _open(
      _body([text, 'FGHIJ' * 25]),
      css: '.columns p:first-child::first-line{font-size:28px;color:red;}',
    );
    final original = await source.loadAnchorChapter(0);
    final pages = await source.loadChapter(0);
    expect(pages.length, greaterThan(1));
    final pieces = _columnText(pages).toList();
    expect(
      pieces.map((piece) => piece.block.layout.text).join(),
      text + 'FGHIJ' * 25,
    );
    final red = [
      for (final piece in pieces)
        for (final run in piece.block.layout.runs)
          if (run.style.color == const Color(0xffff0000)) run,
    ];
    expect(red, hasLength(1));
    expect(red.single.style.fontSize, 28);
    final continuation = pages[1].slices.first.block.startCfi!;
    expect(
      EpubCfi.parse(continuation)!
          .compareTo(EpubCfi.parse(original.cfiAt(0)!)!),
      greaterThan(0),
    );
    for (final page in pages) {
      expect(page.usedHeight, lessThanOrEqualTo(page.pageHeight + .1));
      await _paint(page);
    }
  });

  test('列内百分比图片与嵌套盒以单列为包含块，资源与后续文字均保留', () async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawColor(const Color(0xffff0000), BlendMode.src);
    final picture = recorder.endRecording();
    final image = await picture.toImage(64, 32);
    picture.dispose();
    addTearDown(image.dispose);
    final source = await _open(
      '<div class="columns"><div class="card">'
      '<img src="red.png" style="display:block;width:50%;height:auto;"/>'
      '<p>ABCDEABCDE</p></div><p>FGHIJFGHIJ</p><p>KLMNOKLMNO</p>'
      '</div><p>后续正文</p>',
      css: '.card{padding:4px;border:1px solid blue;}',
      image: image,
    );
    final page = (await source.loadChapter(0)).single;
    final band = page.slices.firstWhere(
      (slice) => slice.block.multicolContent != null,
    );
    final images = page.slices
        .where((slice) => slice.block.isReplaced)
        .toList();
    expect(images, hasLength(1));
    expect(
      images.single.block.style!.width!.resolve(
        _size.width - _insets.horizontal,
      ),
      closeTo((band.block.multicol!.columnWidth - 10) / 2, .01),
    );
    expect(
      _columnText([page]).map((piece) => piece.block.layout.text).join(),
      'ABCDEABCDEFGHIJFGHIJKLMNOKLMNO',
    );
    final pixels = await _paint(page, image: image);
    var count = 0;
    for (var y = 0; y < 854; y++) {
      for (var x = 0; x < 384; x++) {
        if (_colorAt(pixels, x, y, const Color(0xffff0000))) count++;
      }
    }
    expect(count, greaterThan(500));
  });

  test('嵌套多栏保留各自列宽、容器背景和连续文本', () async {
    final source = await _open(
      '<div class="columns"><div class="nested">'
      '<p>ABCDEABCDE</p><p>FGHIJFGHIJ</p></div><p>KLMNOKLMNO</p>'
      '</div><p>后续正文</p>',
      css:
          '.columns{column-count:2;column-rule:2px solid red;}'
          '.nested{column-count:2;column-gap:0;background:#eeeeff;column-rule:2px solid blue;}',
    );
    final original = await source.loadAnchorChapter(0);
    final page = (await source.loadChapter(0)).single;
    final bands = page.slices
        .where((slice) => slice.block.multicolContent != null)
        .toList();
    expect(bands, hasLength(2));
    expect(bands.last.overlay, isTrue);
    expect(
      bands.last.block.multicol!.columnWidth,
      closeTo(bands.first.block.multicol!.columnWidth / 2, .01),
    );
    expect(
      _columnText([page]).map((piece) => piece.block.layout.text).join(),
      'ABCDEABCDEFGHIJFGHIJKLMNOKLMNO',
    );
    final pixels = await _paint(page);
    final inner = bands.last.block.multicolContent!;
    final x =
        (_insets.left + inner.container.contentLeft + inner.geometry.leftOf(1))
            .floor();
    final y = (_insets.top + bands.last.absoluteTop! + 20).floor();
    expect(_lineColorAt(pixels, x, y, const Color(0xff0000ff)), isTrue);
    expect((await source.loadAnchorChapter(0)).text, original.text);
  });
}
