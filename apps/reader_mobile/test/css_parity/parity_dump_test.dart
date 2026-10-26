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

/// 长度值（保留百分比/auto 标记，绘制层按盒尺寸解算）。
Map<String, Object?> _lengthJson(CssLength? length) => length == null
    ? <String, Object?>{}
    : <String, Object?>{
        'value': _n(length.value),
        'percent': length.isPercent,
        'auto': length.isAuto,
      };

/// transform 概要（kind + 数值；不导原始对象，便于 compare 直接比）。
Map<String, Object?> _transformJson(CssTransform transform) {
  final json = <String, Object?>{'kind': transform.kind.name};
  switch (transform.kind) {
    case CssTransformKind.translate:
      json['x'] = _lengthJson(transform.x);
      json['y'] = _lengthJson(transform.y);
    case CssTransformKind.scale:
      json['sx'] = _n(transform.sx ?? 1);
      json['sy'] = _n(transform.sy ?? transform.sx ?? 1);
    case CssTransformKind.rotate:
      json['angleDeg'] = _n(transform.angleDeg ?? 0);
    case CssTransformKind.skew:
      json['axDeg'] = _n(transform.axDeg);
      json['ayDeg'] = _n(transform.ayDeg);
    case CssTransformKind.matrix:
      json['values'] = <double?>[for (final v in transform.values ?? const <double>[]) _n(v)];
  }
  return json;
}

/// 2D 仿射矩阵（CSS matrix(a,b,c,d,e,f)：x' = a·x + c·y + e，y' = b·x + d·y + f）。
List<double> _mmul(List<double> a, List<double> b) => <double>[
  a[0] * b[0] + a[2] * b[1],
  a[1] * b[0] + a[3] * b[1],
  a[0] * b[2] + a[2] * b[3],
  a[1] * b[2] + a[3] * b[3],
  a[0] * b[4] + a[2] * b[5] + a[4],
  a[1] * b[4] + a[3] * b[5] + a[5],
];

/// 单个 transform 函数的矩阵；百分比位移按边框盒宽/高解算。
List<double> _transformMatrix(CssTransform transform, double width, double height) {
  switch (transform.kind) {
    case CssTransformKind.translate:
      final tx = transform.x?.resolve(width) ?? 0;
      final ty = transform.y?.resolve(height) ?? 0;
      return <double>[1, 0, 0, 1, tx, ty];
    case CssTransformKind.scale:
      final sx = transform.sx ?? 1;
      final sy = transform.sy ?? sx;
      return <double>[sx, 0, 0, sy, 0, 0];
    case CssTransformKind.rotate:
      final radians = (transform.angleDeg ?? 0) * math.pi / 180;
      final cos = math.cos(radians);
      final sin = math.sin(radians);
      return <double>[cos, sin, -sin, cos, 0, 0];
    case CssTransformKind.skew:
      final ax = (transform.axDeg) * math.pi / 180;
      final ay = (transform.ayDeg) * math.pi / 180;
      return <double>[1, math.tan(ay), math.tan(ax), 1, 0, 0];
    case CssTransformKind.matrix:
      final values = transform.values ?? const <double>[];
      if (values.length < 6) {
        return <double>[1, 0, 0, 1, 0, 0];
      }
      return <double>[values[0], values[1], values[2], values[3], values[4], values[5]];
  }
}

/// 按 `transform` 列表 + `transform-origin` 计算边框盒的轴对齐 bbox。
///
/// 浏览器 `getBoundingClientRect` 报变换后的 bbox，引擎导出的是未变换
/// 几何；对照时用本函数把四个角变换后取 min/max，才能同口径比较。
Map<String, Object?>? _transformedBbox(
  ComputedStyle style, {
  required double x,
  required double y,
  required double width,
  required double height,
}) {
  if (style.transforms.isEmpty || width <= 0 || height <= 0) {
    return null;
  }
  var matrix = <double>[1, 0, 0, 1, 0, 0];
  for (final transform in style.transforms) {
    matrix = _mmul(matrix, _transformMatrix(transform, width, height));
  }
  // transform-origin 是相对边框盒的偏移，先换算成绝对坐标再做绕点旋转。
  final originX = x + (style.transformOriginX.resolve(width) ?? width / 2);
  final originY = y + (style.transformOriginY.resolve(height) ?? height / 2);
  final full = _mmul(
    <double>[1, 0, 0, 1, originX, originY],
    _mmul(matrix, <double>[1, 0, 0, 1, -originX, -originY]),
  );
  var minX = double.infinity;
  var minY = double.infinity;
  var maxX = double.negativeInfinity;
  var maxY = double.negativeInfinity;
  for (final corner in <List<double>>[
    <double>[x, y],
    <double>[x + width, y],
    <double>[x, y + height],
    <double>[x + width, y + height],
  ]) {
    final px = full[0] * corner[0] + full[2] * corner[1] + full[4];
    final py = full[1] * corner[0] + full[3] * corner[1] + full[5];
    minX = math.min(minX, px);
    minY = math.min(minY, py);
    maxX = math.max(maxX, px);
    maxY = math.max(maxY, py);
  }
  return _rectJson(minX, minY, maxX - minX, maxY - minY);
}

/// filter 概要（kind + 数值；drop-shadow 展开成偏移/模糊/颜色）。
Map<String, Object?> _filterJson(CssFilter filter) => <String, Object?>{
  'kind': filter.kind.name,
  'amount': _n(filter.amount),
  if (filter.shadow != null) ...<String, Object?>{
    'offsetX': _n(filter.shadow!.offsetX),
    'offsetY': _n(filter.shadow!.offsetY),
    'blur': _n(filter.shadow!.blur),
    'color': _color(filter.shadow!.color),
  },
};

/// 背景渐变概要（种类 + 方向/形状 + 色标位置；位置保留百分比/像素两种标记）。
Map<String, Object?> _gradientJson(CssGradient gradient) {
  final json = <String, Object?>{
    'kind': gradient is CssLinearGradient ? 'linear' : 'radial',
    'repeating': gradient.repeating,
    'stops': <Map<String, Object?>>[
      for (final stop in gradient.stops)
        <String, Object?>{
          'color': _color(stop.color),
          if (stop.position != null) 'position': _n(stop.position!),
          if (stop.positionPx != null) 'positionPx': _n(stop.positionPx!),
        },
    ],
  };
  switch (gradient) {
    case CssLinearGradient():
      json['angleDeg'] = _n(gradient.angle);
    case CssRadialGradient():
      json['shape'] = gradient.shape.name;
      json['centerX'] = _lengthJson(gradient.centerX);
      json['centerY'] = _lengthJson(gradient.centerY);
  }
  return json;
}

/// box-shadow 概要（blur/spread/inset 是本轮新增，绘制层要用）。
Map<String, Object?> _boxShadowJson(CssBoxShadow? shadow) => shadow == null
    ? <String, Object?>{}
    : <String, Object?>{
        'offsetX': _n(shadow.offsetX),
        'offsetY': _n(shadow.offsetY),
        'blur': _n(shadow.blur),
        'spread': _n(shadow.spread),
        'inset': shadow.inset,
        'color': _color(shadow.color),
      };

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
    'textOverflow': style.textOverflow.name,
    // ==== 本轮新增（W5/W7/W11）====
    'transform': <Map<String, Object?>>[
      for (final transform in style.transforms) _transformJson(transform),
    ],
    'transformOriginX': _lengthJson(style.transformOriginX),
    'transformOriginY': _lengthJson(style.transformOriginY),
    'overflow': style.overflow.name,
    'writingMode': style.writingMode.name,
    'textOrientation': style.textOrientation.name,
    'direction': style.direction.name,
    if (style.columnCount != null) 'columnCount': style.columnCount,
    'columnWidth': _lengthJson(style.columnWidth),
    if (style.columnGap != null) 'columnGap': _n(style.columnGap!),
    'columnRule': style.columnRule == null
        ? <String, Object?>{}
        : <String, Object?>{
            'width': _n(style.columnRule!.width),
            'style': style.columnRule!.style.name,
            'color': _color(style.columnRule!.color),
          },
    'hyphens': style.hyphens.name,
    'wordBreak': style.wordBreak.name,
    'overflowWrap': style.overflowWrap.name,
    'filters': <Map<String, Object?>>[
      for (final filter in style.filters) _filterJson(filter),
    ],
    'boxShadow': _boxShadowJson(style.boxShadow),
    'listStylePosition': style.listStylePosition.name,
    'backgroundGradient': style.backgroundGradient == null
        ? <String, Object?>{}
        : _gradientJson(style.backgroundGradient!),
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
  final padV = (style?.padding.top ?? 0) + (style?.padding.bottom ?? 0);
  final borderV =
      (style?.borders.top.width ?? 0) + (style?.borders.bottom.width ?? 0);
  final boxHeight =
      slice.height -
      slice.leadingExtent -
      (slice.endLine == block.layout.lineCount ? slice.trailingExtent : 0) +
      padV +
      borderV;
  final bboxRect = style == null || bboxW == null
      ? null
      : _transformedBbox(
          style,
          x: left - (style.padding.left) - style.borders.left.width,
          y: top - (style.padding.top) - style.borders.top.width,
          width: bboxW,
          height: boxHeight,
        );
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
    // 有 transform 时浏览器量的是变换后 bbox；transformed=true 时
    // compare 用 bboxRect 代替 rect 参与 x/y/w/h 比较。
    'transformed': bboxRect != null,
    'bboxRect': bboxRect,

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
      if (key == 'role' || key == 'listMarker' || key == 'bboxRect') {
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

    final failures = <String>[];
    for (final file in files) {
      final caseData =
          jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
      final name = caseData['name']! as String;
      // 单个用例失败（引擎异常/渲染崩溃）不中断整批：写入带 error 的
      // engine_<name>.json，让 compare 报「缺少数据」，最后统一失败。
      try {
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
      } catch (error) {
        failures.add('$name: $error');
        File('${outDir.path}/engine_$name.json').writeAsStringSync(
          const JsonEncoder.withIndent('  ').convert(<String, Object?>{
            'pageSize': <String, Object?>{'w': _width, 'h': _height},
            'pageCount': 0,
            'pages': <Object?>[],
            'nullGeometry': <String>[],
            'error': '$error',
          }),
        );
        // ignore: avoid_print
        print('FAIL $name: $error');
      }
    }
    if (failures.isNotEmpty) {
      fail('引擎渲染失败 ${failures.length} 个用例：\n${failures.join('\n')}');
    }
  }, skip: Platform.environment['CSS_PARITY'] != '1');
}
