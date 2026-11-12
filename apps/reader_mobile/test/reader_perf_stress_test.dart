import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/epub/epub_chapter_source.dart';
import 'package:reader_core/epub/epub_format_opener.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/paint/hit_test.dart';
import 'package:reader_core/paint/image_cache.dart';
import 'package:reader_core/paint/page_renderer.dart';
import 'package:reader_core/perf/trace.dart';
import 'package:reader_core/position/location_anchor.dart';
import 'package:reader_core/source/format_opener.dart';
import 'package:reader_ui/reader_session.dart';

const _enabled = bool.fromEnvironment('RUN_STRESS_BENCHMARK');
const _epub = String.fromEnvironment(
  'STRESS_EPUB',
  defaultValue: 'dist/performance-stress.epub',
);
const _reportPath = String.fromEnvironment(
  'STRESS_REPORT',
  defaultValue: 'dist/performance-stress-report.json',
);
const _bookId = '长章压力基准';
const _size = ui.Size(360, 600);
const _overrides = ReaderOverrides(fontSize: 18);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    '大型 EPUB 长章导航、重排和图片绘制压力基准',
    () async {
      expect(File(_epub).existsSync(), isTrue, reason: '请先运行压力书生成器');
      final benchmark = _StressBenchmark();
      try {
        await benchmark.run();
      } catch (error, stack) {
        benchmark.report['error'] = '$error';
        benchmark.report['stack'] = '$stack';
        rethrow;
      } finally {
        await benchmark.close();
        final output = File(_reportPath);
        await output.parent.create(recursive: true);
        await output.writeAsString(
          const JsonEncoder.withIndent('  ').convert(benchmark.report),
        );
        // ignore: avoid_print
        print('压力基准报告：${output.absolute.path}');
      }
    },
    skip: !_enabled,
    timeout: const Timeout(Duration(minutes: 10)),
  );
}

class _StressBenchmark {
  final report = <String, Object?>{
    'contract': '本地 Flutter 测试；360×600、18px；4ms事件循环探针，非真机帧率',
    'epub': File(_epub).absolute.path,
    'samples': <String, Object?>{},
  };
  EpubChapterSource? _source;
  ReaderSession? _session;
  DecodedImageCache? _images;
  final _store = MemoryReaderProgressStore();
  EpubChapterSource get source => _source!;
  ReaderSession get session => _session!;

  Future<void> run() async {
    report['fileBytes'] = await File(_epub).length();
    await _open();
    await measure('跳入长章', () => session.jumpToChapter(1));
    expect(session.error, isNull);
    expect(session.page?.spineIndex, 1);
    final pages = await session.chapterPages();
    expect(pages.length, greaterThanOrEqualTo(200));
    report['pageCount'] = pages.length;
    final anchor = await source.loadAnchorChapter(1);
    _checkContents(pages, anchor);
    final signature = _signatures(pages);
    final cfis = pages
        .map((page) => session.cfiAtPageOffset(page, null))
        .toList();
    expect(cfis, everyElement(isNotNull));
    report['pageSignature'] = _digest(signature);
    report['cfiSignature'] = _digest(cfis);
    await _warmJump(signature, cfis);
    await _anchorAndReflow(cfis[99]!, signature, anchor);
    await _decodeAndPaint(pages);
    await session.flushProgress();
    expect((await _store.load(_bookId))?.cfi, session.progress?.cfi);
    report['cache'] = source.cacheReport;
  }

  Future<void> _open() async {
    await measure('文件打开', () async {
      _source = await const EpubFormatOpener(verifyCrc: false).openFile(
        File(_epub),
        options: const ReaderOpenOptions(contentWidth: 360, contentHeight: 600),
      );
      source.bookIdForTrace = _bookId;
      expect(source.chapterCount, 2);
    });
    _session = ReaderSession(
      source: source,
      store: _store,
      bookId: _bookId,
      contentRevision: '生成的固定压力书',
    );
    await measure(
      '封面首屏',
      () => session.open(
        overrides: _overrides,
        contentWidth: 360,
        contentHeight: 600,
      ),
    );
    expect(session.error, isNull);
    expect(session.page?.spineIndex, 0);
  }

  Future<void> _warmJump(List<String> signature, List<String?> cfis) async {
    await session.jumpToChapter(0);
    await measure('热缓存跳入长章', () => session.jumpToChapter(1));
    final warmed = await session.chapterPages();
    expect(_signatures(warmed), signature, reason: '缓存返回后的每页内容与几何一致');
    expect(warmed.map((page) => session.cfiAtPageOffset(page, null)), cfis);
  }

  Future<void> _anchorAndReflow(
    String target,
    List<String> signature,
    AnchorChapter original,
  ) async {
    await measure('跳到第100页CFI', () => session.jumpToCfi(target));
    expect(session.page?.pageIndex, 99);
    expect(session.readingCfi, target);
    await measure(
      '字号18到20重排',
      () => session.applyOverrides(const ReaderOverrides(fontSize: 20)),
    );
    expect(session.error, isNull);
    expect(session.readingCfi, target, reason: '字号重排保留原文锚点');
    final reflowed = await session.chapterPages();
    _checkContents(reflowed, original);
    report['reflowPageCount'] = reflowed.length;
    await measure('恢复18字号', () => session.applyOverrides(_overrides));
    expect(session.readingCfi, target);
    expect(_signatures(await session.chapterPages()), signature);
  }

  void _checkContents(List<PageContent> pages, AnchorChapter original) {
    final visible = _normalize(
      pages.expand(TextHitTester.lineBoxes).map((line) => line.text).join(),
    );
    final tables = _normalize(
      pages.expand(_pageTables).map((cell) => cell.text).join(),
    );
    final markers = RegExp(r'第\s*(\d+)\s*节正文').allMatches(original.text);
    final numbers = markers.map((match) => int.parse(match[1]!)).toList();
    expect(numbers, isNotEmpty);
    expect(numbers, List.generate(numbers.length, (index) => index + 1));
    for (final number in numbers) {
      final label = number.toString().padLeft(3, '0');
      _expectContains(visible, '第$label节：山间阅读札记');
      _expectContains(visible, '第$label次行程');
      _expectContains(visible, '第$label节正文');
    }
    for (final block in original.blocks) {
      final expected = _normalize(block.text);
      if (expected.isNotEmpty) {
        expect(
          visible.contains(expected) || tables.contains(expected),
          isTrue,
          reason: '缺少原文：${expected.substring(0, expected.length.clamp(0, 80))}',
        );
      }
    }
    report['sectionsVerified'] = numbers.length;
  }

  Future<void> _decodeAndPaint(List<PageContent> pages) async {
    _images = DecodedImageCache(loadBytes: source.readImageBytes);
    final urls = source.document.package.manifest
        .where((item) => item.mediaType.startsWith('image/'))
        .map(
          (item) => path.posix.normalize(
            path.posix.join(
              path.posix.dirname(source.document.opfPath),
              item.href,
            ),
          ),
        )
        .toList();
    expect(urls.length, greaterThanOrEqualTo(40));
    await measure('全部图片实际解码', () async {
      for (final url in urls) {
        expect(
          await _images!.load(url, displayWidth: 112, devicePixelRatio: 3),
          isNotNull,
          reason: url,
        );
      }
    });
    report['decodedImages'] = urls.length;
    var paintedImages = 0;
    await measure('代表页绘制', () async {
      for (final index in [0, 99, pages.length - 1]) {
        paintedImages += await _paintPage(pages[index], _images!);
      }
    });
    expect(paintedImages, greaterThan(0), reason: '绘制器实际取用了已解码图片');
    report['paintedImageLookups'] = paintedImages;
  }

  Future<T> measure<T>(String name, Future<T> Function() action) async {
    final watch = Stopwatch()..start();
    final gaps = <int>[];
    var prior = 0;
    var peakRss = ProcessInfo.currentRss;
    void sample() {
      final now = watch.elapsedMicroseconds;
      gaps.add(now - prior);
      prior = now;
      final rss = ProcessInfo.currentRss;
      if (rss > peakRss) peakRss = rss;
    }

    ReaderTrace.instance.reset();
    final timer = Timer.periodic(
      const Duration(milliseconds: 4),
      (_) => sample(),
    );
    try {
      return await action();
    } finally {
      sample();
      timer.cancel();
      watch.stop();
      gaps.sort();
      (report['samples']! as Map<String, Object?>)[name] = {
        'elapsedMs': watch.elapsedMicroseconds / 1000,
        'uiGapMaxMs': gaps.last / 1000,
        'uiGapP95Ms': gaps[((gaps.length - 1) * .95).round()] / 1000,
        'uiGapSamples': gaps.length,
        'rssBytes': ProcessInfo.currentRss,
        'sampledPeakRssBytes': peakRss,
        'processMaxRssBytes': ProcessInfo.maxRss,
        'trace': _trace(),
      };
    }
  }

  Future<void> close() async {
    await _session?.flushProgress();
    _session?.dispose();
    _images?.clear();
    _source?.close();
    await _source?.preparationsStopped;
  }
}

Map<String, Object?> _trace() => {
  for (final scope in <String?>[null, _bookId])
    scope ?? '未指定书籍': {
      for (final name in ReaderTraceName.values)
        if ((ReaderTrace.instance.summary(bookId: scope).counts[name] ?? 0) > 0)
          name.name: {
            'count': ReaderTrace.instance.summary(bookId: scope).counts[name],
            'maxMs': ReaderTrace.instance.summary(bookId: scope).maxMs(name),
            'averageMs': ReaderTrace.instance
                .summary(bookId: scope)
                .averageMs(name),
            'p95Ms': ReaderTrace.instance.summary(bookId: scope).p95Ms(name),
          },
    },
};

void _expectContains(String visible, String expected) => expect(
  visible.contains(expected),
  isTrue,
  reason: '缺少原文：${expected.substring(0, expected.length.clamp(0, 80))}',
);

String _normalize(String text) => text.replaceAll(RegExp(r'\s|\uFFFC'), '');
String _digest(Object value) =>
    sha256.convert(utf8.encode(jsonEncode(value))).toString();

List<String> _signatures(List<PageContent> pages) => [
  for (final page in pages)
    _digest([
      page.pageIndex,
      page.usedHeight,
      for (final line in TextHitTester.lineBoxes(page))
        [
          line.text,
          line.rect.left,
          line.rect.top,
          line.rect.width,
          line.rect.height,
        ],
      for (final cell in _pageTables(page)) [cell.text, cell.geometry],
    ]),
];

typedef _TableText = ({String text, List<Object?> geometry});

Iterable<_TableText> _pageTables(PageContent page) sync* {
  for (final slice in page.slices) {
    for (final cell in _blockTables(
      slice.block,
      slice.startLine,
      slice.endLine,
    )) {
      yield (
        text: cell.text,
        geometry: [
          slice.leftInset,
          slice.absoluteTop,
          slice.height,
          slice.startLine,
          slice.endLine,
          ...cell.geometry,
        ],
      );
    }
  }
}

Iterable<_TableText> _blockTables(PageBlock block, int start, int end) sync* {
  // 正式分页器已按本页行区间切分 cells；不能从原始整表重新取文本。
  final table = block.table;
  if (table != null) {
    for (final cell in table.cells) {
      final layout = cell.layout;
      yield (
        text: layout.lines
            .map((line) => layout.text.substring(line.start, line.end))
            .join(),
        geometry: [
          cell.row,
          cell.rect.left,
          cell.rect.top,
          cell.rect.width,
          cell.rect.height,
          for (final line in layout.lines)
            [
              line.start,
              line.end,
              line.top,
              line.offsetX,
              line.width,
              line.height,
            ],
        ],
      );
      yield* _inlineTables(layout, 0, layout.lineCount);
    }
  }
  yield* _inlineTables(block.layout, start, end);
}

Iterable<_TableText> _inlineTables(
  TextLayoutResult layout,
  int start,
  int end,
) sync* {
  for (final line in layout.lines.skip(start).take(end - start)) {
    for (final placement in line.inlineBoxes) {
      final payload = placement.spec.payload;
      if (payload is PageBlock) {
        yield* _blockTables(payload, 0, payload.layout.lineCount);
      }
    }
  }
}

Future<int> _paintPage(PageContent page, DecodedImageCache cache) async {
  final urls = <String>{};
  final probe = ui.PictureRecorder();
  PagePainter(
    imageLookup: (url) {
      urls.add(url);
      return null;
    },
  ).paint(ui.Canvas(probe), page, pageSize: _size);
  probe.endRecording().dispose();
  for (final url in urls) {
    expect(
      await cache.load(url, displayWidth: 112, devicePixelRatio: 3),
      isNotNull,
    );
  }
  var imageLookups = 0;
  final recorder = ui.PictureRecorder();
  PagePainter(
    imageLookup: (url) {
      final image = cache.lookup(url);
      if (image != null) imageLookups++;
      return image;
    },
  ).paint(ui.Canvas(recorder), page, pageSize: _size);
  final picture = recorder.endRecording();
  final image = await picture.toImage(360, 600);
  try {
    final pixels = await image.toByteData();
    expect(pixels, isNotNull);
    expect(pixels!.buffer.asUint8List().any((value) => value < 240), isTrue);
  } finally {
    image.dispose();
    picture.dispose();
  }
  return imageLookups;
}
