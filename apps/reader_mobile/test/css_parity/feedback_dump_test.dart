import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/table_layout.dart';
import 'package:reader_core/paint/image_cache.dart';
import 'package:reader_core/paint/page_renderer.dart';
import 'package:reader_core/epub/epub_chapter_source.dart';
import 'package:reader_mobile/reader/reader_settings.dart';

/// 按外部清单导出原书页面，版权语料与截图均不写入仓库。
/// 清单格式：[{"id":"001","path":"/绝对路径.epub","spines":[0,1]}]。
/// 此入口检查实际分页和绘制；样式是否与多看一致仍需逐图核对。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final manifest = Platform.environment['FEEDBACK_MANIFEST'];
  if (manifest == null) {
    test('原书样式导出需要外部清单', () {}, skip: '未设置 FEEDBACK_MANIFEST');
    return;
  }
  final entries = jsonDecode(File(manifest).readAsStringSync()) as List;
  setUpAll(_loadFonts);
  for (final entry in entries.cast<Map<String, dynamic>>()) {
    test(
      '原书样式导出 ${entry['id']}',
      () => _dumpBook(entry),
      timeout: const Timeout(Duration(minutes: 15)),
    );
  }
}

const _size = ui.Size(350, 700);

Future<void> _dumpBook(Map<String, dynamic> entry) async {
  final output = Directory(
    '${Platform.environment['FEEDBACK_OUTPUT'] ?? '/tmp/spectacular-feedback/render'}/${entry['id']}',
  )..createSync(recursive: true);
  final source = await EpubChapterSource.openFile(
    File(entry['path'] as String),
    contentWidth: _size.width,
    contentHeight: _size.height,
    style: ComputedStyle(const {
      'font-size': '16px',
      'font-family': 'builtin_song',
    }),
  );
  addTearDown(source.close);
  if (Platform.environment['FEEDBACK_READER_SETTINGS'] == '1') {
    await source.applyOverrides(ReaderSettings.defaults.overrides);
  }
  final results = <Map<String, Object?>>[];
  for (final spine in (entry['spines'] as List).cast<int>()) {
    results.add(await _chapter(source, spine, output));
  }
  File('${output.path}/report.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({
      'path': entry['path'],
      'pageWidth': _size.width,
      'pageHeight': _size.height,
      'readerSettings': Platform.environment['FEEDBACK_READER_SETTINGS'] == '1',
      'chapters': results,
    }),
  );
}

Future<void> _loadFonts() async {
  final fonts = FontLoader('builtin_song')
    ..addFont(rootBundle.load('assets/fonts/SourceHanSerifCN-Regular.otf'))
    ..addFont(rootBundle.load('assets/fonts/SourceHanSerifCN-Bold.otf'));
  await fonts.load();
}

Future<Map<String, Object?>> _chapter(
  EpubChapterSource source,
  int spine,
  Directory output,
) async {
  final pages = await source.loadChapter(spine);
  expect(pages, isNotEmpty, reason: '章节 $spine 未产出页面');
  final limit = int.parse(Platform.environment['FEEDBACK_MAX_PAGES'] ?? '3');
  final summaries = <Map<String, Object?>>[];
  for (var index = 0; index < pages.length; index++) {
    final page = pages[index];
    _checkPage(page, spine, index);
    summaries.add({
      'index': index,
      'usedHeight': page.usedHeight,
      'background': page.background?.imageUrl,
      'blocks': [for (final slice in page.slices) _slice(slice)],
    });
    if (limit == 0 || index < limit) {
      await _draw(source, page, '${output.path}/spine-$spine-page-$index.png');
    }
  }
  return {
    'spine': spine,
    'pageCount': pages.length,
    'warning': source.layoutWarningFor(spine),
    'pages': summaries,
  };
}

void _checkPage(PageContent page, int spine, int index) {
  expect(page.pageHeight.isFinite && page.pageHeight > 0, isTrue);
  expect(
    page.usedHeight.isFinite,
    isTrue,
    reason:
        '章节 $spine 第 $index 页 usedHeight=${page.usedHeight}；'
        '切片高度=${page.slices.map((slice) => slice.height).toList()}',
  );
  for (final slice in page.slices) {
    // 切片流占位包含作者负外边距；实际内容盒才需要非负尺寸。
    expect(slice.height.isFinite, isTrue);
    expect(slice.block.height.isFinite && slice.block.height >= 0, isTrue);
    expect(
      slice.block.layout.width.isFinite && slice.block.layout.width >= 0,
      isTrue,
    );
    expect(slice.leftInset.isFinite, isTrue);
    expect(slice.absoluteTop == null || slice.absoluteTop!.isFinite, isTrue);
  }
}

Map<String, Object?> _slice(PageBlockSlice slice) => {
  'text': slice.block.layout.text,
  'startCfi': slice.block.startCfi,
  'startLine': slice.startLine,
  'endLine': slice.endLine,
  'height': slice.height,
  'leadingExtent': slice.leadingExtent,
  'trailingExtent': slice.trailingExtent,
  'blockHeight': slice.block.height,
  'layoutHeight': slice.block.layout.height,
  'leftInset': slice.leftInset,
  'absoluteTop': slice.absoluteTop,
  'absolute': slice.block.absolute,
  'style': slice.block.style?.values,
  'cells': [
    for (final cell in slice.block.table?.cells ?? const <TableCellRender>[])
      {
        'text': cell.layout.text,
        'style': cell.style.values,
        'rect': [
          cell.rect.left,
          cell.rect.top,
          cell.rect.width,
          cell.rect.height,
        ],
        'lines': [
          for (final line in cell.layout.lines)
            {
              'start': line.start,
              'end': line.end,
              'width': line.width,
              'height': line.height,
            },
        ],
      },
  ],
  'containers': [
    for (final fragment in slice.block.containers)
      fragment.container.style.values,
  ],
};

Iterable<PageBlock> _blocks(PageBlock block) sync* {
  yield block;
  for (final line in block.layout.lines) {
    for (final box in line.inlineBoxes) {
      if (box.spec.payload case final PageBlock payload) {
        yield* _blocks(payload);
      }
    }
  }
  for (final cell in block.table?.cells ?? const <TableCellRender>[]) {
    for (final line in cell.layout.lines) {
      for (final box in line.inlineBoxes) {
        if (box.spec.payload case final PageBlock payload) {
          yield* _blocks(payload);
        }
      }
    }
  }
}

Set<String> _imageUrls(PageContent page) => {
  if (page.background?.imageUrl case final String url) url,
  for (final slice in page.slices)
    for (final block in _blocks(slice.block)) ...{
      for (final image in block.inlineImages) image.url,
      if (block.style?.listStyleImage != null) block.style!.listStyleImage!,
      for (final layer
          in block.style?.backgroundLayers ?? const <CssBackgroundLayer>[])
        if (layer.image != null) layer.image!,
      for (final cell in block.table?.cells ?? const <TableCellRender>[])
        for (final layer in cell.style.backgroundLayers)
          if (layer.image != null) layer.image!,
      for (final fragment in block.containers)
        for (final layer in fragment.container.style.backgroundLayers)
          if (layer.image != null) layer.image!,
    },
};

Future<DecodedImageCache> _images(
  EpubChapterSource source,
  PageContent page,
) async {
  final urls = _imageUrls(page);
  final images = DecodedImageCache(
    loadBytes: (url) async => _imageBytes(source, url),
  )..protectedUrls = urls;
  for (final url in urls) {
    if (await images.load(url, displayWidth: _size.width) == null) {
      // ignore: avoid_print
      print('图片未解码或超出阅读缓存预算：$url');
    }
  }
  return images;
}

/// 与正式阅读器同序尝试原路径、OPF 目录和前 64 个章节目录。
Uint8List? _imageBytes(EpubChapterSource source, String url) {
  final document = source.document;
  final direct = document.archive.readBytes(url);
  if (direct != null) return direct;
  final resolved = document.resources.resolve(url);
  if (resolved != null) {
    final bytes = document.archive.readBytes(resolved);
    if (bytes != null) return bytes;
  }
  for (final item in document.spine.take(64)) {
    final slash = item.href.lastIndexOf('/');
    final baseDir = slash < 0 ? '' : item.href.substring(0, slash);
    final candidate = document.resources.resolve(url, baseDir: baseDir);
    if (candidate == null) continue;
    final bytes = document.archive.readBytes(candidate);
    if (bytes != null) return bytes;
  }
  return null;
}

Future<void> _draw(
  EpubChapterSource source,
  PageContent page,
  String path,
) async {
  final images = await _images(source, page);
  final recorder = ui.PictureRecorder();
  ui.Picture? picture;
  try {
    PagePainter(
      background: const ui.Color(0xffffffff),
      textColor: const ui.Color(0xff000000),
      imageLookup: images.lookup,
      listMarkerImageOf: (block) => block.style?.listStyleImage,
    ).paint(ui.Canvas(recorder), page, pageSize: _size);
    picture = recorder.endRecording();
    final image = await picture.toImage(
      _size.width.toInt(),
      _size.height.toInt(),
    );
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      File(path).writeAsBytesSync(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  } finally {
    picture?.dispose();
    if (recorder.isRecording) recorder.endRecording().dispose();
    images.clear();
  }
}
