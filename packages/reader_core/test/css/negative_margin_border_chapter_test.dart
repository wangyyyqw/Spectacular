import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/epub/epub_format_opener.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/paint/page_renderer.dart';
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
h2 { font-family: Ahem; font-size: .95em; line-height: 150%;
  margin: -1em 0 2em .35em; border-width: 15px;
  border-style: dashed dashed dashed solid;
  border-color: transparent transparent transparent #ab2524; }
h2 b { font-size: 1.25em; padding: .1em .2em .1em .15em;
  border-style: none none solid none; border-width: 0 0 1px 0;
  border-color: #7a4c99; }
''';

Future<List<PageContent>> _pages(String heading) async {
  final bytes = auditZip({
    'mimetype': 'application/epub+zip',
    'META-INF/container.xml':
        '<container><rootfiles><rootfile '
        'full-path="book.opf"/></rootfiles></container>',
    'book.opf':
        '<package version="3.0" unique-identifier="id" '
        'xmlns="http://www.idpf.org/2007/opf"><metadata '
        'xmlns:dc="http://purl.org/dc/elements/1.1/">'
        '<dc:identifier id="id">negative-margin-border</dc:identifier>'
        '<dc:title>负边距边框回归</dc:title><dc:language>zh</dc:language>'
        '</metadata><manifest><item id="c" href="c.xhtml" '
        'media-type="application/xhtml+xml"/></manifest>'
        '<spine><itemref idref="c"/></spine></package>',
    'c.xhtml':
        '<html xmlns="http://www.w3.org/1999/xhtml"><head>'
        '<style>$_css</style></head><body><h2>$heading</h2>'
        '<p>相邻正文内容。</p></body></html>',
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
  return source.loadChapter(0);
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

List<int> _pixel(ByteData bytes, int x, int y) =>
    List.generate(4, (channel) => bytes.getUint8((y * 384 + x) * 4 + channel));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('负上边距标题的红色斜角可绘制到正文区上方的页面留白', () async {
    final page = (await _pages('第一章<br/><b>标题样式</b>')).single;
    final bytes = await _render(page);
    // 作者边框 top = 22.3111 - 17×.95 = 6.1611，透明顶边宽 15。
    expect(_pixel(bytes, 16, 12), [171, 37, 36, 255], reason: '外角不能被切片裁平');
    expect(_pixel(bytes, 26, 12), [255, 255, 255, 255], reason: '透明顶边保留斜接');
    expect(_pixel(bytes, 26, 24), [171, 37, 36, 255], reason: '斜接下方仍是完整左边框');
    expect(_pixel(bytes, 16, 4), [255, 255, 255, 255], reason: '边框不延伸到作者盒外');
  });

  test('跨页标题的续页不重画上边斜角或侵入页眉', () async {
    final pages = await _pages(List.filled(70, '章').join('<br/>'));
    expect(pages.length, greaterThan(1));
    expect(pages[1].slices.first.continuesBefore, isTrue);
    final bytes = await _render(pages[1]);
    expect(_pixel(bytes, 16, 12), [255, 255, 255, 255]);
    expect(_pixel(bytes, 26, 24), [171, 37, 36, 255], reason: '续页侧框保持平直');
  });
}
