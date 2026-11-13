import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/epub/epub_chapter_source.dart';
import 'package:reader_core/epub/epub_format_opener.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/source/format_opener.dart';

import '../audit/audit_epub_fixture.dart';

const _pageSize = Size(384, 853.3333333333333);
const _pageInsets = EdgeInsets.fromLTRB(
  8.8,
  56.075,
  8.53333333333336,
  24.08888888888893,
);
const _body =
    '<div class="panel"><h1>制作说明</h1>'
    '<p>正文<b style="font-size:1.1em">加粗</b>说明</p>'
    '<p class="tips">提示<b style="font-size:1.1em">加粗</b>说明</p>'
    '</div>';
const _css =
    'body.page { font-size:.75em; } '
    '.panel { font-size:.9em; width:70%; margin:0 auto; '
    'padding:2em 1.3em; border:2px solid #ffffff; background:#9a8056; } '
    'h1 { font-size:1.2em; text-align:center; margin:0 0 1em; } '
    'p { margin:0; line-height:130%; } .tips { font-size:.7em; }';

Uint8List _bookBytes(String body, String css) => auditZip({
  'mimetype': 'application/epub+zip',
  'META-INF/container.xml':
      '<container><rootfiles><rootfile full-path="book.opf"/>'
      '</rootfiles></container>',
  'book.opf':
      '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" '
      'unique-identifier="id"><metadata '
      'xmlns:dc="http://purl.org/dc/elements/1.1/">'
      '<dc:identifier id="id">inherited-font</dc:identifier>'
      '<dc:title>继承字号回归</dc:title></metadata><manifest>'
      '<item id="c" href="c.xhtml" media-type="application/xhtml+xml"/>'
      '</manifest><spine><itemref idref="c"/></spine></package>',
  'c.xhtml':
      '<html xmlns="http://www.w3.org/1999/xhtml"><head><style>$css'
      '</style></head><body class="page">$body</body></html>',
});

Future<EpubChapterSource> _open(String body, String css) async {
  final source = await const EpubFormatOpener().openBytes(
    _bookBytes(body, css),
    options: ReaderOpenOptions(
      contentWidth: _pageSize.width - _pageInsets.horizontal,
      contentHeight: _pageSize.height - _pageInsets.vertical,
    ),
  );
  addTearDown(source.close);
  return source;
}

Future<Map<String, PageBlock>> _textBlocks(EpubChapterSource source) async => {
  for (final page in await source.loadChapter(0))
    for (final slice in page.slices)
      if (slice.block.layout.text.isNotEmpty)
        slice.block.layout.text: slice.block,
};

void _expectSize(PageBlock block, double expected, {bool hasBold = false}) {
  expect(block.style!.fontSize, closeTo(expected, .001));
  expect(block.layout.runs, isNotEmpty);
  for (final run in block.layout.runs) {
    final text = block.layout.text.substring(run.start, run.end);
    expect(
      run.style.fontSize,
      closeTo(hasBold && text == '加粗' ? expected * 1.1 : expected, .001),
      reason: '正式文字测量必须使用继承后的字号，行内 em 只按最终父字号计算一次',
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('页面和面板的相对字号逐级继承，重排不重复缩放作者盒或行内文字', () async {
    final source = await _open(_body, _css);
    for (final readerSize in [21.0, 25.0, 21.0, null]) {
      await source.applyOverrides(
        ReaderOverrides(
          fontSize: readerSize,
          lineHeight: 1.6,
          paragraphSpacing: 10,
        ),
      );
      final blocks = await _textBlocks(source);
      final bodySize = (readerSize ?? 16) * .75 * .9;
      _expectSize(blocks['正文加粗说明']!, bodySize, hasBold: true);
      _expectSize(blocks['制作说明']!, bodySize * 1.2);
      _expectSize(blocks['提示加粗说明']!, bodySize * .7, hasBold: true);
      final panel = blocks['正文加粗说明']!.containers.single.container.style;
      expect(panel.fontSize, closeTo(10.8, .001));
      expect(panel.padding.top, closeTo(21.6, .001));
      expect(panel.padding.left, closeTo(14.04, .001));
      expect(panel.borders.left.width, 2);
    }
  });

  test('继承的相对字号保留容器层级，rem 重置到阅读器根基准且普通正文不缩小', () async {
    final source = await _open(
      '<p>普通正文</p><div class="panel"><p>继承说明</p>'
          '<p class="root">根字号<b style="font-size:.5em">小</b></p>'
          '<div class="root"><p>继承根字号</p>'
          '<p style="font-size:.5em">根内相对字号</p></div></div>',
      'body { font-size:14px; } p { margin:0; } '
          '.panel { font-size:75%; } .root { font-size:.8rem; }',
    );
    await source.applyOverrides(const ReaderOverrides(fontSize: 21));
    final blocks = await _textBlocks(source);
    _expectSize(blocks['普通正文']!, 21);
    _expectSize(blocks['继承说明']!, 21 * .75);
    final root = blocks['根字号小']!;
    expect(root.style!.fontSize, closeTo(21 * .8, .001));
    expect(root.layout.runs.last.style.fontSize, closeTo(21 * .8 * .5, .001));
    _expectSize(blocks['继承根字号']!, 21 * .8);
    _expectSize(blocks['根内相对字号']!, 21 * .8 * .5);
  });
}
