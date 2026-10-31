import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:reader_mobile/home/bookshelf_page.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/reader/epub_chapter_source.dart';
import 'package:reader_mobile/storage/db.dart';
import 'package:reader_mobile/storage/drift_progress_store.dart';
import 'package:reader_ui/a11y/semantics_layer.dart';
import 'package:reader_ui/menu/reader_menu_overlay.dart';
import 'package:reader_ui/panels/toc_panel.dart';
import 'package:reader_ui/reader_page.dart';
import 'package:reader_ui/reader_session.dart';
import 'package:reader_ui/reader_view.dart';

/// 只由 device_reader_perf.py 在独立包运行；计时包含真实书架读盘和正文帧。
const _server = String.fromEnvironment('PERF_SERVER');
final _navigator = GlobalKey<NavigatorState>();
final _results = <String, Object?>{};

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(home: Scaffold(body: Text('准备真机性能测试'))));
  try {
    final root = await getApplicationSupportDirectory();
    final file = await _download(root);
    if (const bool.fromEnvironment('PERF_IMPORT')) {
      await _measureImport(root, file);
    }
    final db = AppDatabase(NativeDatabase(File('${root.path}/perf.sqlite')));
    await _seedBook(db, file);
    final progress = DriftProgressStore(db);
    final library = LibraryStore(
      database: db,
      directoryProvider: () async => root,
    );
    await library.setSetting('bookshelf.grid', 'false');
    runApp(
      MaterialApp(
        navigatorKey: _navigator,
        home: BookshelfPage(library: library, progressStore: progress),
      ),
    );
    for (var round = 0; round < 3; round++) {
      await _openRound(progress, round);
      if (round == 2 && const bool.fromEnvironment('PERF_LONG_SCAN')) {
        await _scanLongBook();
      }
      _navigator.currentState!.pop();
      await Future<void>.delayed(
        Duration(milliseconds: round == 2 ? 1500 : 500),
      );
    }
    if (const bool.fromEnvironment('PERF_LONG_SCAN')) {
      _results['after_close_rss_bytes'] = ProcessInfo.currentRss;
    }
    await _send('done', _results);
  } catch (error, stack) {
    await _send('done', {..._results, 'error': '$error', 'stack': '$stack'});
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
    final bytes = await original.readAsBytes();
    stages['read_ms'] = watch.elapsedMilliseconds;
    final entry = await library.importBytes(
      bytes,
      onProgress: (progress) {
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
  // 测试准备使用固定书架记录；正文读取仍走生产 File.readAsBytes 路径。
  await db
      .into(db.books)
      .insertOnConflictUpdate(
        BooksCompanion.insert(
          id: const Value(1),
          uuid: 'perf-book',
          title: '诸神愚戏',
          contentDir: file.parent.path,
          sourcePath: Value(file.path),
          spineCount: const Value(1541),
          createdAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );
}

Future<void> _openRound(DriftProgressStore progress, int round) async {
  await progress.save(
    'perf-book',
    ReaderProgress(spineIndex: 29, pageIndex: 0),
  );
  await _until(() => _bookTile() != null);
  final watch = Stopwatch()..start();
  _bookTile()!.onTap!();
  _results['open_$round'] = await _sample(watch, 29);
  await _send('sample', _results);
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

ListTile? _bookTile() => _find<ListTile>(
  (widget) => widget.title is Text && (widget.title! as Text).data == '诸神愚戏',
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
  await _until(() => _fullyVisible(spine));
  await WidgetsBinding.instance.endOfFrame;
  final memory = ProcessInfo.currentRss;
  final source = _find<ReaderPage>((_) => true)?.source;
  return {
    'text_ms': textMs,
    'images_ms': imagesMs,
    'complete_ms': watch.elapsedMilliseconds,
    'spine': spine,
    'rss_bytes': memory,
    if (source is EpubChapterSource) 'cache': source.cacheReport,
  };
}

Future<void> _scanLongBook() async {
  final source = _find<ReaderPage>((_) => true)?.source;
  if (source is! EpubChapterSource) {
    throw StateError('长书扫描未取得 EpubChapterSource');
  }
  final started = ProcessInfo.currentRss;
  var peakRss = started;
  final samples = <Map<String, Object>>[];
  final count = source.chapterCount;
  for (var spine = 0; spine < count; spine += 10) {
    final watch = Stopwatch()..start();
    final pages = await source.loadChapter(spine);
    await WidgetsBinding.instance.endOfFrame;
    final rss = ProcessInfo.currentRss;
    if (rss > peakRss) peakRss = rss;
    if (spine == 0 || spine % 100 == 0 || spine + 10 >= count) {
      samples.add({
        'spine': spine,
        'load_ms': watch.elapsedMilliseconds,
        'pages': pages.length,
        'rss_bytes': rss,
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
    'samples': samples,
  };
  await _send('sample', _results);
}

bool _fullyVisible(int spine) {
  final element = _findElement(
    (widget) =>
        widget is ReaderSemanticsLayer && widget.page.spineIndex == spine,
  );
  if (element == null) return false;
  var visible = true;
  element.visitAncestorElements((ancestor) {
    final widget = ancestor.widget;
    if (widget is FadeTransition && widget.opacity.value < 1) visible = false;
    return visible;
  });
  return visible;
}

Future<void> _readable(int spine) async {
  await _until(
    () =>
        _find<ReaderSemanticsLayer>(
          (w) => w.page.spineIndex == spine && w.page.slices.isNotEmpty,
        ) !=
        null,
  );
  // 确认目标正文已完成一帧，计时不止于 parse 或 session 状态变化。
  await WidgetsBinding.instance.endOfFrame;
}

Future<void> _imagesReady() async {
  final reader = _find<ReaderPage>((_) => true)!;
  final page = _find<ReaderSemanticsLayer>((_) => true)!.page;
  final urls = <String>{
    if (page.background != null) page.background!.imageUrl,
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
