import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/epub/epub_format_opener.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/layout/paginator.dart';
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
const _height = 773.1694444444445;

Future<List<PageContent>> _pages({
  String tag = 'c',
  String display = 'block',
  String extraCss = '',
  String after = 'AFTER',
  bool withFlow = true,
}) async {
  final source = await const EpubFormatOpener().openBytes(
    auditZip({
      'mimetype': 'application/epub+zip',
      'META-INF/container.xml': '<container><rootfiles><rootfile full-path="book.opf"/></rootfiles></container>',
      'book.opf':
          '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id">'
          '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="id">fixed-container-border</dc:identifier>'
          '<dc:title>固定定位面板回归</dc:title></metadata><manifest>'
          '<item id="c" href="c.xhtml" media-type="application/xhtml+xml"/>'
          '</manifest><spine><itemref idref="c"/></spine></package>',
      'c.xhtml':
          '<html xmlns="http://www.w3.org/1999/xhtml"><head><style>'
          'body {margin:0;padding:0;font-family:Ahem;color:black;}'
          '.panel {position:fixed;top:450px;left:20px;right:20px;display:$display;'
          'padding:10px 15px;border:2px solid rgba(255,255,255,0);'
          'background:rgba(255,250,250,.5);border-radius:10px;box-sizing:border-box;'
          'font-weight:normal;margin:0;text-align:center;}'
          '.panel p {margin:12px 0;font-size:18px;line-height:1.6;text-align:left;text-indent:0;}'
          '$extraCss</style></head><body>'
          '${withFlow ? '<p style="margin:0;">FLOW</p>' : ''}'
          '<$tag class="panel"><p>FIRST</p><p>SECOND</p></$tag>'
          '${withFlow ? '<p style="margin:0;">$after</p>' : ''}</body></html>',
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
  return source.loadChapter(0);
}

Future<PageContent> _page({
  String tag = 'c',
  String display = 'block',
  String extraCss = '',
}) async =>
    (await _pages(tag: tag, display: display, extraCss: extraCss)).single;

Future<ByteData> _paint(PageContent page) async {
  final recorder = ui.PictureRecorder();
  const PagePainter(background: Color(0xFF000000))
      .paint(Canvas(recorder), page, pageSize: _size, pageInsets: _insets);
  final picture = recorder.endRecording();
  final output = await picture.toImage(384, 854);
  try {
    return (await output.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  } finally {
    output.dispose();
    picture.dispose();
  }
}

List<int> _pixel(ByteData data, int x, int y) => [
  for (var i = 0; i < 4; i++) data.getUint8((y * 384 + x) * 4 + i),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final (tag, display) in [
    ('c', 'block'),
    ('div', 'block'),
    ('span', 'inline'),
    ('x-panel', 'inline-block'),
  ]) {
    test('$tag/$display 固定面板整体定位，透明边框和半透明背景只绘一次且保留圆角', () async {
      final page = await _page(tag: tag, display: display);
      final overlays = page.slices.where((slice) => slice.overlay).toList();
      expect(overlays, hasLength(2));
      expect(overlays.map((slice) => slice.block.layout.text), [
        'FIRST',
        'SECOND',
      ]);
      expect(
        page.slices
            .where((slice) => !slice.overlay)
            .map((slice) => slice.block.layout.text),
        ['FLOW', 'AFTER'],
      );
      final first = overlays.first;
      final last = overlays.last;
      expect(first.absoluteTop, 450 - _insets.top);
      expect(first.block.containers, hasLength(1));
      final panel = first.block.containers.single.container;
      expect(panel.left, 20 - _insets.left);
      expect(panel.width, closeTo(_size.width - 40, .01));
      expect(panel.style.borders.hasRadius, isTrue);
      expect(panel.style.borders.top.color.a, 0);
      expect(first.block.style!.backgroundColor.a, 0, reason: '子段落不能复制父背景');
      expect(last.block.style!.backgroundColor.a, 0);
      final pixels = await _paint(page);
      final left = 20;
      final top = 450;
      final sampleX = left + 8;
      final bottom =
          (_insets.top +
                  last.absoluteTop! +
                  last.height -
                  last.trailingExtent +
                  last.block.containers.single.bottomInset)
              .floor();
      for (final y in [top + 15, top + 45, bottom - 15]) {
        final pixel = _pixel(pixels, sampleX, y);
        expect(pixel[0], closeTo(128, 1));
        expect(pixel[1], closeTo(125, 1));
        expect(pixel[2], closeTo(125, 1));
      }
      expect(_pixel(pixels, left, top), [0, 0, 0, 255], reason: '圆角外保持页面背景');
      expect(
        _pixel(pixels, (left + panel.width / 2).round(), top)[0],
        closeTo(128, 1),
        reason: '透明边框不能出现白线',
      );
      expect(_pixel(pixels, sampleX, bottom + 2), [
        0,
        0,
        0,
        255,
      ], reason: '面板背景不能越出自身边框盒');
      expect(first.block.startCfi, isNotNull);
      expect(last.block.startCfi, isNotNull);
    });

    test('$tag/$display 仅有固定面板的章节仍显示完整父框和文字', () async {
      final page = (await _pages(
        tag: tag,
        display: display,
        withFlow: false,
      )).single;
      expect(page.slices, hasLength(2));
      expect(page.slices.every((slice) => slice.overlay), isTrue);
      expect(page.slices.map((slice) => slice.block.layout.text), [
        'FIRST',
        'SECOND',
      ]);
      expect(page.usedHeight, 0);
      final first = page.slices.first;
      final last = page.slices.last;
      final panel = first.block.containers.single.container;
      expect(last.block.containers.single.container, same(panel));
      expect(first.absoluteTop, 450 - _insets.top);
      expect(panel.left, 20 - _insets.left);
      expect(panel.width, closeTo(_size.width - 40, .01));
      expect(first.block.startCfi, isNotNull);
      expect(last.block.startCfi, isNotNull);
      expect(_pixel(await _paint(page), 28, 465)[0], closeTo(128, 1));
    });
  }

  test('隐藏的固定行内容器不生成覆盖层，也不拆分正文或占据空间', () async {
    final page = await _page(tag: 'span', display: 'none');
    expect(page.slices.any((slice) => slice.overlay), isFalse);
    expect(page.slices.map((slice) => slice.block.layout.text), [
      'FLOW',
      'AFTER',
    ]);
    expect(
      page.slices.every((slice) => slice.block.containers.isEmpty),
      isTrue,
    );
    expect(page.slices.every((slice) => slice.block.startCfi != null), isTrue);
  });

  test('固定面板的可见实线边框四侧连续，子段落不重复描边', () async {
    final page = await _page(
      tag: 'div',
      extraCss: '.panel {border:3px solid #0c3483;}',
    );
    final overlays = page.slices.where((slice) => slice.overlay).toList();
    final first = overlays.first;
    final last = overlays.last;
    final box = first.block.containers.single.container;
    final pixels = await _paint(page);
    final top = 450.0;
    final bottom =
        _insets.top +
        last.absoluteTop! +
        last.height -
        last.trailingExtent +
        last.block.containers.single.bottomInset;
    for (final point in [
      Offset(20 + 1.5, top + 30),
      Offset(20 + box.width - 1.5, top + 30),
      Offset(20 + box.width / 2, top + 1.5),
      Offset(20 + box.width / 2, bottom - 1.5),
    ]) {
      expect(_pixel(pixels, point.dx.floor(), point.dy.floor()), [
        12,
        52,
        131,
        255,
      ]);
    }
    expect(
      overlays.every((slice) => !slice.block.style!.borders.hasBorder),
      isTrue,
    );
  });

  test('多页正文中固定面板每页显示一次，位置和背景高度不随分页改变', () async {
    final pages = await _pages(after: 'BODY ' * 500);
    expect(pages.length, greaterThan(1));
    for (final page in pages) {
      final overlays = page.slices.where((slice) => slice.overlay).toList();
      expect(overlays, hasLength(2));
      expect(overlays.first.absoluteTop, 450 - _insets.top);
      expect(overlays.first.block.layout.text, 'FIRST');
      expect(overlays.last.block.layout.text, 'SECOND');
      expect(overlays.first.block.containers.single.startsHere, isTrue);
      expect(overlays.last.block.containers.single.endsHere, isTrue);
    }
  });
}
