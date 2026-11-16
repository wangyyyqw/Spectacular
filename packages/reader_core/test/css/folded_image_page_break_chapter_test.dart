import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/reader_overrides.dart';
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
late Uint8List _imageBytes;

Future<void> _prepareImage() async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawColor(const Color(0x00000000), BlendMode.src);
  final picture = recorder.endRecording();
  final image = await picture.toImage(20, 20);
  try {
    _imageBytes = (await image.toByteData(format: ui.ImageByteFormat.png))!
        .buffer
        .asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}

Uint8List _book(String body, String css) => auditZip({
  'mimetype': 'application/epub+zip',
  'META-INF/container.xml':
      '<container><rootfiles><rootfile full-path="book.opf"/>'
      '</rootfiles></container>',
  'book.opf':
      '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" '
      'unique-identifier="id"><metadata '
      'xmlns:dc="http://purl.org/dc/elements/1.1/">'
      '<dc:identifier id="id">folded-image-break</dc:identifier>'
      '<dc:title>图片容器分页回归</dc:title></metadata><manifest>'
      '<item id="c" href="c.xhtml" media-type="application/xhtml+xml"/>'
      '<item id="pic" href="spacer.png" media-type="image/png"/>'
      '<item id="css" href="style.css" media-type="text/css"/>'
      '</manifest><spine><itemref idref="c"/></spine></package>',
  'c.xhtml':
      '<html xmlns="http://www.w3.org/1999/xhtml"><head>'
      '<link rel="stylesheet" href="style.css"/></head>'
      '<body>$body</body></html>',
  'style.css': 'body { margin:0; } p { margin:0; } $css',
  'spacer.png': _imageBytes,
});

Future<List<PageContent>> _pages(String body, {String css = ''}) async {
  final width = _pageSize.width - _pageInsets.horizontal;
  final height = _pageSize.height - _pageInsets.vertical;
  final source = await const EpubFormatOpener().openBytes(
    _book(body, css),
    options: ReaderOpenOptions(contentWidth: width, contentHeight: height),
  );
  addTearDown(source.close);
  await source.applyOverrides(
    const ReaderOverrides(fontSize: 21, lineHeight: 1.6, paragraphSpacing: 10),
  );
  await source.applyContentSize(
    width: width,
    height: height,
    topInset: _pageInsets.top,
    sideInsets: (left: _pageInsets.left, right: _pageInsets.right),
  );
  return source.loadChapter(0);
}

String _text(PageContent page) =>
    page.slices.map((slice) => slice.block.layout.text).join();

void _registerIntroRegression() {
  test('透明图片容器强制分页，负上边距简介不与前页提示混排', () async {
    final pages = await _pages(
      '<p>前页提示</p>'
      '<div style="page-break-after:always"><img src="spacer.png"/></div>'
      '<div>\n    <br/>\n  </div><h1>内容简介</h1><p>简介正文</p>',
      css:
          'h1 { font-size:1em; width:1.1em; text-align:center; '
          'margin:-5.5em auto 2em; padding:5em .1em 4em; '
          'color:white; background:black; }',
    );
    expect(pages, hasLength(2));
    expect(_text(pages.first), '前页提示');
    expect(_text(pages.last), '内容简介简介正文');
    expect(pages.last.slices.first.block.layout.text, isEmpty);
    expect(
      pages.last.slices.first.block.cfiAt(0),
      isNull,
      reason: '显式空行只占布局高度，不能提供不可保存的空白文字锚点',
    );
    final heading = pages.last.slices.singleWhere(
      (slice) => slice.block.layout.text == '内容简介',
    );
    expect(heading.block.style!.values['background-color'], 'black');
    expect(heading.lines, hasLength(4));
  });
}

void _registerStylesheetRegressions() {
  for (final declaration in ['page-break-after:always', 'break-after:page']) {
    test('外部样式表的 $declaration 在纯图片容器末尾生效', () async {
      final pages = await _pages(
        '<p>前页正文</p><div class="frame"><img src="spacer.png"/></div>'
        '<p>后页正文</p>',
        css: '.frame { $declaration; }',
      );
      expect(pages, hasLength(2));
      expect(_text(pages.first), '前页正文');
      expect(_text(pages.last), '后页正文');
    });
  }
}

void _registerBoundaryRegressions() {
  test('嵌套图片容器分别保留前后分页，图片 auto 不覆盖父边界', () async {
    final pages = await _pages(
      '<p>前页正文</p><div style="break-before:page">'
      '<div style="break-after:page">'
      '<img src="spacer.png" style="break-before:auto;break-after:auto"/>'
      '</div></div><p>后页正文</p>',
    );
    expect(pages, hasLength(3));
    expect(_text(pages.first), '前页正文');
    expect(pages[1].slices.single.block.isReplaced, isTrue);
    expect(_text(pages.last), '后页正文');
  });

  test('保留容器已在首子块分页，不在其内部图片前重复分页', () async {
    final pages = await _pages(
      '<p>前页正文</p><div style="break-before:page">'
      '<p style="break-before:page">同页开头</p>'
      '<div><img src="spacer.png"/></div><p>同页结束</p></div>',
    );
    expect(pages, hasLength(2));
    expect(_text(pages.last), '同页开头同页结束');
  });
}

void _registerCascadeRegressions() {
  test('图片容器的行内 auto 覆盖普通样式表，不产生额外分页', () async {
    final pages = await _pages(
      '<p>前页正文</p><div class="frame" style="break-after:auto">'
      '<img src="spacer.png"/></div><p>后页正文</p>',
      css: '.frame { break-after:page; }',
    );
    expect(pages, hasLength(1));
    expect(_text(pages.single), '前页正文后页正文');
  });

  test('图片自身的分页声明继续生效', () async {
    final pages = await _pages(
      '<p>前页正文</p><div>'
      '<img src="spacer.png" style="break-after:page"/>'
      '</div><p>后页正文</p>',
    );
    expect(pages, hasLength(2));
    expect(_text(pages.first), '前页正文');
    expect(_text(pages.last), '后页正文');
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_prepareImage);
  _registerIntroRegression();
  _registerStylesheetRegressions();
  _registerBoundaryRegressions();
  _registerCascadeRegressions();
}
