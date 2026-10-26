import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/table_layout.dart';
import 'package:reader_core/paint/page_renderer.dart';
import 'package:reader_mobile/reader/epub_chapter_source.dart';

/// CSS 属性对照：把 cases/*.json 用引擎渲染成同尺寸 PNG，并导出每页的
/// 块/行/表格单元格几何与计算样式，供与浏览器（render_browser.mjs）
/// 结果逐项比对。
///
/// 只在 CSS_PARITY=1 时运行，避免污染日常测试。
const _width = 350.0;
const _height = 800.0;

/// 最多导出页数：跨页用例只需第 1/2 页，多导无用数据。
const _maxPages = 2;

/// JSON 不支持 Infinity/NaN，统一降成 null（compare.py 视为「未知」）。
double? _n(double value) => value.isFinite ? value : null;

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

Map<String, Object?> _rectJson(double x, double y, double w, double h) =>
    <String, Object?>{'x': _n(x), 'y': _n(y), 'w': _n(w), 'h': _n(h)};

/// 块/单元格共用的计算样式快照（只导出可比对的数值型字段）。
Map<String, Object?> _styleJson(ComputedStyle? style) {
  if (style == null) {
    return <String, Object?>{};
  }
  return <String, Object?>{
    'fontSize': _n(style.fontSize),
    'lineHeight': _n(style.lineHeight),
    'letterSpacing': _n(style.letterSpacing),
    'wordSpacing': _n(style.wordSpacing),
    'textAlign': style.textAlign.name,
    'textIndent': _n(style.textIndent),
    'color': _color(style.color),
    'backgroundColor': _color(style.backgroundColor),
    'margin': <double?>[
      _n(style.margin.top),
      _n(style.margin.right),
      _n(style.margin.bottom),
      _n(style.margin.left),
    ],
    'padding': <double?>[
      _n(style.padding.top),
      _n(style.padding.right),
      _n(style.padding.bottom),
      _n(style.padding.left),
    ],
    'border': <double?>[
      _n(style.borders.top.width),
      _n(style.borders.right.width),
      _n(style.borders.bottom.width),
      _n(style.borders.left.width),
    ],
    'textTransform': style.textTransform.name,
    'fontWeight': style.fontWeight,
    'italic': style.italic,
    'whiteSpace': style.whiteSpace.name,
    'verticalAlign': style.verticalAlign.name,
    'boxSizing': style.boxSizing.name,
  };
}

/// 单元格几何：坐标换成页面绝对坐标（与浏览器 td 的 border box 对齐）。
///
/// 口径与绘制端（PagePainter._paintTable）一致：表格原点 = 块顶/块左，
/// 格内文字再叠加 padding + border 与 vertical-align 偏移。
Map<String, Object?> _cellJson(
  TableCellRender cell,
  double blockLeft,
  double blockTop,
  int cellIndex,
) {
  final style = cell.style;
  final cellLeft = blockLeft + cell.rect.left;
  final cellTop = blockTop + cell.rect.top;
  final topInset = style.padding.top + style.borders.top.width;
  final bottomInset = style.padding.bottom + style.borders.bottom.width;
  final innerHeight = math.max(0.0, cell.rect.height - topInset - bottomInset);
  final freeSpace = math.max(0.0, innerHeight - cell.layout.height);
  final alignOffset = switch (style.verticalAlign) {
    CssVerticalAlign.middle => freeSpace / 2,
    CssVerticalAlign.bottom => freeSpace,
    _ => 0.0,
  };
  final contentLeft =
      cellLeft + style.padding.left + style.borders.left.width;
  var lineY = cellTop + topInset + alignOffset;
  final lines = <Map<String, Object?>>[];
  for (final line in cell.layout.lines) {
    lines.add(<String, Object?>{
      'x': _n(contentLeft + line.offsetX),
      'y': _n(lineY),
      'w': _n(line.advanceWidth),
      'h': _n(line.height),
    });
    lineY += line.height;
  }
  return <String, Object?>{
    'row': cell.row,
    'col': cellIndex,
    'rect': _rectJson(
      cellLeft,
      cellTop,
      cell.rect.width,
      cell.rect.height,
    ),
    'text': cell.layout.text,
    'lines': lines,
    'style': _styleJson(style),
  };
}

Map<String, Object?> _blockJson(PageBlockSlice slice, double sliceTop) {
  final block = slice.block;
  final style = block.style;
  // 切片顶 + 段前扩展 = 边框盒顶（与浏览器 border box 对齐）。
  final top = sliceTop + slice.leadingExtent;
  final left = slice.leftInset + (style?.margin.left ?? 0);
  final lines = <Map<String, Object?>>[];
  for (var i = slice.startLine; i < slice.endLine; i++) {
    final line = block.layout.lines[i];
    lines.add(<String, Object?>{
      'x': _n(left + line.offsetX),
      'y': _n(top + line.top),
      'w': _n(line.advanceWidth),
      'h': _n(line.height),
    });
  }
  // 行内样式区间（b/strong/span 等）：一块多 run 时全部导出，供对照浏览器
  // 行内元素的字重/字号/斜体（相对字重、行内字号覆盖）。单 run 块不导。
  final runs = <Map<String, Object?>>[];
  if (block.layout.runs.length > 1) {
    for (final run in block.layout.runs.take(24)) {
      final runStyle = run.style;
      runs.add(<String, Object?>{
        'text': block.layout.text.substring(run.start, run.end),
        'fontWeight': runStyle.fontWeight,
        'italic': runStyle.italic,
        'fontSize': _n(runStyle.fontSize),
      });
    }
  }
  final cells = <Map<String, Object?>>[];
  final table = block.table;
  if (table != null) {
    final seen = <int, int>{};
    for (final cell in table.cells) {
      final index = seen[cell.row] ?? 0;
      seen[cell.row] = index + 1;
      cells.add(_cellJson(cell, left, top, index));
    }
  }
  // 块宽三种口径分开报，避免拿「最长行宽」当边框盒宽与浏览器比：
  // - contentWidth：排版可用内容宽（maxWidth，pre/nowrap 下可能是 Infinity）；
  // - longestLineW：最长行宽（仅供留档，不做块宽比较）；
  // - bboxW：边框盒宽 = contentWidth + padding + border；未知时 null。
  final contentWidth = block.layout.maxWidth;
  final padH = (style?.padding.left ?? 0) + (style?.padding.right ?? 0);
  final borderH =
      (style?.borders.left.width ?? 0) + (style?.borders.right.width ?? 0);
  final bboxW = contentWidth.isFinite ? contentWidth + padH + borderH : null;
  return <String, Object?>{
    'text': block.layout.text,
    'rect': _rectJson(
      left,
      top,
      block.layout.width,
      slice.height -
          slice.leadingExtent -
          (slice.endLine == block.layout.lineCount ? slice.trailingExtent : 0),
    ),
    // 配对用角色：表格块 / 列表项块（有标记）/ 普通块。浏览器端 ul、ol
    // 等容器不参与配对，li 只与列表项块配对（列表项无标记时由
    // compare.py 的兜底轮次处理）。
    'role': block.table != null
        ? 'table'
        : (block.listMarker != null ? 'li' : 'block'),
    'listMarker': block.listMarker,
    'lines': lines,
    'runs': runs,
    'cells': cells,
    'slice': <String, Object?>{
      'startLine': slice.startLine,
      'endLine': slice.endLine,
      'lineCount': block.layout.lineCount,
      'overlay': slice.overlay,
      'continuesBefore': slice.continuesBefore,
      'continuesAfter': slice.continuesAfter,
    },
    'contentWidth': _n(contentWidth),
    'longestLineW': _n(block.layout.width),
    'bboxW': _n(bboxW ?? double.nan),
    'style': _styleJson(style),
  };
}

Map<String, Object?> _pageJson(PageContent page) {
  var y = page.topPadding;
  final blocks = <Map<String, Object?>>[];
  for (final slice in page.slices) {
    // 浮动覆盖切片不推进流游标（与绘制端一致）。
    final sliceTop = slice.overlay ? (slice.absoluteTop ?? y) : y;
    blocks.add(_blockJson(slice, sliceTop));
    if (!slice.overlay) {
      y += slice.height;
    }
  }
  return <String, Object?>{
    'index': page.pageIndex,
    'topPadding': _n(page.topPadding),
    'usedHeight': _n(page.usedHeight),
    'blocks': blocks,
  };
}

/// 递归收集 null 几何（引擎返回 Infinity/NaN 的位置），供报告标注。
///
/// 只关心几何数值；`role`/`listMarker` 这类可空语义字段为 null 属正常，
/// 不当作非有限几何上报。
void _collectNulls(Object? node, String path, List<String> out) {
  if (out.length >= 20) {
    return;
  }
  if (node is Map) {
    node.forEach((key, value) {
      if (key == 'role' || key == 'listMarker') {
        return;
      }
      final next = '$path.$key';
      if (value == null) {
        out.add(next);
      } else {
        _collectNulls(value, next, out);
      }
    });
  } else if (node is List) {
    for (var i = 0; i < node.length; i++) {
      _collectNulls(node[i], '$path[$i]', out);
    }
  }
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
    // 默认输出目录；并行验证时用 CSS_PARITY_OUT 隔离，避免互相覆盖。
    final outDir = Directory(
      Platform.environment['CSS_PARITY_OUT'] ?? '/tmp/css_parity',
    )..createSync(recursive: true);

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

      final pageJson = <Map<String, Object?>>[
        for (final item in pages.take(_maxPages)) _pageJson(item),
      ];
      final nulls = <String>[];
      _collectNulls(pageJson, '', nulls);
      File('${outDir.path}/engine_$name.json').writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(<String, Object?>{
          'pageSize': <String, Object?>{'w': _width, 'h': _height},
          'pageCount': pages.length,
          'pages': pageJson,
          'nullGeometry': nulls,
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
      print('ok $name pages=${pages.length} blocks=${page.slices.length}');
    }
  }, skip: Platform.environment['CSS_PARITY'] != '1');
}
