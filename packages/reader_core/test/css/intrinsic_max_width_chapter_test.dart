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
import 'package:reader_core/source/format_opener.dart';

import '../audit/audit_epub_fixture.dart';

const _insets = EdgeInsets.fromLTRB(
  8.8,
  56.075,
  8.53333333333336,
  24.08888888888893,
);
const _size = Size(384, 853.3333333333334);
const _width = 384 - 8.8 - 8.53333333333336;
const _height = 853.3333333333334 - 56.075 - 24.08888888888893;

Uint8List _book(String body, String css) => auditZip({
  'mimetype': 'application/epub+zip',
  'META-INF/container.xml':
      '<container><rootfiles><rootfile full-path="book.opf"/>'
      '</rootfiles></container>',
  'book.opf':
      '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" '
      'unique-identifier="id"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
      '<dc:identifier id="id">intrinsic-max-width</dc:identifier>'
      '<dc:title>标题内容限宽回归</dc:title></metadata><manifest>'
      '<item id="c" href="c.xhtml" media-type="application/xhtml+xml"/>'
      '</manifest><spine><itemref idref="c"/></spine></package>',
  'c.xhtml':
      '<html xmlns="http://www.w3.org/1999/xhtml"><head><style>'
      'html, body, div, h4, p {margin:0; padding:0; font-family:Ahem; '
      'font-weight:normal; line-height:1.6; text-indent:0;} '
      'html, body {font-size:16px;} div, h4, p {font-size:1em;} '
      '.label {text-align:center; color:white; background:#7a5012; '
      'padding:8px 10px; border-radius:5px; margin:0 auto; $css}'
      '</style></head><body>$body<p>相邻正文保持原有宽度。</p></body></html>',
});

Future<EpubChapterSource> _open(
  String css, {
  String body = '<h4 class="label">一</h4>',
}) async {
  final source = await const EpubFormatOpener().openBytes(
    _book(body, css),
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
  return source;
}

void _expectHeading(PageContent page, double width) {
  final block = page.slices.first.block;
  expect(block.layout.maxWidth, closeTo(width, .01));
  expect(block.style!.margin.left, closeTo((_width - width - 20) / 2, .01));
  expect(block.style!.margin.right, closeTo(block.style!.margin.left, .01));
  expect(page.slices.last.block.layout.maxWidth, closeTo(_width, .01));
  expect(
    TextHitTester.lineBoxes(page).first.rect.center.dx,
    closeTo(_width / 2, .01),
  );
}

Future<Rect> _backgroundBounds(PageContent page) async {
  final recorder = ui.PictureRecorder();
  const PagePainter().paint(
    Canvas(recorder),
    page,
    pageSize: _size,
    pageInsets: _insets,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(384, 854);
  final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  var left = 384, top = 854, right = -1, bottom = -1;
  for (var y = 0; y < 854; y++) {
    for (var x = 0; x < 384; x++) {
      final i = (y * 384 + x) * 4;
      if (bytes.getUint8(i) == 0x7a &&
          bytes.getUint8(i + 1) == 0x50 &&
          bytes.getUint8(i + 2) == 0x12 &&
          bytes.getUint8(i + 3) == 255) {
        if (x < left) left = x;
        if (x > right) right = x;
        if (y < top) top = y;
        if (y > bottom) bottom = y;
      }
    }
  }
  image.dispose();
  picture.dispose();
  expect(right, greaterThan(left));
  return Rect.fromLTRB(left.toDouble(), top.toDouble(), right + 1, bottom + 1);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final value in [
    'fit-content',
    '-moz-fit-content',
    '-webkit-fit-content',
  ]) {
    test('真机参数下 max-width:$value 收窄背景并居中', () async {
      final source = await _open('max-width:$value;');
      final page = (await source.loadChapter(0)).single;
      _expectHeading(page, 18);
      final background = await _backgroundBounds(page);
      expect(background.width, closeTo(38, 1));
      expect(background.center.dx, closeTo(_insets.left + _width / 2, 1));
    });
  }

  test('连续前缀声明经过级联，阅读字号切换后重新收窄且保留CFI', () async {
    final source = await _open(
      'max-width:fit-content; max-width:-moz-fit-content; max-width:-webkit-fit-content;',
    );
    final cfi = (await source.loadChapter(0))
        .single
        .slices
        .first
        .block
        .startCfi;
    for (final size in [24.0, 12.0, 18.0]) {
      await source.applyOverrides(
        ReaderOverrides(fontSize: size, lineHeight: 1.6, paragraphSpacing: 10),
      );
      final page = (await source.loadChapter(0)).single;
      _expectHeading(page, size);
      expect(page.slices.first.block.startCfi, cfi);
    }
  });

  for (final (css, expected) in [
    ('width:200px; max-width:fit-content;', 18.0),
    ('min-width:80px; max-width:fit-content;', 80.0),
    ('max-width:fit-content; box-sizing:border-box; border:2px solid;', 18.0),
    ('max-width:60px; max-width:invalid-value;', 60.0),
  ]) {
    test('内容限宽保留声明宽、最小宽、盒模型及有效级联：$css', () async {
      final source = await _open(css);
      final page = (await source.loadChapter(0)).single;
      expect(page.slices.first.block.layout.maxWidth, closeTo(expected, .01));
      final bounds = await _backgroundBounds(page);
      expect(bounds.width, closeTo(expected + 20, 1));
    });
  }

  for (final (value, expected) in [
    ('min-content', 18.0),
    ('max-content', 36.0),
  ]) {
    test('最大宽度消费$value 内容边界', () async {
      final source = await _open(
        'max-width:$value;',
        body: '<h4 class="label">一二</h4>',
      );
      final block = (await source.loadChapter(0)).single.slices.first.block;
      expect(block.layout.maxWidth, closeTo(expected, .01));
    });
  }

  test('短内容限宽不同于固定宽，长内容仍按可用宽换行', () async {
    final source = await _open(
      'max-width:fit-content;',
      body: '<h4 class="label">${'天地玄黄' * 12}</h4>',
    );
    final page = (await source.loadChapter(0)).single;
    expect(page.slices.first.block.layout.maxWidth, closeTo(_width - 20, .01));
    expect(page.slices.first.block.layout.lineCount, greaterThan(1));
  });

  test('保留容器的内容限宽同时约束后代与背景', () async {
    final source = await _open(
      'max-width:fit-content;',
      body: '<div class="label"><p>一</p><p>二三</p></div>',
    );
    final page = (await source.loadChapter(0)).single;
    final container = page.slices.first.block.containers.last.container;
    expect(container.contentWidth, closeTo(36, .01));
    expect(container.width, closeTo(56, .01));
    expect(page.slices.first.block.layout.maxWidth, closeTo(36, .01));
    expect((await _backgroundBounds(page)).width, closeTo(56, 1));
  });

  test('嵌套标题在父内容盒中收窄居中，投影不重复计算外边距', () async {
    final source = await _open(
      'max-width:fit-content;',
      body:
          '<div style="width:160px; margin:0 0 0 40px; padding:0 12px;">'
          '<h4 class="label">一</h4></div>',
    );
    final page = (await source.loadChapter(0)).single;
    expect(page.slices.first.block.layout.maxWidth, closeTo(18, .01));
    final background = await _backgroundBounds(page);
    expect(background.width, closeTo(38, 1));
    expect(background.center.dx, closeTo(_insets.left + 40 + 12 + 80, 1));
  });
}
