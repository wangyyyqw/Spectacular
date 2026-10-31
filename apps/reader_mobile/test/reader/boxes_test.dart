import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/paint/page_renderer.dart';
import 'package:reader_mobile/reader/epub_chapter_source.dart';
import 'package:reader_ui/panels/settings_panel.dart';

/// 卡片四边框闭合（P9-25）：容器被 flat 管线拆成多个块，背景与左右边框
/// 要拼回一片，四边都要画出来且不留缝。
const _pageSize = Size(340, 400);

Uint8List _book(String body, String css) {
  final chapter = '<?xml version="1.0" encoding="UTF-8"?>'
      '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>t</title>'
      '<link rel="stylesheet" type="text/css" href="../Styles/s.css"/>'
      '</head><body>$body</body></html>';
  const opf = '<?xml version="1.0" encoding="UTF-8"?>'
      '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="b">'
      '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
      '<dc:identifier id="b">urn:uuid:cardframe</dc:identifier>'
      '<dc:title>t</dc:title><dc:language>zh</dc:language>'
      '<meta property="dcterms:modified">2026-01-01T00:00:00Z</meta></metadata>'
      '<manifest><item id="c" href="Text/c.xhtml" '
      'media-type="application/xhtml+xml"/>'
      '<item id="s" href="Styles/s.css" media-type="text/css"/></manifest>'
      '<spine><itemref idref="c"/></spine></package>';
  const container = '<?xml version="1.0" encoding="UTF-8"?>'
      '<container version="1.0" '
      'xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
      '<rootfiles><rootfile full-path="OEBPS/content.opf" '
      'media-type="application/oebps-package+xml"/></rootfiles></container>';
  final files = <String, List<int>>{
    'mimetype': utf8.encode('application/epub+zip'),
    'META-INF/container.xml': utf8.encode(container),
    'OEBPS/content.opf': utf8.encode(opf),
    'OEBPS/Text/c.xhtml': utf8.encode(chapter),
    'OEBPS/Styles/s.css': utf8.encode(css),
  };
  final archive = Archive();
  files.forEach((name, bytes) {
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  });
  return Uint8List.fromList(ZipEncoder().encodeBytes(archive));
}

Future<ByteData> _renderPage({
  String? body,
  String? css,
  Color background = const Color(0xFFFFFFFF),
}) async {
  final source = await EpubChapterSource.open(
    _book(
      body ?? '<div class="card"><p>第一段文字</p><p>第二段文字</p></div>',
      css ??
          '.card { border: 2px solid #00ff00; border-left: 6px solid #ff0000; '
              'background-color: #112233; padding: 6px; }',
    ),
    contentWidth: _pageSize.width + 2 * ReaderSettingsDefaults.horizontalPadding,
    contentHeight: _pageSize.height + 32,
    verifyCrc: false,
  );
  await source.applyOverrides(ReaderSettingsDefaults.overrides);
  final pages = await source.loadChapter(0);
  final recorder = ui.PictureRecorder();
  PagePainter(background: background).paint(
    Canvas(recorder),
    pages.first,
    pageSize: _pageSize,
  );
  final image = await recorder.endRecording().toImage(
    _pageSize.width.toInt(),
    _pageSize.height.toInt(),
  );
  final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  return bytes!;
}

/// 边框色近似判定：CSS 行高是小数时（如 1.7×15 = 25.5），卡片底边会落在
/// 半像素上，抗锯齿让边缘行不再是纯色；这里按「明显偏绿」判定。
bool _isGreenish(Color color) =>
    color.g > 0.35 && color.r < 0.6 && color.b < 0.6;

Color _pixel(ByteData bytes, int x, int y) {
  final offset = (y * _pageSize.width.toInt() + x) * 4;
  return Color.fromARGB(
    bytes.getUint8(offset + 3),
    bytes.getUint8(offset),
    bytes.getUint8(offset + 1),
    bytes.getUint8(offset + 2),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('行内元素的背景与边框画出（P9-24）', () async {
    final bytes = await _renderPage(
      body: '<p>前缀<span class="chip">标签文字</span>后缀</p>',
      css: '.chip { display: inline-block; padding: 2px 4px; '
          'border: 1px solid #d4af37; background-color: #1f1a10; '
          'color: #f3d382; }',
    );
    const gold = Color(0xFFD4AF37);
    const chipBackground = Color(0xFF1F1A10);
    var goldPixels = 0;
    var chipPixels = 0;
    for (var i = 0; i < bytes.lengthInBytes; i += 4) {
      final color = Color.fromARGB(
        bytes.getUint8(i + 3),
        bytes.getUint8(i),
        bytes.getUint8(i + 1),
        bytes.getUint8(i + 2),
      );
      if (color == gold) {
        goldPixels += 1;
      } else if (color == chipBackground) {
        chipPixels += 1;
      }
    }
    expect(goldPixels, greaterThan(0), reason: '行内元素的金色边框应画出');
    expect(chipPixels, greaterThan(0), reason: '行内元素的背景色应画出');
  });

  test('普通行内 b 的白色底在深色页背景上可见', () async {
    final bytes = await _renderPage(
      body: '<div class="bookcover"><b>人</b> <b>物</b> <b>关</b> '
          '<b>系</b> <b>图</b></div>',
      css: '.bookcover { color: #000002; text-align: center; '
          'margin-top: 40px; width: 10em; } '
          '.bookcover b { background-color: #fff; padding: 3px; '
          'font-weight: bold; }',
      background: const Color(0xFF07151B),
    );
    var whitePixels = 0;
    for (var i = 0; i < bytes.lengthInBytes; i += 4) {
      if (bytes.getUint8(i) == 0xFF &&
          bytes.getUint8(i + 1) == 0xFF &&
          bytes.getUint8(i + 2) == 0xFF) {
        whitePixels += 1;
      }
    }
    expect(whitePixels, greaterThan(100), reason: 'b 的白色行内底应可见');
  });

  test('卡片四边框闭合且背景连成一片（P9-25）', () async {
    final bytes = await _renderPage();
    const red = Color(0xFFFF0000);

    var redColumns = 0;
    var greenRows = 0;
    for (var x = 0; x < _pageSize.width.toInt(); x++) {
      if (_pixel(bytes, x, 30) == red) {
        redColumns += 1;
      }
    }
    expect(redColumns, greaterThan(0), reason: '左边框应画出');

    // 顶/底边框：逐行扫描是否出现绿色横向描边。
    var topBorderY = -1;
    var bottomBorderY = -1;
    for (var y = 0; y < _pageSize.height.toInt(); y++) {
      var hits = 0;
      for (var x = 0; x < _pageSize.width.toInt(); x++) {
        if (_isGreenish(_pixel(bytes, x, y))) {
          hits += 1;
        }
      }
      if (hits > _pageSize.width ~/ 2) {
        greenRows += 1;
        if (topBorderY < 0) {
          topBorderY = y;
        }
        bottomBorderY = y;
      }
    }
    expect(greenRows, greaterThanOrEqualTo(2), reason: '顶边框与底边框都要画出');

    // 右边框：右侧 20px 带宽内应有绿色竖线。
    var greenRightBand = 0;
    for (var y = 0; y < _pageSize.height.toInt(); y++) {
      for (var x = _pageSize.width.toInt() - 20;
          x < _pageSize.width.toInt();
          x++) {
        if (_isGreenish(_pixel(bytes, x, y))) {
          greenRightBand += 1;
        }
      }
    }
    expect(greenRightBand, greaterThan(0), reason: '右边框应画出');

    // 背景连成一片：边框之间的中轴上不应露出页面白底。
    final white = const Color(0xFFFFFFFF);
    var whiteHoles = 0;
    for (var y = topBorderY + 2; y < bottomBorderY - 1; y++) {
      if (_pixel(bytes, _pageSize.width ~/ 2, y) == white) {
        whiteHoles += 1;
      }
    }
    expect(whiteHoles, 0, reason: '卡片内部的块间缝隙也必须被背景填满');
  });
}
