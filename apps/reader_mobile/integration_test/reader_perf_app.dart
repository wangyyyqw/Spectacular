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
import 'package:reader_core/perf/trace.dart';
import 'package:reader_mobile/home/bookshelf_page.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_core/epub/epub_chapter_source.dart';
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
import '../test/reader/support/layout_snapshot.dart';

import 'package:reader_core/source/toc.dart';

/// 只由 device_reader_perf.py 在独立包运行；计时包含真实书架读盘和正文帧。
const _server = String.fromEnvironment('PERF_SERVER');
String _bookId = 'perf-book';
const _rounds = int.fromEnvironment('PERF_ROUNDS', defaultValue: 5);
int _targetSpine = const int.fromEnvironment('PERF_SPINE', defaultValue: 29);
final _fontSize = double.parse(
  const String.fromEnvironment('PERF_FONT_SIZE', defaultValue: '21'),
);
const _measureResizing = bool.fromEnvironment('PERF_RESIZE');
const _measureFullChapter = bool.fromEnvironment('PERF_FULL_CHAPTER');
const _title = String.fromEnvironment('PERF_TITLE', defaultValue: '诸神愚戏');
final _uiProbe = _UiProbe();
final _navigator = GlobalKey<NavigatorState>();
final _results = <String, Object?>{};
const _openingOnly = bool.fromEnvironment('PERF_OPENING_ONLY');
const _hasScenario = bool.fromEnvironment('PERF_SCENARIO');
Map<String, Object?>? _scenario;
Map<String, Object?> _run = const {};
DateTime _traceStarted = DateTime.now();
String? _targetCfi;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _results['start'] = _memory();
  _results['process'] = {
    'pid': pid,
    'measurement_started_at_utc': DateTime.now().toUtc().toIso8601String(),
    'rounds': _rounds,
  };
  _results['measurement_contract'] = {
    'schema': 5,
    'opening': '原书已预读；首轮为进程内初开，后续为同进程重开',
    'resizing': '首轮请求进程内首次使用的字号；后续轮可能命中跨来源缓存，不能作为新字号冷排样本',
    'fresh_gate': '独立进程由宿主指定，每进程一个开书样本；暖页界预热进程不计样本',
    'complete': '正文及图片就绪、淡入结束后的Flutter帧；不代表系统呈现时间',
    'chapter': _measureFullChapter
        ? '页界缓存作用域由 run.cache_mode 指定；额外等待整章完成，内容、CFI及行几何签名在计时结束后计算'
        : '只等待首屏完整显示',
    'ui_gap': '4ms定时器回调最大间隔，包含结束时尚未回调的间隔',
    'frames': '按原始buildStart时间归属事件；最终报告标记尾帧是否收齐',
  };
  runApp(const MaterialApp(home: Scaffold(body: Text('准备真机性能测试'))));
  try {
    final root = await getApplicationSupportDirectory();
    _run = await _getJson('/run.json');
    if (_hasScenario) {
      _scenario = await _getJson('/scenario/scenario.json');
      final book = (_scenario!['book'] as Map).cast<String, Object?>();
      _bookId = book['uuid'] as String;
      final progress =
          ((_scenario!['tables'] as Map)['reading_progress'] as List).single
              as Map;
      _targetSpine = progress['spine_index'] as int;
      _targetCfi = progress['locator_cfi'] as String;
    }
    _results['run'] = _run;
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
    if (_scenario != null) {
      await _seedScenario(db, root, file);
    } else {
      await _seedBook(db, file);
    }
    final progress = DriftProgressStore(db);
    final library = LibraryStore(
      database: db,
      directoryProvider: () async => root,
    );
    await library.setSetting('bookshelf.grid', 'false');
    if (_scenario == null) {
      await ReaderSettingsStore(library)
          .save(ReaderSettings(fontSize: _fontSize));
    }
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
      final closingSpine = !_openingOnly && !_measureResizing && round == 0
          ? 32
          : _targetSpine;
      final closingSource = _find<ReaderPage>((_) => true)?.source;
      if (closingSource is EpubChapterSource) {
        await closingSource.cacheWritesStopped;
      }
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

/// 测量前只向隔离数据库恢复场景，实际字体注册与规则匹配仍走阅读页。
Future<void> _seedScenario(AppDatabase db, Directory root, File file) async {
  final scenario = _scenario!;
  final book = (scenario['book'] as Map).cast<String, Object?>();
  final originalRevision = book['content_revision'] as String;
  final digest = (await sha256.bind(file.openRead()).first).toString();
  if (digest != originalRevision) throw StateError('复现场景与 EPUB 内容摘要不同');
  final revision = _cacheRevision(digest);
  final replacements = <String, String>{originalRevision: revision};
  for (final value in scenario['files'] as List) {
    final resource = (value as Map).cast<String, Object?>();
    final target = resource['target'] as String;
    final path = resource['path'] as String;
    if (target.startsWith('/') ||
        target.split('/').contains('..') ||
        path.startsWith('/') ||
        path.split('/').contains('..')) {
      throw const FormatException('复现场景资源必须使用相对路径');
    }
    final local = File('${root.path}/$target');
    final expected = resource['sha256'] as String?;
    final matches =
        expected != null &&
        await local.exists() &&
        (await sha256.bind(local.openRead()).first).toString() == expected;
    if (!matches) await _downloadTo('/scenario/$path', local);
    if (expected != null &&
        (await sha256.bind(local.openRead()).first).toString() != expected) {
      throw StateError('复现场景资源摘要不同：$path');
    }
    replacements[resource['source_path'] as String] = local.path;
  }
  final tables = (scenario['tables'] as Map).cast<String, Object?>();
  await db.transaction(() async {
    await _insertRows(db, 'books', [
      {
        ...book,
        'source_path': file.path,
        'content_dir': file.parent.path,
        'cover_path': replacements[book['cover_path']],
        'content_revision': originalRevision,
      },
    ], replacements);
    for (final table in const [
      'settings',
      'user_fonts',
      'spine_items',
      'decoration_rule_groups',
      'decoration_rules',
      'decorations',
      'annotations',
      'reading_progress',
    ]) {
      await _insertRows(
        db,
        table,
        tables[table] as List? ?? const [],
        replacements,
      );
    }
  });
  _results['pagination_scope'] = {
    'book_sha256': digest,
    'content_revision': revision,
    'isolated_per_process': _run['cache_mode'] != 'warm',
  };
}

String _cacheRevision(String revision) {
  if (!_openingOnly && !_measureFullChapter) return revision;
  final scope = _run['scope'] ?? 'legacy';
  final suffix = _run['cache_mode'] == 'warm'
      ? scope
      : '$scope:$pid:${DateTime.now().microsecondsSinceEpoch}';
  return '$revision:perf:$suffix';
}

Future<void> _insertRows(
  AppDatabase db,
  String table,
  List<Object?> rows,
  Map<String, String> replacements,
) async {
  final namePattern = RegExp(r'^[a-z][a-z0-9_]*$');
  for (final value in rows) {
    final row = (value as Map).cast<String, Object?>();
    if (!row.keys.every(namePattern.hasMatch)) {
      throw const FormatException('复现场景包含非法字段名');
    }
    final columns = row.keys.map((key) => '"$key"').join(',');
    final values = row.values.map((value) {
      if (value is! String) return value;
      var text = value;
      for (final replacement in replacements.entries) {
        text = text.replaceAll(replacement.key, replacement.value);
      }
      return text;
    }).toList();
    await db.customStatement(
      'INSERT OR REPLACE INTO "$table" ($columns) VALUES (${List.filled(values.length, '?').join(',')})',
      values,
    );
  }
}

Future<Map<String, Object?>> _getJson(String endpoint) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse('$_server$endpoint'));
    final response = await request.close();
    if (response.statusCode != 200) throw StateError('读取复现场景失败：$endpoint');
    return (jsonDecode(await utf8.decodeStream(response)) as Map)
        .cast<String, Object?>();
  } finally {
    client.close();
  }
}

Future<void> _downloadTo(String endpoint, File file) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse('$_server$endpoint'));
    final response = await request.close();
    if (response.statusCode != 200) throw StateError('下载复现资源失败：$endpoint');
    await file.parent.create(recursive: true);
    await response.pipe(file.openWrite());
  } finally {
    client.close();
  }
}

/// 目标必须落在实际可见行中，匹配同块但在另一页不能算续读成功。
bool perfPageContainsCfi(PageContent page, String cfi) {
  for (final slice in page.slices) {
    final offset = slice.block.offsetForCfi(cfi);
    if (offset == null) continue;
    for (final line in slice.lines) {
      if (offset >= line.start &&
          (offset < line.end ||
              line.start == line.end && offset == line.start ||
              offset == slice.block.layout.text.length && offset == line.end)) {
        return true;
      }
    }
  }
  return false;
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
  // 整章冷排不能复用前一进程的持久页索引；只隔离测试内容版本，保留真实原书哈希。
  final cacheRevision = _cacheRevision(revision);
  _results['pagination_scope'] = {
    'book_sha256': revision,
    'content_revision': cacheRevision,
    'isolated_per_process': _run['cache_mode'] != 'warm',
  };
  await db
      .into(db.books)
      .insertOnConflictUpdate(
        BooksCompanion.insert(
          id: const Value(1),
          uuid: _bookId,
          title: _title,
          contentDir: file.parent.path,
          sourcePath: Value(file.path),
          contentRevision: cacheRevision,
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
  if (_scenario == null) {
    await progress.clear(_bookId);
    final target = ReaderProgress(spineIndex: _targetSpine, pageIndex: 0);
    await progress.save(_bookId, target);
  }
  final restored = await progress.load(_bookId);
  if (restored?.spineIndex != _targetSpine ||
      _targetCfi != null && restored?.cfi != _targetCfi) {
    throw StateError('第 $round 轮写入目标章失败，当前 ${restored?.spineIndex}');
  }
  await _until(() => _bookTile() != null);
  _traceStarted = DateTime.now();
  _uiProbe.start();
  final watch = Stopwatch()..start();
  await openPerfReader(
    isMounted: isPerfReaderMounted,
    tap: () => _bookTile()?.onTap?.call(),
  );
  final sample = await _sample(watch, _targetSpine);
  sample['cache_temperature'] = round == 0
      ? '预读文件后的独立进程初开；页界缓存 ${_run['cache_mode']}'
      : '同进程重开';
  _results['open_$round'] = sample;
  await _send('sample', _results);
  if (_openingOnly) return;
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
    _samples.flush();
  }

  void close() {
    _samples.flush();
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
      widget.key == ValueKey<String>('book-row-$_bookId') ||
      widget.key == ValueKey<String>('book-card-$_bookId'),
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
  final completeMs = watch.elapsedMilliseconds;
  final source = _find<ReaderPage>((_) => true)?.source;
  List<PageContent>? pages;
  int? chapterCompleteMs;
  if (_measureFullChapter) {
    if (source is! EpubChapterSource) {
      throw StateError('整章测量未取得 EpubChapterSource');
    }
    pages = await source.loadChapter(spine);
    chapterCompleteMs = watch.elapsedMilliseconds;
  }
  final sample = _uiProbe.finish();
  final visible = _find<ReaderSemanticsLayer>((_) => true)!.page;
  if (_targetCfi != null && !perfPageContainsCfi(visible, _targetCfi!)) {
    throw StateError(
      '续读位置未恢复：第 ${visible.spineIndex} 章第 ${visible.pageIndex} 页不包含目标 CFI',
    );
  }
  sample.addAll({
    'text_ms': textMs,
    'images_ms': imagesMs,
    'complete_ms': completeMs,
    'spine': spine,
    'visible_page': visible.pageIndex,
    'target_cfi_verified': _targetCfi != null,
    'trace': [
      for (final event in ReaderTrace.instance.eventsSince(_traceStarted))
        if (event.bookId == _bookId)
          {
            'name': event.name.name,
            'spine': event.spineIndex,
            'microseconds': event.microseconds,
            'at': event.at.toIso8601String(),
            'fields': event.fields,
          },
    ],
    ..._memory(),
    'environment': _sampleEnvironment(),
    if (source is EpubChapterSource) 'cache': source.cacheReport,
  });
  if (pages != null) {
    sample.addAll({
      'chapter_complete_ms': chapterCompleteMs!,
      'chapter_pages': pages.length,
      'chapter_snapshot_sha256': sha256
          .convert(utf8.encode(jsonEncode(snapshotPages(pages))))
          .toString(),
    });
  }
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
