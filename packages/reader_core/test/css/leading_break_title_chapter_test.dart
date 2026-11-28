import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/epub/epub_chapter_source.dart';
import 'package:reader_core/epub/epub_format_opener.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/paint/page_renderer.dart';
import 'package:reader_core/parser/cfi_binder.dart';
import 'package:reader_core/source/format_opener.dart';

import '../audit/audit_epub_fixture.dart';

const _pageSize = Size(384, 853.3333333333333);
const _pageInsets = EdgeInsets.fromLTRB(
  8.8,
  22.311111111111124,
  8.53333333333336,
  24.08888888888893,
);
const _css = '''
h2 { font-family:Ahem; text-align:right; font-weight:900;
  font-size:.8em; margin:-1em 1em 2em 0; color:#ddedfd; line-height:160%; }
h2 b { font-size:1.1em; padding:15px; border-radius:5px;
  border-top:1px solid #ddedfd; border-bottom:1px solid #ddedfd; }
''';

Future<EpubChapterSource> _open(
  String contents, {
  String tag = 'h2',
  String extraCss = '',
}) async {
  final bytes = auditZip({
    'mimetype': 'application/epub+zip',
    'META-INF/container.xml':
        '<container><rootfiles><rootfile '
        'full-path="book.opf"/></rootfiles></container>',
    'book.opf':
        '<package version="3.0" unique-identifier="id" '
        'xmlns="http://www.idpf.org/2007/opf"><metadata '
        'xmlns:dc="http://purl.org/dc/elements/1.1/">'
        '<dc:identifier id="id">leading-break-title</dc:identifier>'
        '<dc:title>标题首行换行回归</dc:title></metadata><manifest>'
        '<item id="c" href="c.xhtml" media-type="application/xhtml+xml"/>'
        '<item id="pic" href="pic.svg" media-type="image/svg+xml"/>'
        '</manifest><spine><itemref idref="c"/></spine></package>',
    'c.xhtml':
        '<html xmlns="http://www.w3.org/1999/xhtml"><head>'
        '<style>$_css$extraCss</style></head>'
        '<body><$tag>$contents</$tag></body></html>',
    'pic.svg':
        '<svg xmlns="http://www.w3.org/2000/svg" width="20" height="10">'
        '<rect width="20" height="10" fill="red"/></svg>',
  });
  final source = await const EpubFormatOpener().openBytes(
    bytes,
    options: const ReaderOpenOptions(
      contentWidth: 366.6666666666667,
      contentHeight: 806.9333333333333,
    ),
  );
  addTearDown(source.close);
  await source.applyOverrides(
    const ReaderOverrides(fontSize: 17, lineHeight: 1.6, paragraphSpacing: 10),
  );
  return source;
}

Future<ByteData> _render(PageContent page) async {
  final recorder = ui.PictureRecorder();
  const PagePainter().paint(
    Canvas(recorder),
    page,
    pageSize: _pageSize,
    pageInsets: _pageInsets,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(384, 854);
  try {
    return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  } finally {
    image.dispose();
    picture.dispose();
  }
}

List<int> _borderBands(ByteData bytes) {
  final bands = <int>[];
  var previous = false;
  for (var y = 0; y < 150; y++) {
    var count = 0;
    for (var x = 280; x < 375; x++) {
      if (_borderPixel(bytes, x, y)) count++;
    }
    final current = count >= 40;
    if (current && !previous) bands.add(y);
    previous = current;
  }
  return bands;
}

bool _borderPixel(ByteData bytes, int x, int y) {
  final offset = (y * 384 + x) * 4;
  return bytes.getUint8(offset) < 245 &&
      bytes.getUint8(offset + 1) > 210 &&
      bytes.getUint8(offset + 2) > 245;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('标题块首显式换行保留一行，文字上下边框完整显示', () async {
    final source = await _open('<br/><b>简介</b>');
    final page = (await source.loadChapter(0)).single;
    final layout = page.slices.single.block.layout;
    expect(layout.text, '简介');
    expect(layout.lines, hasLength(2));
    expect(layout.lines[1].top - layout.lines[0].top, closeTo(21.76, .01));
    final titleRun = layout.runs
        .where((run) => !run.syntheticFontFallback)
        .single;
    expect(titleRun.style.fontSize, closeTo(14.96, .001));
    expect(titleRun.style.lineHeight, closeTo(21.76, .001));
    expect(titleRun.style.unitlessLineHeightFactor, isNull);
    final bands = _borderBands(await _render(page));
    expect(bands, hasLength(2), reason: '上下装饰线都应位于屏幕内');
    expect(bands.first, greaterThan(0));
  });

  test('仅上下边框的行内标题按五像素圆角弯曲，保留边框中段', () async {
    final rounded = await _open('<br/><b>简介</b>');
    final square = await _open(
      '<br/><b>简介</b>',
      extraCss: 'h2 b { border-radius:0; }',
    );
    final roundedPage = (await rounded.loadChapter(0)).single;
    final squarePage = (await square.loadChapter(0)).single;
    expect(
      roundedPage.slices.single.block.layout.height,
      squarePage.slices.single.block.layout.height,
    );
    final roundedBytes = await _render(roundedPage);
    final squareBytes = await _render(squarePage);
    var removedCorners = 0;
    var addedArcs = 0;
    var retainedPixels = 0;
    for (var y = 0; y < 150; y++) {
      for (var x = 280; x < 375; x++) {
        final curved = _borderPixel(roundedBytes, x, y);
        final straight = _borderPixel(squareBytes, x, y);
        if (straight && !curved) removedCorners++;
        if (curved && !straight) addedArcs++;
        if (curved && straight) retainedPixels++;
      }
    }
    expect(removedCorners, greaterThan(0), reason: '方角端点应让出圆角外的区域');
    expect(addedArcs, greaterThan(0), reason: '边框应沿五像素半径弯曲，不能只裁掉端点');
    expect(retainedPixels, greaterThan(60), reason: '顶底边框中段均应保留');
  });

  test('跨三行的行内边框中段沿用直边，不新增片段圆角', () async {
    const fragmentCss =
        'h2 { width:100px; margin:0; text-align:left; '
        'line-height:4; word-break:break-all; } h2 b { padding:4px; }';
    final rounded = await _open(
      '<b>ABCDEFGHIJKLMNO</b>',
      extraCss: fragmentCss,
    );
    final square = await _open(
      '<b>ABCDEFGHIJKLMNO</b>',
      extraCss: '$fragmentCss h2 b { border-radius:0; }',
    );
    final roundedPage = (await rounded.loadChapter(0)).single;
    final squarePage = (await square.loadChapter(0)).single;
    final slice = roundedPage.slices.single;
    final lines = slice.block.layout.lines;
    expect(lines, hasLength(3));
    final roundedBytes = await _render(roundedPage);
    final squareBytes = await _render(squarePage);
    final top =
        _pageInsets.top +
        roundedPage.topPadding +
        slice.leadingExtent +
        lines[1].top;
    var differences = 0;
    for (var y = top.ceil(); y < (top + lines[1].height).floor(); y++) {
      for (var x = 0; x < 150; x++) {
        final offset = (y * 384 + x) * 4;
        if (roundedBytes.getUint32(offset) != squareBytes.getUint32(offset)) {
          differences++;
        }
      }
    }
    expect(differences, 0, reason: '中间片段不是元素真实左右边界，本次不能新增圆弧');
  });

  test('连续首行换行与锚点原文坐标保持一致', () async {
    final source = await _open(' \n<br/>\n<br/> <b>简介</b>');
    final page = (await source.loadChapter(0)).single;
    final layout = page.slices.single.block.layout;
    expect(layout.text, '简介');
    expect(layout.lines, hasLength(3));
    expect(
      layout.runs.where((run) => !run.syntheticFontFallback).single.start,
      0,
    );
    final chapter = await source.loadAnchorChapter(0);
    expect(chapter.text, layout.text);
    // 以原 XHTML 的字符节点为准；两个 br 和 b 均参与标准 CFI 步进。
    final bound = CfiBinder.bind(
      xhtml: '<html><body><h2> \n<br/>\n<br/> <b>简介</b></h2></body></html>',
      spineIndex: 0,
    );
    final savedCfi = bound.textNodes
        .singleWhere((node) => node.text == '简介')
        .baseCfi
        .withCharOffset(1)
        .serialize();
    expect(chapter.cfiAt(1), savedCfi);
    expect(chapter.offsetFor(savedCfi), 1);
    expect(chapter.text.substring(chapter.offsetFor(savedCfi)!), '介');
  });

  test('普通源码换行仍折叠，不增加标题空行', () async {
    final source = await _open(' \n<b>简介</b> \n');
    final layout = (await source.loadChapter(0))
        .single
        .slices
        .single
        .block
        .layout;
    expect(layout.text, '简介');
    expect(layout.lines, hasLength(1));
    expect(layout.lines.single.start, 0);
  });

  test('纯 br 块通过正式排版保留两个空行', () async {
    final source = await _open('<br/><br/>');
    final layout = (await source.loadChapter(0))
        .single
        .slices
        .single
        .block
        .layout;
    expect(layout.text, isEmpty);
    expect(layout.lines, hasLength(2));
    expect(layout.height, closeTo(43.52, .01));
    expect(
      layout.lines.every((line) => line.start == 0 && line.end == 0),
      isTrue,
    );
    expect((await source.loadAnchorChapter(0)).text, isEmpty);
  });

  test('块首 br 后的图片保留空行与原有占位坐标', () async {
    final source = await _open(
      '<br/><img src="pic.svg" width="20" height="10"/>',
    );
    final block = (await source.loadChapter(0)).single.slices.single.block;
    expect(block.layout.text, '\uFFFC');
    expect(block.layout.lines, hasLength(2));
    expect(block.layout.lines.first.start, 0);
    expect(block.layout.lines.first.end, 0);
    expect(block.layout.lines[1].top, closeTo(21.76, .01));
    expect(block.inlineImages.single.offset, 0);
  });

  for (final entry in {'ul': '•', 'ol': '1.'}.entries) {
    test('${entry.key} 首个空行仍绘制列表标记', () async {
      final source = await _open('<li><br/>条目</li>', tag: entry.key);
      final page = (await source.loadChapter(0)).single;
      final slice = page.slices.single;
      final layout = slice.block.layout;
      expect(slice.block.listMarker, entry.value);
      expect(layout.lines, hasLength(2));
      expect(layout.lines.first.start, layout.lines.first.end);
      final bytes = await _render(page);
      final top = _pageInsets.top + page.topPadding + slice.leadingExtent;
      var markerPixels = 0;
      for (
        var y = top.ceil();
        y < (top + layout.lines.first.height).floor();
        y++
      ) {
        for (var x = 0; x < 384; x++) {
          final offset = (y * 384 + x) * 4;
          if (bytes.getUint8(offset) < 100 &&
              bytes.getUint8(offset + 1) < 100 &&
              bytes.getUint8(offset + 2) < 100 &&
              bytes.getUint8(offset + 3) > 0) {
            markerPixels++;
          }
        }
      }
      expect(markerPixels, greaterThan(0), reason: '文字前的空行应保留可见列表标记');
    });
  }
}
