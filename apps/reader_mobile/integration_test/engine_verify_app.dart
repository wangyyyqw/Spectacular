import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/paint/image_cache.dart';
import 'package:reader_core/epub/epub_chapter_source.dart';
import 'package:reader_mobile/reader/epub_reader_page.dart';
import 'package:reader_mobile/reader/reader_settings.dart';
import 'package:reader_mobile/storage/db.dart';
import 'package:reader_mobile/storage/drift_progress_store.dart';
import 'package:reader_ui/a11y/semantics_layer.dart';
import 'package:reader_ui/menu/reader_menu_overlay.dart';
import 'package:reader_ui/paging/page_turn_mode.dart';
import 'package:reader_ui/paging/continuous_scroll_view.dart';
import 'package:reader_ui/panels/toc_panel.dart';
import 'package:reader_ui/reader_page.dart';
import 'package:reader_ui/reader_view.dart';
import 'package:reader_core/source/toc.dart';

/// 只由 tool/device_engine_verify.py 在隔离包运行的真机引擎验收入口。
///
/// 覆盖：章节加载、嵌套目录跳转、翻页与连续滚动、字体/行距/段距/边距、
/// 图片渲染、SVG 降级、异常 EPUB 容错、字号与主题变更；每一步记录耗时、
/// 内存与断言，并在检查点请求宿主截图。
const _server = String.fromEnvironment('ENGINE_SERVER');

final _results = <String, Object?>{};
final _scenarios = <Map<String, Object?>>[];
final _errors = <String>[];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(home: Scaffold(body: Text('准备真机引擎验收'))));
  final runWatch = Stopwatch()..start();
  try {
    final root = await getApplicationSupportDirectory();
    final fixtureBytes = await _downloadFixtures(root);
    final fixtureDir = Directory('${root.path}/fixtures');
    await fixtureDir.create(recursive: true);
    final fixtures = <String, File>{};
    for (final entry in fixtureBytes.entries) {
      fixtures[entry.key] = await File('${fixtureDir.path}/${entry.key}.epub')
          .writeAsBytes(entry.value, flush: true);
    }
    _results['fixtures'] = fixtures
        .map((key, value) => MapEntry(key, value.lengthSync()))
        .cast<String, Object?>();
    final db = AppDatabase(NativeDatabase(File('${root.path}/verify.sqlite')));
    await db.customStatement('DELETE FROM books');
    final progress = DriftProgressStore(db);
    await _runNamed('S1-S3 混合样本：打开/目录/长章节/翻页', () async {
      await _mountAndRun(
        sourcePath: fixtures['verify-mixed']!.path,
        bookId: 'verify-mixed',
        store: progress,
        body: (harness) => _mixedScenarios(harness),
      );
    });
    await _runNamed('S4 容错样本：缺资源/错误路径/异常样式', () async {
      await _mountAndRun(
        sourcePath: fixtures['verify-tolerance']!.path,
        bookId: 'verify-tolerance',
        store: progress,
        body: (harness) => _toleranceScenarios(harness),
      );
    });
    await _runNamed('S5 小样本：字号/主题/连续滚动', () async {
      await _mountAndRun(
        sourcePath: fixtures['verify-small']!.path,
        bookId: 'verify-small',
        store: progress,
        body: (harness) => _smallScenarios(harness),
      );
    });
    await _runNamed('S6 断链 spine：按 manifest 恢复阅读顺序', () async {
      await _mountAndRun(
        sourcePath: fixtures['verify-broken-spine']!.path,
        bookId: 'verify-broken-spine',
        store: progress,
        body: (harness) => _brokenSpineScenarios(harness),
      );
    });
    await db.close();
  } catch (error, stack) {
    _errors.add('$error\n$stack');
  }
  _results['scenarios'] = _scenarios;
  _results['errors'] = _errors;
  _results['total_ms'] = runWatch.elapsedMilliseconds;
  await _send('done', _results);
}

Future<void> _runNamed(String name, Future<void> Function() body) async {
  final watch = Stopwatch()..start();
  final scenario = <String, Object?>{
    'name': name,
    'ok': false,
    'ms': 0,
    'steps': <Map<String, Object?>>[],
  };
  _scenarios.add(scenario);
  try {
    await body();
    scenario['ok'] = true;
  } catch (error, stack) {
    _errors.add('[$name] $error\n$stack');
    scenario['error'] = '$error';
  }
  scenario['ms'] = watch.elapsedMilliseconds;
}

/// 把 harness 挂到 widget 树，运行 body，然后卸载。
Future<void> _mountAndRun({
  required String sourcePath,
  required String bookId,
  required DriftProgressStore store,
  required Future<void> Function(_HarnessController) body,
}) async {
  final harnessKey = GlobalKey<_ReaderHarnessState>();
  final navigatorKey = GlobalKey<NavigatorState>();
  runApp(
    MaterialApp(
      navigatorKey: navigatorKey,
      home: _ReaderHarness(
        key: harnessKey,
        sourcePath: sourcePath,
        bookId: bookId,
        store: store,
      ),
    ),
  );
  await _until(() => _find<ReaderPage>((_) => true) != null);
  await harnessKey.currentState!.pumpOnce();
  try {
    await body(_HarnessController(harnessKey, navigatorKey));
  } finally {
    runApp(const MaterialApp(home: Scaffold(body: Text('已卸载'))));
    await _until(() => harnessKey.currentState == null);
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }
}

// ---------------------------------------------------------------- 场景

Future<void> _mixedScenarios(_HarnessController harness) async {
  final source = harness.source;
  await _step('打开与首屏', () async {
    await harness.waitReadable(0);
    _record({
      'spine_chapters': source.chapterCount,
      'rss_bytes': ProcessInfo.currentRss,
      'toc_entries': flattenToc(source.toc).length,
    });
    await _capture('mixed-open');
  });

  await _step('嵌套目录与跳转', () async {
    final rows = flattenToc(source.toc);
    final maxDepth = rows.fold<int>(
      0,
      (d, row) => row.depth > d ? row.depth : d,
    );
    final longEntry = rows
        .firstWhere((row) => row.entry.title.contains('长章节'))
        .entry;
    _record({
      'toc_depth': maxDepth,
      'toc_entries': rows.length,
      'jump_target_spine': longEntry.spineIndex,
      'jump_target_title': longEntry.title,
    });
    if (maxDepth < 3) {
      throw StateError('目录层级只有 $maxDepth，期望 ≥3');
    }
    await harness.openToc();
    await _capture('toc-nested');
    final watch = Stopwatch()..start();
    _find<TocPanel>((_) => true)!.onSelect(longEntry);
    await harness.waitReadable(longEntry.spineIndex);
    _record({
      'jump_ms': watch.elapsedMilliseconds,
      'current_spine': harness.currentSpine(),
      'rss_bytes': ProcessInfo.currentRss,
    });
    if (harness.currentSpine() != longEntry.spineIndex) {
      throw StateError(
        '跳转后 spine=${harness.currentSpine()}，期望 ${longEntry.spineIndex}',
      );
    }
    await _capture('long-enter');
  });

  await _step('长章节加载与翻页', () async {
    final watch = Stopwatch()..start();
    final pages = await source.loadChapter(10);
    final loadMs = watch.elapsedMilliseconds;
    final turns = <int>[];
    for (var index = 0; index < 4; index++) {
      final turnWatch = Stopwatch()..start();
      final before = harness.currentPageIndex();
      harness.nextPage();
      await _until(
        () =>
            harness.currentPageIndex() != before ||
            harness.currentSpine() != 10,
        timeout: const Duration(seconds: 20),
      );
      turns.add(turnWatch.elapsedMilliseconds);
    }
    _record({
      'pages': pages.length,
      'load_ms': loadMs,
      'page_turn_ms': turns,
      'rss_bytes': ProcessInfo.currentRss,
      'cache': source.cacheReport,
    });
    await _capture('long-page');
  });

  await _step('排版关键样式探针', () async {
    final pages = await source.loadChapter(3);
    final blocks = <PageBlock>[
      for (final page in pages)
        for (final slice in page.slices) slice.block,
    ];
    PageBlock? findBlock(String needle) {
      for (final block in blocks) {
        if (block.layout.text.contains(needle)) {
          return block;
        }
      }
      return null;
    }

    final tight = findBlock('这一行使用紧缩行距');
    final wide = findBlock('这一行使用宽松行距');
    final noIndent = findBlock('这一行取消首行缩进');
    final authorEm = findBlock('来自作者样式表的加强规则');
    if (tight == null || wide == null || noIndent == null || authorEm == null) {
      throw StateError('样式探针段落未出现在分页结果中');
    }
    double linePitch(PageBlock block) =>
        block.layout.lines.isEmpty ? 0 : block.layout.lines.first.height;
    double firstIndent(PageBlock block) =>
        block.layout.lines.isEmpty ? 0 : block.layout.lines.first.indent;
    final settings = ReaderSettings.defaults;
    final expectedPitch = settings.fontSize * settings.lineHeight;
    _record({
      'setting_font_size': settings.fontSize,
      'setting_line_height': settings.lineHeight,
      'base_font_size': tight.style?.fontSize,
      'tight_line_height': linePitch(tight),
      'wide_line_height': linePitch(wide),
      'expected_line_height': expectedPitch,
      'wide_space_after': wide.spaceAfter,
      'normal_space_after': tight.spaceAfter,
      'indent_with_text_indent': firstIndent(tight),
      'indent_without_text_indent': firstIndent(noIndent),
      'letter_spacing': tight.style?.letterSpacing,
      'author_em_weight': authorEm.style?.fontWeight,
      'font_family': tight.style?.fontFamilies.join(','),
    });
    // 设计口径（P2-22）：设置层高于作者层，行距/字号由设置决定。
    if ((linePitch(tight) - expectedPitch).abs() > 1) {
      throw StateError(
        '行距 ${linePitch(tight)} 与设置 ${settings.lineHeight}×${settings.fontSize} 不一致',
      );
    }
    if (!((tight.style?.letterSpacing ?? 0) > 0)) {
      throw StateError('作者 letter-spacing 未生效');
    }
    if ((authorEm.style?.fontWeight ?? 400) < 700) {
      throw StateError('后一份样式表的加粗规则未生效：${authorEm.style?.fontWeight}');
    }
    if (!(firstIndent(tight) > 4 && firstIndent(noIndent) < 1)) {
      throw StateError(
        '缩进探针异常：tight=${firstIndent(tight)} noIndent=${firstIndent(noIndent)}',
      );
    }
  });

  await _step('表格与列表渲染', () async {
    final pages = await source.loadChapter(5);
    var tableCells = 0;
    for (final page in pages) {
      for (final slice in page.slices) {
        final table = slice.block.table;
        tableCells += table?.cells.length ?? 0;
      }
    }
    var listMarkers = 0;
    for (final page in await source.loadChapter(4)) {
      for (final slice in page.slices) {
        if (slice.block.listMarker != null) {
          listMarkers += 1;
        }
      }
    }
    _record({
      'chapter_pages': pages.length,
      'table_cells': tableCells,
      'list_markers': listMarkers,
    });
    if (tableCells < 4) {
      throw StateError('表格单元格只有 $tableCells 个');
    }
    if (listMarkers < 2) {
      throw StateError('列表标记只有 $listMarkers 个');
    }
  });

  await _step('图片渲染与缺失占位', () async {
    final pages = await source.loadChapter(7);
    final urls = _imageUrlsOf(pages);
    _record({'image_urls': urls.length});
    await harness.openSpine(7);
    // 本章刻意引用一张不存在的图片（missing-photo.jpg），
    // 等待条件只要求真实存在的三张图片解码完成。
    const expectedImages = 3;
    await _until(
      () =>
          urls.where((url) => harness.imageCache.lookup(url) != null).length >=
          expectedImages,
      timeout: const Duration(seconds: 20),
    );
    final decoded = urls.where((url) => harness.imageCache.lookup(url) != null);
    _record({
      'decoded_images': decoded.length,
      'missing_images': urls.length - decoded.length,
      'page_text': pages
          .expand((page) => page.slices)
          .map((slice) => slice.block.layout.text)
          .join()
          .length,
    });
    await _capture('images-page');
    if (decoded.length < expectedImages) {
      throw StateError(
        '图片解码不足：成功 ${decoded.length}/${urls.length}，期望至少 $expectedImages 张',
      );
    }
  });

  await _step('SVG 与矢量降级', () async {
    final pages = await source.loadChapter(8);
    await harness.openSpine(8);
    final text = pages
        .expand((page) => page.slices)
        .map((slice) => slice.block.layout.text)
        .join();
    _record({
      'chapter_pages': pages.length,
      'has_body_text': text.contains('标点挤压'),
      'layout_warning': source.layoutWarningFor(8),
    });
    await _capture('svg-page');
    if (!text.contains('标点挤压')) {
      throw StateError('SVG 章正文缺失');
    }
  });
}

Future<void> _toleranceScenarios(_HarnessController harness) async {
  final source = harness.source;
  await _step('容错样本打开', () async {
    final watch = Stopwatch()..start();
    await harness.waitReadable(0);
    _record({
      'open_ms': watch.elapsedMilliseconds,
      'spine_chapters': source.chapterCount,
      'rss_bytes': ProcessInfo.currentRss,
    });
    await _capture('tolerance-open');
  });
  await _step('缺资源章节仍可翻页', () async {
    final pages = await source.loadChapter(1);
    final text = pages
        .expand((page) => page.slices)
        .map((slice) => slice.block.layout.text)
        .join();
    _record({
      'chapter_pages': pages.length,
      'has_text': text.contains('重复标识'),
      'layout_warning': source.layoutWarningFor(1),
    });
    if (!text.contains('重复标识')) {
      throw StateError('缺资源章节正文缺失');
    }
    final before = harness.currentPageIndex();
    harness.nextPage();
    await _until(
      () => harness.currentPageIndex() != before || harness.currentSpine() != 0,
      timeout: const Duration(seconds: 20),
    );
    await _capture('tolerance-page2');
  });
}

Future<void> _smallScenarios(_HarnessController harness) async {
  final source = harness.source;
  await _step('小样本打开与字号变更', () async {
    await harness.waitReadable(0);
    final before = await source.loadChapter(0);
    final beforeHeight = _firstLineHeight(before);
    harness.applySettings(
      (settings) =>
          settings.copyWithOverrides(settings.overrides.copyWith(fontSize: 24)),
    );
    await harness.waitRelayout();
    final after = await source.loadChapter(0);
    final afterHeight = _firstLineHeight(after);
    _record({
      'pages_before': before.length,
      'pages_after': after.length,
      'line_height_before': beforeHeight,
      'line_height_after': afterHeight,
      'rss_bytes': ProcessInfo.currentRss,
    });
    if (!(afterHeight > beforeHeight)) {
      throw StateError('字号放大后行高未增大：$beforeHeight → $afterHeight');
    }
    await _capture('font-24');
  });
  await _step('主题切换与像素检查', () async {
    harness.applySettings((settings) => settings.copyWithTheme('dark'));
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await _capture('theme-dark');
    harness.applySettings((settings) => settings.copyWithTheme('sepia'));
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await _capture('theme-sepia');
    harness.applySettings(
      (settings) =>
          settings.copyWithOverrides(settings.overrides.copyWith(fontSize: 17)),
    );
    await harness.waitRelayout();
    _record({'themes': 'dark,sepia'});
  });
  await _step('连续滚动模式', () async {
    harness.applySettings(
      (settings) => settings.copyWithPageTurnMode(PageTurnMode.scroll),
    );
    await _until(
      () => _find<ContinuousScrollView>((_) => true) != null,
      timeout: const Duration(seconds: 20),
    );
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await _capture('scroll-mode');
    harness.applySettings(
      (settings) => settings.copyWithPageTurnMode(PageTurnMode.cover),
    );
    await _until(
      () => _find<ContinuousScrollView>((_) => true) == null,
      timeout: const Duration(seconds: 20),
    );
    _record({'scroll_mode': 'shown'});
  });
}

/// S6：spine 全部指向不存在的 id，验证解析层按 manifest 恢复阅读顺序。
Future<void> _brokenSpineScenarios(_HarnessController harness) async {
  final source = harness.source;
  await _step('断链 spine 恢复阅读顺序', () async {
    await harness.waitReadable(0);
    final pages = await source.loadChapter(0);
    final text = pages
        .expand((page) => page.slices)
        .map((slice) => slice.block.layout.text)
        .join();
    _record({
      'spine_chapters': source.chapterCount,
      'toc_entries': flattenToc(source.toc).length,
      'first_chapter_pages': pages.length,
      'has_recovered_text': text.contains('恢复顺序甲'),
      'rss_bytes': ProcessInfo.currentRss,
    });
    await _capture('broken-spine-open');
    if (source.chapterCount != 3) {
      throw StateError('恢复后的章节数为 ${source.chapterCount}，期望 3');
    }
    if (!text.contains('恢复顺序甲')) {
      throw StateError('恢复章节正文缺失');
    }
  });
  await _step('恢复后翻页与目录跳转', () async {
    final before = harness.currentPageIndex();
    harness.nextPage();
    await _until(
      () => harness.currentPageIndex() != before || harness.currentSpine() != 0,
      timeout: const Duration(seconds: 20),
    );
    await harness.openSpine(2);
    _record({
      'current_spine': harness.currentSpine(),
      'rss_bytes': ProcessInfo.currentRss,
    });
    await _capture('broken-spine-ch3');
    if (harness.currentSpine() != 2) {
      throw StateError('目录跳转后 spine=${harness.currentSpine()}，期望 2');
    }
  });
}

// ---------------------------------------------------------------- 工具

double _firstLineHeight(List<PageContent> pages) {
  for (final page in pages) {
    for (final slice in page.slices) {
      if (slice.block.layout.lines.isNotEmpty) {
        return slice.block.layout.lines.first.height;
      }
    }
  }
  return 0;
}

List<String> _imageUrlsOf(List<PageContent> pages) {
  final urls = <String>{};
  for (final page in pages) {
    for (final slice in page.slices) {
      final block = slice.block;
      final background = block.style?.backgroundImage;
      if (background != null && !background.startsWith('linear-gradient')) {
        urls.add(background);
      }
      for (final image in block.inlineImages) {
        urls.add(image.url);
      }
      for (final fragment in block.containers) {
        final containerImage = fragment.container.style.backgroundImage;
        if (containerImage != null) {
          urls.add(containerImage);
        }
      }
      final pageImage = page.background?.imageUrl;
      if (pageImage != null) {
        urls.add(pageImage);
      }
    }
  }
  return urls.toList(growable: false);
}

void _record(Map<String, Object?> metrics) {
  final current = _scenarios.last['steps']! as List<Map<String, Object?>>;
  current.last['metrics'] = metrics;
}

Future<void> _step(String name, Future<void> Function() body) async {
  final steps = _scenarios.last['steps']! as List<Map<String, Object?>>;
  final step = <String, Object?>{'name': name, 'ok': false, 'ms': 0};
  steps.add(step);
  final watch = Stopwatch()..start();
  try {
    await body();
    step['ok'] = true;
  } catch (error, stack) {
    step['error'] = '$error';
    _errors.add('[$name] $error\n$stack');
  }
  step['ms'] = watch.elapsedMilliseconds;
  await _send('sample', _results);
}

/// 请求宿主截图；失败只记日志，不影响场景结论。
Future<void> _capture(String name) async {
  final steps = _scenarios.last['steps']! as List<Map<String, Object?>>;
  try {
    await Future<void>.delayed(const Duration(milliseconds: 120));
    await WidgetsBinding.instance.endOfFrame;
    await _send('capture/$name', {'at': DateTime.now().toIso8601String()});
    steps.last['screenshot'] = name;
  } catch (error) {
    _errors.add('截图 $name 失败：$error');
  }
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

Future<void> _until(
  bool Function() condition, {
  Duration timeout = const Duration(minutes: 2),
}) async {
  final watch = Stopwatch()..start();
  while (!condition()) {
    if (watch.elapsed > timeout) {
      throw TimeoutException('等待条件超时');
    }
    await Future<void>.delayed(const Duration(milliseconds: 8));
  }
}

Future<Map<String, Uint8List>> _downloadFixtures(Directory root) async {
  const names = [
    'verify-mixed',
    'verify-tolerance',
    'verify-small',
    'verify-broken-spine',
  ];
  final client = HttpClient();
  final result = <String, Uint8List>{};
  try {
    for (final name in names) {
      final request = await client.getUrl(
        Uri.parse('$_server/fixtures/$name.epub'),
      );
      final response = await request.close();
      if (response.statusCode != 200) {
        throw StateError('fixture 下载失败：$name → ${response.statusCode}');
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response) {
        builder.add(chunk);
      }
      result[name] = builder.takeBytes();
    }
  } finally {
    client.close();
  }
  return result;
}

Future<void> _send(String path, Map<String, Object?> data) async {
  final client = HttpClient();
  try {
    final request = await client.postUrl(Uri.parse('$_server/$path'));
    request.headers.contentType = ContentType.json;
    final bytes = utf8.encode(jsonEncode(data));
    request.contentLength = bytes.length;
    request.add(bytes);
    final response = await request.close();
    await response.drain<void>();
  } catch (_) {
    // 采样上报失败不阻断场景执行。
  } finally {
    client.close();
  }
}

// ---------------------------------------------------------------- 宿主

class _HarnessController {
  _HarnessController(this.key, this.navigatorKey);

  final GlobalKey<_ReaderHarnessState> key;
  final GlobalKey<NavigatorState> navigatorKey;

  EpubChapterSource get source => key.currentState!.source;

  DecodedImageCache get imageCache {
    final cache = _find<ReaderPage>((_) => true)?.imageCache;
    if (cache == null) {
      throw StateError('阅读页图片缓存尚未就绪');
    }
    return cache;
  }

  int currentSpine() =>
      _find<ReaderSemanticsLayer>((_) => true)!.page.spineIndex;

  int currentPageIndex() =>
      _find<ReaderSemanticsLayer>((_) => true)!.page.pageIndex;

  Future<void> openToc() async {
    final view = _find<ReaderView>((_) => true)!;
    if (_find<ReaderMenuOverlay>((overlay) => overlay.open) == null) {
      view.onToggleToolbar!();
    }
    await _until(
      () => _find<ReaderMenuOverlay>((overlay) => overlay.open) != null,
    );
    _find<ReaderMenuOverlay>((overlay) => overlay.open)!
        .onEntry(ReaderMenuEntry.toc);
    await _until(() => _find<TocPanel>((_) => true) != null);
  }

  void nextPage() => _find<ReaderView>((_) => true)!.onNext!();

  /// 通过目录跳到指定 spine 并等到该章可读。
  Future<void> openSpine(int spineIndex) async {
    if (currentSpine() == spineIndex) {
      await waitReadable(spineIndex);
      return;
    }
    final rows = flattenToc(source.toc);
    final row = rows.firstWhere(
      (candidate) => candidate.entry.spineIndex == spineIndex,
      orElse: () => throw StateError('目录中没有 spine=$spineIndex 的条目'),
    );
    await openToc();
    _find<TocPanel>((_) => true)!.onSelect(row.entry);
    await waitReadable(spineIndex);
  }

  Future<void> waitReadable(int spine) async {
    await _until(
      () =>
          _find<ReaderSemanticsLayer>(
            (layer) =>
                layer.page.spineIndex == spine && layer.page.slices.isNotEmpty,
          ) !=
          null,
    );
    await WidgetsBinding.instance.endOfFrame;
  }

  Future<void> waitRelayout() async {
    await Future<void>.delayed(const Duration(milliseconds: 600));
    await WidgetsBinding.instance.endOfFrame;
  }

  void applySettings(ReaderSettings Function(ReaderSettings) change) {
    key.currentState!.applySettings(change);
  }
}

class _ReaderHarness extends StatefulWidget {
  const _ReaderHarness({
    super.key,
    required this.sourcePath,
    required this.bookId,
    required this.store,
  });

  final String sourcePath;
  final String bookId;
  final DriftProgressStore store;

  @override
  State<_ReaderHarness> createState() => _ReaderHarnessState();
}

class _ReaderHarnessState extends State<_ReaderHarness> {
  ReaderSettings _settings = ReaderSettings.defaults;

  /// 供场景读取的章节源：ReaderPage 是公开 widget，source 是公开字段。
  EpubChapterSource get source {
    final source = _find<ReaderPage>((_) => true)?.source;
    if (source is EpubChapterSource) {
      return source;
    }
    throw StateError('章节源尚未就绪');
  }

  /// 等一帧，确保宿主拿到首帧后再开始断言。
  Future<void> pumpOnce() async {
    await WidgetsBinding.instance.endOfFrame;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: EpubReaderPage(
        sourcePath: widget.sourcePath,
        bookId: widget.bookId,
        store: widget.store,
        settings: _settings,
        bookTitle: widget.bookId,
        onSettingsChanged: (next) {
          if (mounted) {
            setState(() => _settings = next);
          }
        },
      ),
    );
  }

  void applySettings(ReaderSettings Function(ReaderSettings) change) {
    setState(() => _settings = change(_settings));
  }

  @override
  void initState() {
    super.initState();
    // 初始即白色主题与默认排版，后续场景用 applySettings 驱动变更。
  }
}
