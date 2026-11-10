import 'dart:async';
import 'dart:convert';
import 'dart:developer' show Timeline;
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_mobile/home/bookshelf_page.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/reader/epub_chapter_source.dart';
import 'package:reader_mobile/reader/epub_reader_page.dart';
import 'package:reader_mobile/storage/db.dart';
import 'package:reader_mobile/storage/drift_progress_store.dart';
import 'package:reader_ui/a11y/semantics_layer.dart';
import 'package:reader_ui/menu/reader_menu_overlay.dart';
import 'package:reader_ui/panels/toc_panel.dart';
import 'package:reader_ui/reader_page.dart';
import 'package:reader_ui/reader_session.dart';
import 'package:reader_ui/reader_view.dart';
import 'package:reader_mobile/reader/reader_settings.dart';

import 'reader_perf_probe.dart';

/// 只由 device_reader_perf.py 在独立包运行；计时包含真实书架读盘和正文帧。
const _server = String.fromEnvironment('PERF_SERVER');
const _bookId = 'perf-book';
const _rounds = int.fromEnvironment('PERF_ROUNDS', defaultValue: 5);
const _targetSpine = int.fromEnvironment('PERF_SPINE', defaultValue: 29);
final _fontSize = double.parse(
  const String.fromEnvironment('PERF_FONT_SIZE', defaultValue: '21'),
);
const _measureResizing = bool.fromEnvironment('PERF_RESIZE');
const _title = String.fromEnvironment('PERF_TITLE', defaultValue: '诸神愚戏');
final _uiProbe = _UiProbe();
final _navigator = GlobalKey<NavigatorState>();
final _results = <String, Object?>{};

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _results['start'] = _memory();
  _results['process'] = {
    'pid': pid,
    'measurement_started_at_utc': DateTime.now().toUtc().toIso8601String(),
    'rounds': _rounds,
  };
  _results['measurement_contract'] = {
    'schema': 3,
    'opening': '原书已预读；首轮为进程内初开，后续为同进程重开',
    'resizing': '首轮请求进程内首次使用的字号；后续轮可能命中跨来源缓存，不能作为新字号冷排样本',
    'fresh_gate': '前后各启动五次独立进程，每次rounds=1；分别统计首次新字号和恢复原字号',
    'complete': '正文及图片就绪、淡入结束后的Flutter帧；不代表系统呈现时间',
    'ui_gap': '4ms定时器回调最大间隔，包含结束时尚未回调的间隔',
    'frames': '按原始buildStart时间归属事件；最终报告标记尾帧是否收齐',
  };
  runApp(const MaterialApp(home: Scaffold(body: Text('准备真机性能测试'))));
  try {
    final root = await getApplicationSupportDirectory();
    final file = await _download(root);
    if (const bool.fromEnvironment('PERF_IMPORT')) {
      await _measureImport(root, file);
    }
    // 每次运行用全新库：覆盖安装会保留上一轮的书架、进度与内容锚点，
    // 阅读器恢复到的位置就不再是本次写入的第 29 章，多轮测量会整体失效。
    final db = AppDatabase(
      NativeDatabase(
        File(
          '${root.path}/perf-${DateTime.now().microsecondsSinceEpoch}.sqlite',
        ),
      ),
    );
    await _seedBook(db, file);
    final progress = DriftProgressStore(db);
    final library = LibraryStore(
      database: db,
      directoryProvider: () async => root,
    );
    await library.setSetting('bookshelf.grid', 'false');
    await ReaderSettingsStore(library)
        .save(ReaderSettings(fontSize: _fontSize));
    runApp(
      MaterialApp(
        navigatorKey: _navigator,
        home: BookshelfPage(library: library, progressStore: progress),
      ),
    );
    for (var round = 0; round < _rounds; round++) {
      await _openRound(progress, round);
      if (round == _rounds - 1 &&
          const bool.fromEnvironment('PERF_LONG_SCAN')) {
        await _scanLongBook();
      }
      // 非字号测试首轮最后跳到第 32 章，其他轮次停在目标章。旧阅读页的进度落盘
      // 是异步的，必须等它真正写入后再清进度，否则下一轮会被旧位置覆盖。
      final closingSpine = !_measureResizing && round == 0 ? 32 : _targetSpine;
      _navigator.currentState!.pop();
      await _until(() => _find<ReaderPage>((_) => true) == null);
      await _untilProgress(progress, closingSpine);
    }
    if (const bool.fromEnvironment('PERF_LONG_SCAN')) {
      _results['after_close'] = _memory();
    }
    await _uiProbe.drain();
    await _send('done', _results);
  } catch (error, stack) {
    await _send('done', {..._results, 'error': '$error', 'stack': '$stack'});
  } finally {
    _uiProbe.close();
  }
}

Future<void> _measureImport(Directory root, File original) async {
  final directory = await root.createTemp('import-perf-');
  final db = AppDatabase(
    NativeDatabase(File('${directory.path}/import.sqlite')),
  );
  try {
    final library = LibraryStore(
      database: db,
      directoryProvider: () async => directory,
    );
    final stages = <String, int>{};
    final watch = Stopwatch()..start();
    // 走生产默认入口：文件流式导入，不整本读入内存。
    final entry = await library.importFile(
      original.path,
      onProgress: (progress) {
        if (progress == 0.1) stages['started_ms'] = watch.elapsedMilliseconds;
        if (progress == 0.45) stages['verified_ms'] = watch.elapsedMilliseconds;
        if (progress == 0.85) stages['written_ms'] = watch.elapsedMilliseconds;
        if (progress == 0.95) stages['counted_ms'] = watch.elapsedMilliseconds;
      },
    );
    final weights = await library.progressWeights(entry.id);
    _results['import'] = {
      ...stages,
      'complete_ms': watch.elapsedMilliseconds,
      'chapters': entry.spineCount,
      'characters': weights.totalCharacters,
      ..._memory(),
    };
    await _send('sample', _results);
  } finally {
    await db.close();
    await directory.delete(recursive: true);
  }
}

Future<File> _download(Directory root) async {
  final file = File('${root.path}/perf.epub');
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse('$_server/book.epub'));
    final response = await request.close();
    if (response.statusCode != 200) throw StateError('原书下载失败');
    await response.pipe(file.openWrite());
    return file;
  } finally {
    client.close();
  }
}

Future<void> _seedBook(AppDatabase db, File file) async {
  // 测试准备使用固定书架记录；正文读取仍走生产惰性文件路径。
  final revision = (await sha256.bind(file.openRead()).first).toString();
  await db
      .into(db.books)
      .insertOnConflictUpdate(
        BooksCompanion.insert(
          id: const Value(1),
          uuid: _bookId,
          title: _title,
          contentDir: file.parent.path,
          sourcePath: Value(file.path),
          contentRevision: Value(revision),
          spineCount: Value(await _chapterCount(file)),
          createdAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );
}

Future<void> _untilProgress(DriftProgressStore progress, int spine) async {
  final watch = Stopwatch()..start();
  while (watch.elapsed < const Duration(seconds: 10)) {
    final saved = await progress.load(_bookId);
    if (saved?.spineIndex == spine) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  throw TimeoutException('等待阅读进度落盘到第 $spine 章超时；现场 $_scene');
}

Future<void> _openRound(DriftProgressStore progress, int round) async {
  // 每轮都从目标章开。存储层在 cfi 为空且已有内容锚点时会保留旧位置
  // （书架标"读完"不得清掉锚点），所以先清进度再写入，并读回确认。
  await progress.clear(_bookId);
  const target = ReaderProgress(spineIndex: _targetSpine, pageIndex: 0);
  await progress.save(_bookId, target);
  final restored = await progress.load(_bookId);
  if (restored?.spineIndex != _targetSpine) {
    throw StateError('第 $round 轮写入目标章失败，当前 ${restored?.spineIndex}');
  }
  await _until(() => _bookTile() != null);
  _uiProbe.start();
  final watch = Stopwatch()..start();
  await openPerfReader(
    isMounted: isPerfReaderMounted,
    tap: () => _bookTile()?.onTap?.call(),
  );
  final sample = await _sample(watch, _targetSpine);
  sample['cache_temperature'] = round == 0 ? '预读文件后的进程内初开' : '同进程重开';
  _results['open_$round'] = sample;
  await _send('sample', _results);
  if (_measureResizing) {
    await _resizeRound(round);
    return;
  }
  if (round != 0) return;
  for (final spine in [
    30,
    47,
    if (const bool.fromEnvironment('PERF_FAR_JUMP', defaultValue: true)) 1515,
    29,
    32,
  ]) {
    await _jump(spine);
  }
}

/// 路由挂载先于章节准备；正文仍交给原有就绪等待，兼容基线的慢扫描。
bool isPerfReaderMounted() => _find<EpubReaderPage>((_) => true) != null;

/// 保留防重入期间的点击重试；挂载检测不等待下一个250ms重试时刻。
Future<void> openPerfReader({
  required bool Function() isMounted,
  required VoidCallback tap,
}) async {
  if (isMounted()) return;
  var expired = false;
  final deadline = Timer(const Duration(seconds: 5), () => expired = true);
  final retry = Timer.periodic(const Duration(milliseconds: 250), (_) {
    if (!expired && !isMounted()) tap();
  });
  try {
    tap();
    while (!isMounted()) {
      if (expired) throw TimeoutException('等待阅读页挂载超时');
      await Future<void>.delayed(const Duration(milliseconds: 8));
    }
  } finally {
    deadline.cancel();
    retry.cancel();
  }
}

Future<int> _chapterCount(File file) async {
  final source = await EpubChapterSource.openFile(file, verifyCrc: false);
  try {
    return source.chapterCount;
  } finally {
    source.close();
  }
}

Future<void> _resizeRound(int round) async {
  for (final size in [_fontSize + 1, _fontSize]) {
    final reader = _find<ReaderPage>((_) => true)!;
    final previous = _find<ReaderSemanticsLayer>((_) => true)!.page;
    _uiProbe.start();
    final watch = Stopwatch()..start();
    reader.onOverridesChanged!(reader.overrides!.copyWith(fontSize: size));
    await _until(() {
      final source = _find<ReaderPage>((_) => true)?.source;
      return isRequestedFontPage(
        current: _find<ReaderSemanticsLayer>((_) => true)?.page,
        previous: previous,
        requestedSize: size,
        appliedSize: source is EpubChapterSource
            ? source.overrides.fontSize
            : null,
      );
    });
    final sample = await _sample(watch, _targetSpine);
    sample['cache_temperature'] = size == _fontSize
        ? '恢复原字号'
        : round == 0
        ? '进程内首次请求新字号'
        : '同进程再次请求该字号，可能命中跨来源缓存';
    _results['resize_${round}_$size'] = sample;
    await _send('sample', _results);
  }
}

/// 字号验收仅适用含正文的页面；空页、旧页和仅更新设置均不算排版完成。
bool isRequestedFontPage({
  required PageContent? current,
  required PageContent previous,
  required double requestedSize,
  required double? appliedSize,
}) =>
    current != null &&
    !identical(previous, current) &&
    current.spineIndex == previous.spineIndex &&
    appliedSize == requestedSize &&
    current.slices.any(
      (slice) =>
          slice.block.layout.text.isNotEmpty &&
          slice.block.style?.fontSize == requestedSize,
    );

/// 事件循环间隔与真实帧耗时分别记录；同设备前后使用同一探针。
class _UiProbe {
  Timer? _timer;
  final Stopwatch _watch = Stopwatch();
  final _samples = ReaderPerfProbeSamples();
  bool _listening = false;

  void start() {
    _timer?.cancel();
    if (!_listening) {
      WidgetsBinding.instance.addTimingsCallback(_samples.addFrames);
      _listening = true;
    }
    _samples.start(Timeline.now);
    _watch
      ..reset()
      ..start();
    _timer = Timer.periodic(const Duration(milliseconds: 4), (_) {
      _samples.tick(_watch.elapsedMicroseconds);
    });
  }

  Map<String, Object> finish() {
    _timer?.cancel();
    _watch.stop();
    return _samples.finish(
      elapsedMicros: _watch.elapsedMicroseconds,
      rawFrameTimestampMicros: Timeline.now,
    );
  }

  Future<void> drain() async {
    // Release帧批次通常每秒交付；等待不计入任何操作耗时。
    final watch = Stopwatch()..start();
    while (!_samples.complete && watch.elapsed < const Duration(seconds: 3)) {
      await WidgetsBinding.instance.endOfFrame;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  void close() {
    _timer?.cancel();
    if (_listening) {
      WidgetsBinding.instance.removeTimingsCallback(_samples.addFrames);
      _listening = false;
    }
  }
}

// 书架条目的点击目标是 InkWell，按公开 key 定位：列表模式 'book-row-<uuid>'、
// 网格模式 'book-card-<uuid>'；BookEntry.id 用 uuid，不是整数主键。
InkWell? _bookTile() => _find<InkWell>(
  (widget) =>
      widget.key == const ValueKey<String>('book-row-$_bookId') ||
      widget.key == const ValueKey<String>('book-card-$_bookId'),
);

Future<void> _jump(int spine) async {
  if (_find<ReaderMenuOverlay>((w) => w.open) == null) {
    _find<ReaderView>((_) => true)!.onToggleToolbar!();
  }
  await _until(() => _find<ReaderMenuOverlay>((w) => w.open) != null);
  final menu = _find<ReaderMenuOverlay>((_) => true)!;
  menu.onEntry(ReaderMenuEntry.toc);
  await _until(() => _find<TocPanel>((_) => true) != null);
  final toc = _find<TocPanel>((_) => true)!;
  final entry = flattenToc(toc.entries)
      .firstWhere((r) => r.entry.spineIndex == spine)
      .entry;
  _uiProbe.start();
  final watch = Stopwatch()..start();
  toc.onSelect(entry);
  _results['jump_$spine'] = await _sample(watch, spine);
  await _send('sample', _results);
}

Future<Map<String, Object>> _sample(Stopwatch watch, int spine) async {
  await _readable(spine);
  final textMs = watch.elapsedMilliseconds;
  await _imagesReady();
  final imagesMs = watch.elapsedMilliseconds;
  // 首帧可能仍处于 AnimatedSwitcher 淡入，另记录完全显示后的时间。
  await _until(() => isPerfPageFullyVisible(spine));
  await WidgetsBinding.instance.endOfFrame;
  final source = _find<ReaderPage>((_) => true)?.source;
  final sample = _uiProbe.finish();
  sample.addAll({
    'text_ms': textMs,
    'images_ms': imagesMs,
    'complete_ms': watch.elapsedMilliseconds,
    'spine': spine,
    ..._memory(),
    'environment': _sampleEnvironment(),
    if (source is EpubChapterSource) 'cache': source.cacheReport,
  });
  return sample;
}

Map<String, Object?> _sampleEnvironment() {
  final element = _findElement((widget) => widget is ReaderSemanticsLayer)!;
  final layer = element.widget as ReaderSemanticsLayer;
  final media = MediaQuery.of(element);
  final reader = _find<ReaderPage>((_) => true)!;
  final source = reader.source;
  return {
    'viewport': [media.size.width, media.size.height],
    'dpr': media.devicePixelRatio,
    'text_scale_at_21': media.textScaler.scale(21),
    'page_width': layer.pageWidth,
    'requested_font_size': reader.overrides?.fontSize,
    'requested_font_family': reader.overrides?.fontFamily,
    'source_font_size': source is EpubChapterSource
        ? source.overrides.fontSize
        : null,
    'visible_font_families': {
      for (final slice in layer.page.slices)
        ...?slice.block.style?.fontFamilies,
    }.toList()..sort(),
  };
}

Future<void> _scanLongBook() async {
  final source = _find<ReaderPage>((_) => true)?.source;
  if (source is! EpubChapterSource) {
    throw StateError('长书扫描未取得 EpubChapterSource');
  }
  final started = ProcessInfo.currentRss;
  var peakRss = started;
  final startedPss = _pssBytes();
  var peakPss = startedPss;
  final samples = <Map<String, Object>>[];
  final peaks = <Map<String, Object>>[];
  var peakChapterPss = 0;
  var peakChapterSpine = 0;
  final count = source.chapterCount;
  for (var spine = 0; spine < count; spine += 10) {
    final watch = Stopwatch()..start();
    final pages = await source.loadChapter(spine);
    await WidgetsBinding.instance.endOfFrame;
    final rss = ProcessInfo.currentRss;
    if (rss > peakRss) peakRss = rss;
    final pss = _pssBytes();
    if (pss > peakPss) peakPss = pss;
    if (pss > peakChapterPss) {
      peakChapterPss = pss;
      peakChapterSpine = spine;
    }
    peaks.add({
      'spine': spine,
      'load_ms': watch.elapsedMilliseconds,
      'pages': pages.length,
      'pss_bytes': pss,
    });
    if (spine == 0 || spine % 100 == 0 || spine + 10 >= count) {
      samples.add({
        'spine': spine,
        'load_ms': watch.elapsedMilliseconds,
        'pages': pages.length,
        'rss_bytes': rss,
        'pss_bytes': pss,
        'cache': source.cacheReport,
      });
    }
  }
  _results['long_scan'] = {
    'chapters': count,
    'stride': 10,
    'start_rss_bytes': started,
    'peak_rss_bytes': peakRss,
    'end_rss_bytes': ProcessInfo.currentRss,
    'start_pss_bytes': startedPss,
    'peak_pss_bytes': peakPss,
    'end_pss_bytes': _pssBytes(),
    'peak_chapter_spine': peakChapterSpine,
    'peak_chapter_pss_bytes': peakChapterPss,
    'chapter_samples': peaks,
    'samples': samples,
  };
  await _send('sample', _results);
}

/// 进程内存：RSS + Android 口径的 PSS（`/proc/self/smaps_rollup`）。
///
/// PSS 是 Android 设置与 `ActivityManager` 使用的口径；GPU/EGL 不计入
/// 这里，由宿主脚本的 `dumpsys meminfo` 另行核对。
Map<String, Object> _memory() => {
  'rss_bytes': ProcessInfo.currentRss,
  'pss_bytes': _pssBytes(),
  'hwm_bytes': _hwmBytes(),
};

int _pssBytes() {
  try {
    for (final line in File('/proc/self/smaps_rollup').readAsLinesSync()) {
      if (line.startsWith('Pss:')) return _kbOf(line);
    }
  } catch (_) {
    // 内核未开放 smaps_rollup 时只保留 RSS。
  }
  return 0;
}

int _hwmBytes() {
  try {
    for (final line in File('/proc/self/status').readAsLinesSync()) {
      if (line.startsWith('VmHWM:')) return _kbOf(line);
    }
  } catch (_) {
    // 同上。
  }
  return 0;
}

int _kbOf(String line) {
  final match = RegExp(r'(\d+)').firstMatch(line);
  return match == null ? 0 : (int.tryParse(match.group(1)!) ?? 0) * 1024;
}

/// 封面准备期正文已挂载但语义被排除，不能提前算作完整显示。
bool isPerfPageFullyVisible(int spine) {
  final element = _findElement(
    (widget) =>
        widget is ReaderSemanticsLayer && widget.page.spineIndex == spine,
  );
  if (element == null) return false;
  var visible = true;
  element.visitAncestorElements((ancestor) {
    final widget = ancestor.widget;
    if (widget is FadeTransition && widget.opacity.value < 1) visible = false;
    if (widget is ExcludeSemantics && widget.excluding) visible = false;
    if (widget is Offstage && widget.offstage) visible = false;
    return visible;
  });
  return visible;
}

Future<void> _readable(int spine) async {
  try {
    await _until(
      () =>
          _find<ReaderSemanticsLayer>(
            (w) => w.page.spineIndex == spine && w.page.slices.isNotEmpty,
          ) !=
          null,
    );
  } on TimeoutException {
    // 超时是引擎/排版回归的主要信号；附带现场状态，避免只能靠截图猜。
    throw TimeoutException('等待第 $spine 章正文超时；现场 $_scene');
  }
  // 确认目标正文已完成一帧，计时不止于 parse 或 session 状态变化。
  await WidgetsBinding.instance.endOfFrame;
}

Future<void> _imagesReady() async {
  final reader = _find<ReaderPage>((_) => true)!;
  final page = _find<ReaderSemanticsLayer>((_) => true)!.page;
  final urls = <String>{
    if (page.background?.imageUrl case final String url) url,
    for (final slice in page.slices) ...[
      if (slice.block.style?.backgroundImage != null)
        slice.block.style!.backgroundImage!,
      for (final image in slice.block.inlineImages) image.url,
      for (final fragment in slice.block.containers)
        if (fragment.container.style.backgroundImage != null)
          fragment.container.style.backgroundImage!,
    ],
  };
  await _until(
    () => urls.every((url) => reader.imageCache?.lookup(url) != null),
  );
  await WidgetsBinding.instance.endOfFrame;
}

T? _find<T extends Widget>(bool Function(T) predicate) {
  return _findElement((widget) => widget is T && predicate(widget))?.widget
      as T?;
}

/// 失败现场：已挂载的语义页章节与切片数，区分"没打开"与"排版为空"。
String get _scene {
  final pages = <ReaderSemanticsLayer>[];
  _visit((widget) {
    if (widget is ReaderSemanticsLayer) pages.add(widget);
  });
  final mounted = pages
      .map((w) => '#${w.page.spineIndex}:${w.page.slices.length}')
      .join(',');
  final reader = _find<ReaderPage>((_) => true) != null;
  return '阅读页=$reader 语义页=[$mounted]';
}

void _visit(void Function(Widget) onWidget) {
  void visit(Element element) {
    onWidget(element.widget);
    element.visitChildren(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildren(visit);
}

Element? _findElement(bool Function(Widget) predicate) {
  Element? result;
  void visit(Element element) {
    if (predicate(element.widget)) result = element;
    element.visitChildren(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildren(visit);
  return result;
}

Future<void> _until(bool Function() condition) async {
  final watch = Stopwatch()..start();
  while (!condition()) {
    if (watch.elapsed > const Duration(minutes: 5)) {
      throw TimeoutException('等待正文超时');
    }
    await Future<void>.delayed(const Duration(milliseconds: 8));
  }
}

Future<void> _send(String kind, Map<String, Object?> data) async {
  final client = HttpClient();
  try {
    final request = await client.postUrl(Uri.parse('$_server/$kind'));
    request.headers.contentType = ContentType.json;
    final bytes = utf8.encode(jsonEncode(data));
    request.contentLength = bytes.length;
    request.add(bytes);
    final response = await request.close();
    if (response.statusCode != 204) throw StateError('性能报告保存失败');
    await response.drain<void>();
  } finally {
    client.close();
  }
}
