import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/paint/page_renderer.dart';
import 'package:reader_mobile/reader/epub_chapter_source.dart';

/// CSS 属性对照：把 cases/*.json 用引擎渲染成同尺寸 PNG，并导出每块/每行
/// 几何与计算样式，供与浏览器（render_browser.mjs）结果逐项比对。
///
/// 只在 CSS_PARITY=1 时运行，避免污染日常测试。
const _width = 350.0;
const _height = 800.0;

Uint8List _book(String body, String css) {
  final chapter = '<?xml version="1.0" encoding="UTF-8"?>'
      '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>t</title>'
      '<link rel="stylesheet" type="text/css" href="../Styles/s.css"/>'
      '</head><body>$body</body></html>';
  const opf = '<?xml version="1.0" encoding="UTF-8"?>'
      '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" '
      'unique-identifier="b"><metadata '
      'xmlns:dc="http://purl.org/dc/elements/1.1/">'
      '<dc:identifier id="b">urn:uuid:parity</dc:identifier>'
      '<dc:title>t</dc:title><dc:language>zh</dc:language>'
      '<meta property="dcterms:modified">2026-01-01T00:00:00Z</meta>'
      '</metadata><manifest>'
      '<item id="c" href="Text/c.xhtml" media-type="application/xhtml+xml"/>'
      '<item id="s" href="Styles/s.css" media-type="text/css"/>'
      '</manifest><spine><itemref idref="c"/></spine></package>';
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

Map<String, Object?> _color(Color? color) => color == null
    ? <String, Object?>{}
    : <String, Object?>{
        'r': color.r,
        'g': color.g,
        'b': color.b,
        'a': color.a,
      };

Map<String, Object?> _blockJson(PageBlockSlice slice, double y) {
  final block = slice.block;
  final style = block.style;
  // 版面 y 含段前距；边框盒顶 = y + leading（与浏览器 border box 对齐）。
  final top = y + slice.leadingExtent;
  final lines = <Map<String, Object?>>[];
  for (var i = slice.startLine; i < slice.endLine; i++) {
    final line = block.layout.lines[i];
    lines.add(<String, Object?>{
      'x': line.offsetX + slice.leftInset + (style?.margin.left ?? 0),
      'y': top + line.top,
      'w': line.width,
      'h': line.height,
    });
  }
  return <String, Object?>{
    'text': block.layout.text,
    'rect': <String, Object?>{
      'x': slice.leftInset + (style?.margin.left ?? 0),
      'y': top,
      'w': block.layout.width,
      // 边框盒高 = 切片高 - 段前/段后扩展（切片高含首尾额外高度）。
      'h': slice.height - slice.leadingExtent -
          (slice.endLine == block.layout.lineCount ? slice.trailingExtent : 0),
    },
    'lines': lines,
    'maxWidth': block.layout.maxWidth,
    'layoutWidth': block.layout.width,
    'style': <String, Object?>{
      'fontSize': style?.fontSize,
      'lineHeight': style?.lineHeightFactor == null
          ? null
          : style!.fontSize * style.lineHeightFactor!,
      'letterSpacing': style?.letterSpacing,
      'wordSpacing': style?.wordSpacing,
      'textAlign': style?.textAlign.name,
      'textIndent': style?.textIndent,
      'color': _color(style?.color),
      'backgroundColor': _color(style?.backgroundColor),
      'margin': style == null
          ? null
          : <double>[
              style.margin.top,
              style.margin.right,
              style.margin.bottom,
              style.margin.left,
            ],
      'padding': style == null
          ? null
          : <double>[
              style.padding.top,
              style.padding.right,
              style.padding.bottom,
              style.padding.left,
            ],
      'border': style == null
          ? null
          : <double>[
              style.borders.top.width,
              style.borders.right.width,
              style.borders.bottom.width,
              style.borders.left.width,
            ],
      'textTransform': style?.textTransform.name,
      'fontWeight': style?.fontWeight,
      'italic': style?.italic,
      'whiteSpace': style?.whiteSpace.name,
    },
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('导出引擎渲染几何与截图', () async {
    final root = Directory.current;
    final casesDir = Directory('${root.path}/../../tool/css_parity/cases');
    if (!casesDir.existsSync()) {
      // ignore: avoid_print
      print('SKIP 缺少 cases 目录：${casesDir.path}');
      return;
    }
    final outDir = Directory('/tmp/css_parity')..createSync(recursive: true);

    final song = FontLoader('builtin_song')
      ..addFont(rootBundle.load('assets/fonts/SourceHanSerifCN-Regular.otf'))
      ..addFont(rootBundle.load('assets/fonts/SourceHanSerifCN-Bold.otf'));
    await song.load();

    final files = casesDir
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.json'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    for (final file in files) {
      final caseData =
          jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
      final name = caseData['name']! as String;
      final source = await EpubChapterSource.open(
        _book(caseData['html']! as String, caseData['css']! as String),
        contentWidth: _width,
        contentHeight: _height,
        verifyCrc: false,
      );
      await source.applyOverrides(const ReaderOverrides());
      final pages = await source.loadChapter(0);
      final page = pages.first;

      var y = page.topPadding;
      final blocks = <Map<String, Object?>>[];
      for (final slice in page.slices) {
        blocks.add(_blockJson(slice, y));
        y += slice.height;
      }
      File('${outDir.path}/engine_$name.json').writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(<String, Object?>{
          'pageSize': <String, Object?>{'w': _width, 'h': _height},
          'blocks': blocks,
        }),
      );

      final recorder = ui.PictureRecorder();
      PagePainter(
        background: const Color(0xFFFFFFFF),
        textColor: const Color(0xFF000000),
      ).paint(
        Canvas(recorder),
        page,
        pageSize: const Size(_width, _height),
      );
      final image = await recorder.endRecording().toImage(
        _width.toInt(),
        _height.toInt(),
      );
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      File('${outDir.path}/engine_$name.png')
          .writeAsBytesSync(png!.buffer.asUint8List());
      image.dispose();
      // ignore: avoid_print
      print('ok $name blocks=${blocks.length}');
    }
  }, skip: Platform.environment['CSS_PARITY'] != '1');
}
