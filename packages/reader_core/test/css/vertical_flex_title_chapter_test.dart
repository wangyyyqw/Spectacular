import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/epub/epub_format_opener.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/table_layout.dart';
import 'package:reader_core/paint/page_renderer.dart';
import 'package:reader_core/source/format_opener.dart';

import '../audit/audit_epub_fixture.dart';

const _size = Size(384, 853.3333333333334);
const _insets = EdgeInsets.fromLTRB(
  8.8,
  56.075,
  8.53333333333336,
  24.08888888888893,
);
const _width = 366.6666666666667;
const _height = 773.1694444444443;
const _text = '第 一 卷';

Future<PageContent> _page({String css = '', String text = _text}) async {
  final source = await const EpubFormatOpener().openBytes(
    auditZip({
      'mimetype': 'application/epub+zip',
      'META-INF/container.xml': '<container><rootfiles><rootfile full-path="book.opf"/></rootfiles></container>',
      'book.opf':
          '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id">'
          '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="id">vertical-flex-title</dc:identifier>'
          '<dc:title>竖排 Flex 卷标题回归</dc:title></metadata><manifest>'
          '<item id="c" href="c.xhtml" media-type="application/xhtml+xml"/>'
          '</manifest><spine><itemref idref="c"/></spine></package>',
      'c.xhtml':
          '<html xmlns="http://www.w3.org/1999/xhtml"><head><style>'
          'body {display:flex;justify-content:flex-end;align-items:flex-start;height:100vh;'
          'font-family:Ahem;padding-top:200px;padding-right:60%;box-sizing:border-box;}'
          '.title {font-size:2em;font-weight:bold;writing-mode:vertical-rl;text-orientation:upright;'
          'border:2px solid transparent;border-radius:10px;background:lightgray;padding:20px;}'
          '$css</style></head><body><h1 class="title">$text</h1></body></html>',
    }),
    options: const ReaderOpenOptions(
      contentWidth: _width,
      contentHeight: _height,
    ),
  );
  addTearDown(source.close);
  await source.applyOverrides(
    const ReaderOverrides(fontSize: 18, lineHeight: 1.6, paragraphSpacing: 10),
  );
  await source.applyContentSize(
    width: _width,
    height: _height,
    topInset: _insets.top,
    sideInsets: (left: _insets.left, right: _insets.right),
  );
  return (await source.loadChapter(0)).single;
}

TableCellRender _title(PageContent page) =>
    page.slices.single.block.table!.cells.single;

Future<ByteData> _paint(PageContent page) async {
  final recorder = ui.PictureRecorder();
  const PagePainter(background: Color(0xFF4488AA))
      .paint(Canvas(recorder), page, pageSize: _size, pageInsets: _insets);
  final picture = recorder.endRecording();
  final image = await picture.toImage(384, 854);
  try {
    return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  } finally {
    image.dispose();
    picture.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final bytes = await File('../../test_fonts/SourceHanSerifSC-Regular.otf')
        .readAsBytes();
    await (FontLoader(
      'VolumeTitleSerif',
    )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
  });

  test('窄横向 Flex 中竖排卷标题使用可用高度，保持单列及原文锚点', () async {
    final page = await _page();
    final title = _title(page);
    expect(title.layout.lines, hasLength(1));
    expect(title.layout.text, _text);
    expect(title.rect.right, closeTo(_width * .4, .01));
    expect(title.rect.width, closeTo(title.layout.width + 44, .01));
    expect(title.rect.top, closeTo(36 * .67, .01));
    expect(title.startCfi, isNotNull);
    expect(title.textCoordinates!.cfiAt(4), endsWith(':4)'));
    expect(title.style.borders.top.color.a, 0);
    final pixels = await _paint(page);
    final origin = title.textOrigin.translate(
      _insets.left,
      _insets.top + page.slices.single.leadingExtent,
    );
    expect(title.layout.height, closeTo(5 * 36, .01));
    for (final index in [0, 2, 4]) {
      var ink = 0;
      for (
        var y = (origin.dy + index * 36).ceil();
        y < origin.dy + (index + 1) * 36;
        y++
      ) {
        for (
          var x = origin.dx.ceil();
          x < origin.dx + title.layout.width;
          x++
        ) {
          if (pixels.getUint8((y * 384 + x) * 4) < 100) ink++;
        }
      }
      expect(ink, greaterThan(20), reason: '三个字都沿同一列完整绘制');
    }
  });

  test('父盒可用高度仍约束竖排列长，不把长标题强行铺成单列', () async {
    final title = _title(
      await _page(
        css: 'body {height:350px;} .title {margin:0;}',
        text: '甲乙丙丁戊己',
      ),
    );
    expect(title.layout.lineCount, greaterThan(1));
    expect(title.layout.height, lessThanOrEqualTo(350 - 200 - 44));
    expect(
      title.layout.lines
          .map((line) => title.layout.text.substring(line.start, line.end))
          .join(),
      '甲乙丙丁戊己',
    );
  });

  test('作者显式列高继续生效，横排 Flex 标题维持原来的断行宽', () async {
    final vertical = _title(
      await _page(css: '.title {height:80px;margin:0;}', text: '甲乙丙丁'),
    );
    expect(vertical.layout.lines, hasLength(2));
    expect(vertical.layout.height, lessThanOrEqualTo(80));
    final horizontal = _title(
      await _page(css: '.title {writing-mode:horizontal-tb;margin:0;}'),
    );
    expect(horizontal.layout.isVertical, isFalse);
    expect(horizontal.layout.lineCount, greaterThan(1));
  });

  test('真实宋体的窄空格按竖排字格计高，末字不被标题背景框裁掉', () async {
    final page = await _page(css: 'body {font-family:VolumeTitleSerif;}');
    final title = _title(page);
    expect(title.layout.lineCount, 1);
    expect(title.layout.height, closeTo(180, .01));
    expect(title.rect.height, closeTo(224, .01));
    final pixels = await _paint(page);
    final origin = title.textOrigin.translate(
      _insets.left,
      _insets.top + page.slices.single.leadingExtent,
    );
    var ink = 0;
    for (var y = (origin.dy + 144).ceil(); y < origin.dy + 180; y++) {
      for (var x = origin.dx.ceil(); x < origin.dx + title.layout.width; x++) {
        if (pixels.getUint8((y * 384 + x) * 4) < 100) ink++;
      }
    }
    expect(ink, greaterThan(100), reason: '末字完整保留在框内最后一个字格');
  });
}
