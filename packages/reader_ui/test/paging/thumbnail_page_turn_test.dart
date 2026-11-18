import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/epub/epub_format_opener.dart';
import 'package:reader_core/paint/image_cache.dart';
import 'package:reader_core/source/chapter_source.dart';
import 'package:reader_core/source/format_opener.dart';
import 'package:reader_ui/paging/page_turn_controller.dart';
import 'package:reader_ui/paging/page_turn_mode.dart';
import 'package:reader_ui/paging/page_turn_view.dart';
import 'package:reader_ui/reader_page.dart';
import 'package:reader_ui/reader_session.dart';

import '../../../reader_core/test/audit/audit_epub_fixture.dart';

const _colors = [
  0xffcd1234,
  0xff1256cd,
  0xff12cd56,
  0xffac5621,
  0xff5612ac,
  0xff21ac56,
  0xffac2156,
  0xff2156ac,
  0xff5621ac,
  0xff34cd12,
  0xff1234cd,
  0xffcd3412,
  0xffac1234,
  0xff1234ac,
  0xff12ac34,
  0xff3456ac,
  0xffac3456,
  0xff34ac56,
  0xff56ac34,
  0xff5634ac,
  0xffac5634,
  0xffac34cd,
];

Future<Uint8List> _png(int color, {int width = 1000, int height = 1333}) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawColor(Color(color), BlendMode.src);
  final picture = recorder.endRecording();
  final image = picture.toImageSync(width, height);
  try {
    return (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer
        .asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}

Future<Uint8List> _book() async {
  final files = <String, Object>{
    'mimetype': 'application/epub+zip',
    'META-INF/container.xml':
        '<container><rootfiles><rootfile full-path="OEBPS/book.opf"/>'
        '</rootfiles></container>',
    'OEBPS/book.opf': _opf(),
    'OEBPS/Styles/main.css':
        'body{margin:0;font-family:Ahem;background-color:white;'
        'background-image:url(../Images/bg.png);background-repeat:no-repeat;'
        'background-position:bottom center;background-size:cover;}'
        'h1{font-size:1em;text-align:center;color:#b95b41;}'
        '.heading{margin:5% 15% 15%;padding:3%;border-top:3px solid #b95b41;'
        'border-bottom:3px solid #b95b41;}'
        '.row{text-align:center;}img{width:20%;margin:3px;}',
    for (var spine = 0; spine < 2; spine++)
      'OEBPS/Text/$spine.xhtml': _chapter(spine),
    'OEBPS/Images/bg.png': await _png(0xffffeedd, width: 1080, height: 2400),
    for (final (index, color) in _colors.indexed)
      'OEBPS/Images/$index.png': await _png(color),
  };
  return auditZip(files);
}

String _opf() =>
    '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" '
    'unique-identifier="id"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
    '<dc:identifier id="id">thumbnail-turn</dc:identifier>'
    '<dc:title>缩略图翻页</dc:title></metadata><manifest>'
    '<item id="css" href="Styles/main.css" media-type="text/css"/>'
    '<item id="bg" href="Images/bg.png" media-type="image/png"/>'
    '${List.generate(2, (i) => '<item id="c$i" href="Text/$i.xhtml" media-type="application/xhtml+xml"/>').join()}'
    '${List.generate(_colors.length, (i) => '<item id="i$i" href="Images/$i.png" media-type="image/png"/>').join()}'
    '</manifest><spine><itemref idref="c0"/><itemref idref="c1"/></spine></package>';

String _chapter(int spine) {
  final indices = spine == 0
      ? List.generate(12, (i) => i)
      : List.generate(10, (i) => i + 12);
  final rows = [
    for (var start = 0; start < indices.length; start += 4)
      '<div class="row">${indices.skip(start).take(4).map((i) => '<img src="../Images/$i.png"/>').join()}</div>',
  ];
  return '<html xmlns="http://www.w3.org/1999/xhtml"><head>'
      '<link rel="stylesheet" href="../Styles/main.css"/>'
      '</head><body><div class="heading"><h1>封面</h1></div>${rows.join()}</body></html>';
}

Future<void> _advance(WidgetTester tester) async {
  for (var frame = 0; frame < 70; frame++) {
    await tester.pump(const Duration(milliseconds: 20));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
}

Future<void> _expectPaper(WidgetTester tester, GlobalKey key, int spine) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = boundary.toImageSync();
  try {
    await _expectImage(tester, image, spine);
  } finally {
    image.dispose();
  }
}

Future<void> _expectImage(
  WidgetTester tester,
  ui.Image image,
  int spine,
) async {
  final pixels = (await tester.runAsync(image.toByteData))!.buffer
      .asUint8List();
  final colors = <int>{};
  for (var offset = 0; offset < pixels.length; offset += 4) {
    colors.add(
      0xff000000 |
          pixels[offset] << 16 |
          pixels[offset + 1] << 8 |
          pixels[offset + 2],
    );
  }
  final expected = spine == 0 ? _colors.take(12) : _colors.skip(12);
  expect(colors, containsAll(expected), reason: '纸面不能缺少当前页的任何缩略图');
  expect(colors, contains(0xffffeedd), reason: '整页背景必须保留');
}

Future<(ReaderSession, DecodedImageCache)> _show(
  WidgetTester tester,
  GlobalKey key,
) async {
  final bytes = (await tester.runAsync(_book))!;
  final source = await const EpubFormatOpener().openBytes(
    bytes,
    options: const ReaderOpenOptions(
      contentWidth: 366.6666666666667,
      contentHeight: 773.1694444444443,
    ),
  );
  addTearDown(source.close);
  final cache = DecodedImageCache(
    maxEntries: 32,
    maxBytes: 32 << 20,
    loadBytes: source.readImageBytes,
  );
  addTearDown(cache.clear);
  late ReaderSession session;
  await tester.pumpWidget(
    MaterialApp(
      home: RepaintBoundary(
        key: key,
        child: _reader(source, cache, (value) => session = value),
      ),
    ),
  );
  await _advance(tester);
  return (session, cache);
}

Widget _reader(
  ReaderChapterSource source,
  DecodedImageCache cache,
  ValueChanged<ReaderSession> onReady,
) => ReaderPage(
  source: source,
  store: MemoryReaderProgressStore(),
  bookId: '缩略图往返',
  imageCache: cache,
  pageTurnMode: PageTurnMode.simulation3d,
  showPageFooter: false,
  padding: const EdgeInsets.fromLTRB(
    8.8,
    56.075,
    8.53333333333336,
    24.08888888888893,
  ),
  overrides: const ReaderOverrides(
    fontSize: 18,
    lineHeight: 1.6,
    paragraphSpacing: 10,
  ),
  onSessionReady: onReady,
);

Future<void> _pumpUntil(WidgetTester tester, bool Function() ready) async {
  for (var frame = 0; frame < 80 && !ready(); frame++) {
    await tester.pump(const Duration(milliseconds: 16));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 3)),
    );
  }
  expect(ready(), isTrue, reason: '应完成当前翻页阶段');
}

void main() {
  testWidgets('32项缓存容纳两张缩略图页，3D往返快照和落页均不缺图', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.8125;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final key = GlobalKey();
    final (session, cache) = await _show(tester, key);
    await _expectPaper(tester, key, 0);
    final view = tester.state<PageTurnViewState>(find.byType(PageTurnView));
    for (final next in [true, false, true, false]) {
      final spine = next ? 1 : 0;
      view.controller.request(next);
      await _pumpUntil(tester, () => view.controller.targetImage != null);
      await _expectImage(tester, view.controller.originImage!, 1 - spine);
      await _expectImage(tester, view.controller.targetImage!, spine);
      await _pumpUntil(tester, () => !view.controller.active);
      expect(view.controller.phase, PageTurnPhase.idle);
      expect(session.page!.spineIndex, spine);
      await _expectPaper(tester, key, spine);
      await _advance(tester);
      await _expectPaper(tester, key, spine);
      expect(cache.entryCount, lessThanOrEqualTo(32));
      expect(cache.byteCount, lessThanOrEqualTo(32 << 20));
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
