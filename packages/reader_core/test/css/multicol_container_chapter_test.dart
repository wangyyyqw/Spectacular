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

String _pageText(PageContent page) => [
  for (final slice in page.slices)
    for (final line in slice.block.layout.lines.sublist(
      slice.startLine,
      slice.endLine,
    ))
      slice.block.layout.text.substring(line.start, line.end),
].join();

void _expectVisibleText(List<PageContent> pages, String text) {
  expect(pages.map(_pageText).join(), text);
  for (final page in pages) {
    expect(page.usedHeight, lessThanOrEqualTo(page.pageHeight + .1));
    for (final box in TextHitTester.lineBoxes(page)) {
      expect(box.rect.bottom, lessThanOrEqualTo(page.pageHeight + .1));
    }
  }
}

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

  test('长嵌套多栏续排保留全部正文、可见行和递增文本位置', () async {
    final text = 'ABCDE' * 120;
    final source = await _open(
      '<div class="columns"><div class="nested"><p>$text</p></div>'
      '</div><p>后续正文</p>',
      css: '.columns{column-count:2;}.nested{column-count:2;column-gap:0;}',
    );
    final original = await source.loadAnchorChapter(0);
    final pages = await source.loadChapter(0);
    expect(pages.length, greaterThan(1));
    _expectVisibleText(pages, '$text后续正文');
    var offset = 0;
    for (final piece in _columnText(pages)) {
      expect(
        EpubCfi.parse(piece.block.startCfi!)!
            .compareTo(EpubCfi.parse(original.cfiAt(offset)!)!),
        0,
      );
      offset += piece.block.layout.text.length;
    }
    expect(offset, text.length);
  });

  for (final nested in [false, true]) {
    for (final declaration in [
      'break-before:page;page-break-before:always;',
      'break-after:page;page-break-after:always;',
    ]) {
      test('多栏${nested ? '嵌套' : '直接'}子块保留 $declaration', () async {
        final before = declaration.startsWith('break-before');
        final content =
            '<p${before ? '' : ' style="$declaration"'}>AAAA</p>'
            '<p${before ? ' style="$declaration"' : ''}>BBBB</p>';
        final source = await _open(
          '<div class="columns">'
          '${nested ? '<div class="nested">$content</div>' : content}'
          '</div><p>CCCC</p>',
          css: '.columns{column-count:2;}.nested{column-count:2;column-gap:0;}',
        );
        final pages = await source.loadChapter(0);
        _expectVisibleText(pages, 'AAAABBBBCCCC');
        final first = pages.indexWhere(
          (page) => _pageText(page).contains('AAAA'),
        );
        final second = pages.indexWhere(
          (page) => _pageText(page).contains('BBBB'),
        );
        expect(second, greaterThan(first), reason: '强制分页不能退化为换列');
      });
    }
  }

  test('多栏内绝对定位沿用页面坐标且不挤占列流高度', () async {
    final source = await _open(
      '<div class="columns"><p>AAAA</p>'
      '<p style="position:absolute;top:120px;left:90px;width:90px;">BBBB</p>'
      '<p>CCCC</p></div>',
      css: '.columns{column-count:2;}',
    );
    final control = await _open(
      '<div class="columns"><p>AAAA</p><p>CCCC</p></div>',
      css: '.columns{column-count:2;}',
    );
    final page = (await source.loadChapter(0)).single;
    final expected = (await control.loadChapter(0)).single;
    final located = page.slices.singleWhere(
      (slice) => slice.block.layout.text == 'BBBB',
    );
    expect(located.absoluteTop, closeTo(120, .1));
    expect(located.leftInset, closeTo(90, .1));
    expect(page.usedHeight, closeTo(expected.usedHeight, .01));
    final following = TextHitTester.lineBoxes(page)
        .singleWhere((box) => box.text == 'CCCC');
    final reference = TextHitTester.lineBoxes(expected)
        .singleWhere((box) => box.text == 'CCCC');
    expect(following.rect, reference.rect);
  });

  test('多栏内自动宽绝对定位重排保留行内字体和替换图片', () async {
    final source = await _open(
      '<div class="columns"><p>AAAA</p>'
      '<p style="position:absolute;top:120px;left:90px;">'
      '<span style="color:red;font-weight:bold;padding-left:2px;padding-right:3px;">BB</span>'
      '<img src="red.png" style="width:20px;height:16px;"/>DD</p>'
      '<p>CCCC</p></div>',
      css: '.columns{column-count:2;}',
    );
    final page = (await source.loadChapter(0)).single;
    final absolute = page.slices.singleWhere(
      (slice) => slice.block.layout.text.startsWith('BB'),
    );
    expect(absolute.absoluteTop, closeTo(120, .1));
    expect(absolute.leftInset, closeTo(90, .1));
    expect(
      absolute.block.layout.runs.any(
        (run) =>
            run.start == 0 &&
            run.style.color == const Color(0xffff0000) &&
            run.style.fontWeight == 700,
      ),
      isTrue,
    );
    final image = absolute.lines
        .expand((line) => line.inlineBoxes)
        .singleWhere((box) => box.spec.replacesPlaceholder);
    expect(image.width, closeTo(20, .01));
    expect(image.height, closeTo(16, .01));
    final spacing = absolute.lines
        .expand((line) => line.inlineBoxes)
        .where((box) => !box.spec.replacesPlaceholder)
        .fold(0.0, (width, box) => width + box.width);
    expect(spacing, closeTo(5, .01), reason: '重排只保留一份作者行内留白');
  });

  test('浮动多栏以单列宽测量正文，后文沿整盒绕排', () async {
    final text = 'ABCD' * 4;
    final source = await _open(
      '<div class="floating"><p>$text</p><p>BB</p></div><p>CCCC</p>',
      css: '.floating{float:left;width:120px;column-count:2;column-gap:0;}',
    );
    final page = (await source.loadChapter(0)).single;
    _expectVisibleText([page], '${text}BBCCCC');
    final boxes = TextHitTester.lineBoxes(page);
    final floated = boxes.firstWhere(
      (box) => box.slice.block.columnFragment != null,
    );
    final following = boxes.firstWhere((box) => box.text.contains('CCCC'));
    expect(following.rect.top, lessThan(floated.rect.bottom));
    expect(following.rect.bottom, greaterThan(floated.rect.top));
    expect(following.rect.left, greaterThanOrEqualTo(119.9));
    for (final piece in _columnText([page])) {
      expect(piece.block.layout.maxWidth, closeTo(60, .01));
      for (final line in piece.lines) {
        expect(line.width, lessThanOrEqualTo(60.01));
      }
    }
    await _paint(page);
  });

  test('窄父盒中的右浮动多栏只平移一次，并保留内部装饰', () async {
    final source = await _open(
      '<div class="host"><div class="floating"><div class="card">'
      '<p>ABCD</p><p>EFGH</p></div></div><p>CCCC</p></div>',
      css:
          '.host{width:280px;margin-left:16px;padding:8px;border:2px solid blue;}'
          '.floating{float:right;width:120px;column-count:2;column-gap:0;}'
          '.card{border:1px solid green;}',
    );
    final page = (await source.loadChapter(0)).single;
    _expectVisibleText([page], 'ABCDEFGHCCCC');
    final floated = _columnText([page]).toList();
    final boxes = TextHitTester.lineBoxes(page);
    final following = boxes.firstWhere((box) => box.text == 'CCCC');
    final first = boxes.firstWhere((box) => box.slice == floated.first);
    expect(first.rect.left, closeTo(16 + 10 + 280 - 120 + 1, .01));
    expect(following.rect.left, closeTo(26, .01));
    expect(following.rect.right, lessThan(first.rect.left));
    expect(following.rect.top, lessThan(first.rect.bottom));
    expect(
      floated.first.block.containers.any(
        (fragment) =>
            fragment.container.style.borders.left.color ==
            const Color(0xff008000),
      ),
      isTrue,
    );
    await _paint(page);
  });

  test('浮动与普通长多栏出现在同章时，两种列流都完整展开', () async {
    final text = 'ABCDE' * 180;
    final source = await _open(
      '<div class="floating"><p>AA</p><p>BB</p></div>'
      '<div class="columns"><p>$text</p></div><p>后续正文</p>',
      css:
          '.floating{float:left;width:120px;column-count:2;column-gap:0;}'
          '.columns{column-count:2;}',
    );
    final pages = await source.loadChapter(0);
    expect(pages.length, greaterThan(1));
    _expectVisibleText(pages, 'AABB$text后续正文');
    final firstPage = TextHitTester.lineBoxes(pages.first);
    final lastFloatBottom = firstPage
        .where((box) => box.text == 'AA' || box.text == 'BB')
        .map((box) => box.rect.bottom)
        .reduce((a, b) => a > b ? a : b);
    final ordinary = firstPage.firstWhere(
      (box) => box.text.startsWith('ABCDE'),
    );
    expect(ordinary.rect.top, greaterThanOrEqualTo(lastFloatBottom));
  });

  test('长浮动多栏跨页保留全部正文与后续普通段落', () async {
    final text = 'ABCDE' * 120;
    final source = await _open(
      '<div class="floating"><p>$text</p></div><p>后续正文</p>',
      css: '.floating{float:left;width:120px;column-count:2;column-gap:0;}',
    );
    final pages = await source.loadChapter(0);
    expect(pages.length, greaterThan(1));
    _expectVisibleText(pages, '$text后续正文');
  });

  test('三层长多栏跨页保留全文和可见范围', () async {
    final text = 'ABCDE' * 120;
    final source = await _open(
      '<div class="columns"><div class="nested"><div class="inner">'
      '<p>$text</p></div></div></div><p>后续正文</p>',
      css:
          '.columns{column-count:2;}'
          '.nested,.inner{column-count:2;column-gap:0;}',
    );
    final pages = await source.loadChapter(0);
    expect(pages.length, greaterThan(1));
    _expectVisibleText(pages, '$text后续正文');
  });

  test('嵌套多栏在页末预留底边框与内边距', () async {
    final source = await _open(
      '<p class="before">PRE</p><div class="columns">'
      '<div class="nested"><p>AB</p></div></div><p>END</p>',
      css:
          '.before{height:690px;}.columns{column-count:2;}'
          '.nested{column-count:2;column-gap:0;padding-bottom:18px;border-bottom:2px solid red;}',
    );
    final pages = await source.loadChapter(0);
    _expectVisibleText(pages, 'PREABEND');
    for (final page in pages) {
      for (final slice in page.slices.where((slice) => slice.overlay)) {
        expect(
          slice.absoluteTop! + slice.height,
          lessThanOrEqualTo(page.pageHeight + .1),
        );
      }
    }
  });

  for (final hasFloat in [false, true]) {
    test('顶层多栏末片底装饰不越页（同章浮动：$hasFloat）', () async {
      final text = 'A' * 368;
      final source = await _open(
        '<div class="columns"><p>$text</p></div>'
        '${hasFloat ? '<p style="float:right;width:30px;">D</p>' : ''}',
        css: '.columns{column-count:2;padding-bottom:18px;border-bottom:2px solid red;}',
      );
      final pages = await source.loadChapter(0);
      expect(pages.length, greaterThan(1));
      _expectVisibleText(pages, '$text${hasFloat ? 'D' : ''}');
      final last = pages.last.slices.firstWhere(
        (slice) => slice.block.multicolContent != null,
      );
      expect(last.trailingExtent, greaterThanOrEqualTo(20));
    });
  }

  test('多栏末片同时预留子段和容器的底装饰', () async {
    final text = 'A' * 352;
    final source = await _open(
      '<div class="columns"><p>$text</p></div>',
      css:
          '.columns{column-count:2;padding-bottom:18px;border-bottom:2px solid red;}'
          '.columns>p{padding-bottom:20px;}',
    );
    final pages = await source.loadChapter(0);
    _expectVisibleText(pages, text);
    expect(pages.length, greaterThan(1));
    final last = pages.last.slices.firstWhere(
      (slice) => slice.block.multicolContent != null,
    );
    expect(last.trailingExtent, greaterThanOrEqualTo(20));
  });

  test('能放入下一外列的嵌套多栏遵守避免内部断列', () async {
    final source = await _open(
      '<div class="columns"><p>PRE</p><div class="nested">'
      '<p>A<br/>B<br/>C<br/>D<br/>E<br/>F</p></div></div>',
      css:
          '.columns{column-count:2;}'
          '.nested{column-count:2;column-gap:0;break-inside:avoid;}',
    );
    final page = (await source.loadChapter(0)).single;
    final nested = page.slices.where(
      (slice) => slice.overlay && slice.block.multicolContent != null,
    );
    expect(nested, hasLength(1));
    final boxes = TextHitTester.lineBoxes(page);
    final before = boxes.firstWhere((box) => box.text == 'PRE');
    final first = boxes.firstWhere((box) => box.text == 'A');
    expect(first.rect.left, greaterThan(before.rect.right));
  });

  test('短嵌套多栏保留作者最小高度', () async {
    final source = await _open(
      '<div class="columns"><div class="nested"><p>A</p></div><p>B</p></div>',
      css:
          '.columns{column-count:2;}'
          '.nested{column-count:2;column-gap:0;min-height:100px;}',
    );
    final page = (await source.loadChapter(0)).single;
    final inner = page.slices.singleWhere(
      (slice) => slice.overlay && slice.block.multicolContent != null,
    );
    expect(inner.block.layout.height, closeTo(100, .01));
    expect(page.usedHeight, greaterThanOrEqualTo(100));
    _expectVisibleText([page], 'AB');
  });

  for (final mode in ['普通列流', '同章浮动', '自身浮动']) {
    test('$mode 保留多栏最小高度及后续正文位置', () async {
      final source = await _open(
        '${mode == '同章浮动' ? '<p style="float:right;width:30px;">D</p>' : ''}'
        '<div class="columns"><p>A</p></div><p>${'C' * 120}</p>',
        css:
            '.columns{width:120px;column-count:2;column-gap:0;min-height:100px;'
            '${mode == '自身浮动' ? 'float:left;' : ''}}',
      );
      final page = (await source.loadChapter(0)).single;
      final anchor = page.slices.singleWhere(
        (slice) => slice.block.multicolContent != null,
      );
      expect(anchor.block.layout.height, closeTo(100, .01));
      final boxes = TextHitTester.lineBoxes(page);
      final columnTop = boxes.singleWhere((box) => box.text == 'A').rect.top;
      final following = boxes.where((box) => box.text.startsWith('C'));
      if (mode == '自身浮动') {
        final floatBottom = anchor.absoluteTop! + anchor.height;
        for (final box in following.where(
          (box) => box.rect.top < floatBottom - .1,
        )) {
          expect(box.rect.left, greaterThanOrEqualTo(119.9));
        }
        expect(following.last.rect.left, lessThan(119.9));
      } else {
        expect(following.first.rect.top, greaterThanOrEqualTo(columnTop + 100));
      }
      _expectVisibleText([page], '${mode == '同章浮动' ? 'D' : ''}A${'C' * 120}');
    });
  }

  test('连续分页声明和三层首子分页不制造空页', () async {
    final source = await _open(
      '<p style="break-after:page;">AAAA</p><div class="columns">'
      '<div class="nested"><div class="inner">'
      '<p style="break-before:page;">BBBB</p></div></div></div>',
      css:
          '.columns{column-count:2;}'
          '.nested,.inner{column-count:2;column-gap:0;}',
    );
    final pages = await source.loadChapter(0);
    expect(pages.map(_pageText), ['AAAA', 'BBBB']);
  });
}
