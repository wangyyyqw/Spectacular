import 'dart:async';
import 'dart:convert';
import 'dart:developer' show Timeline;
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:reader_core/perf/trace.dart';
import 'package:reader_mobile/reader/epub_reader_page.dart';
import 'package:reader_mobile/reader/reader_settings.dart';
import 'package:reader_ui/paging/continuous_scroll_view.dart';
import 'package:reader_ui/paging/page_turn_mode.dart';
import 'package:reader_ui/paging/page_turn_view.dart';
import 'package:reader_ui/reader_session.dart';
import 'package:reader_ui/reader_ui_diagnostics.dart';

import 'reader_perf_probe.dart';

/// 正式阅读页、控制器和手势识别器；只在隔离 release 测量包执行。
const _server = String.fromEnvironment('PERF_SERVER');
const _rounds = int.fromEnvironment('PERF_ROUNDS', defaultValue: 3);
const _spine = int.fromEnvironment('PERF_SPINE', defaultValue: 10);
const _startPage = int.fromEnvironment('PERF_START_PAGE');
const _farSpines = String.fromEnvironment('PERF_FAR_SPINES');
const _modeIds = String.fromEnvironment(
  'PERF_MODES',
  defaultValue: 'simulation3d',
);
const _sceneIds = String.fromEnvironment(
  'PERF_SCENES',
  defaultValue: 'open,continuous,cross,far,resume,drag,fling,extend',
);
final _samples = ReaderPerfProbeSamples();
final _results = <String, Object?>{};
final _turns = <Map<String, Object?>>[];
List<Map<String, Object?>>? _events;
int _eventStart = 0;
PageTurnMode _mode = PageTurnMode.cover;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  WidgetsBinding.instance.addTimingsCallback(_samples.addFrames);
  ReaderUiDiagnostics.onEvent = (event, fields) {
    _events?.add({
      'event': event,
      'at_us': Timeline.now - _eventStart,
      ...fields,
    });
  };
  runApp(const MaterialApp(home: Scaffold(body: Text('准备翻页对比'))));
  try {
    final file = await _download();
    final revision = (await sha256.bind(file.openRead()).first).toString();
    _describeRun(revision);
    for (final id in _modeIds.split(',')) {
      _mode = PageTurnMode.values.singleWhere((mode) => mode.id == id);
      for (var round = 0; round < _rounds; round++) {
        await _runRound(file, revision, round);
      }
    }
    await _drainFrames();
    _results['frame_timings_complete'] = _samples.complete;
    await _send('done');
  } catch (error, stack) {
    _results.addAll({'error': '$error', 'stack': '$stack'});
    await _drainFrames();
    _results['frame_timings_complete'] = _samples.complete;
    await _send('done');
  } finally {
    WidgetsBinding.instance.removeTimingsCallback(_samples.addFrames);
    ReaderUiDiagnostics.onEvent = null;
  }
}

void _describeRun(String revision) {
  _results.addAll({
    'book_sha256': revision,
    'turns': _turns,
    'contract': {
      'schema': 2,
      'modes': _modeIds,
      'scenes': _sceneIds,
      'rounds': _rounds,
      'start': [_spine, _startPage],
      'far_spines': _farSpines,
      'input': '分页点击调用生产 request；分页和滚动拖动注入 Flutter 指针事件，不计 Android 触摸与合成延迟',
      'ready': '快照交付和 Flutter 绘制完成分别记录；不是屏幕实际呈现时间',
      'frames': '按 buildStart 归属；UI/Raster 按 display 刷新率分别统计，非系统丢帧',
      'temperature': '每轮重建阅读页，系统文件缓存不清空；开书首翻不等预热',
      'cross': 'cross 为预热后跨章；cold-cross 为新阅读页章末首翻，不清系统文件缓存',
      'resume': '宿主将隔离应用切到桌面两秒后恢复，不模拟生命周期',
    },
  });
}

Future<File> _download() async {
  final root = await getApplicationSupportDirectory();
  final file = File('${root.path}/page-turn-perf.epub');
  final client = HttpClient();
  try {
    final response = await (await client.getUrl(
      Uri.parse('$_server/book.epub'),
    )).close();
    if (response.statusCode != 200) throw StateError('原书传输失败');
    await response.pipe(file.openWrite());
    return file;
  } finally {
    client.close();
  }
}

Future<void> _open(
  File file,
  String revision,
  int round, {
  int startPage = _startPage,
}) async {
  final store = MemoryReaderProgressStore();
  await store.save(
    'turn-perf',
    ReaderProgress(
      spineIndex: _spine,
      pageIndex: startPage,
      contentRevision: revision,
    ),
  );
  runApp(
    MaterialApp(
      home: EpubReaderPage(
        key: UniqueKey(),
        sourcePath: file.path,
        contentRevision: revision,
        bookId: 'turn-perf',
        bookTitle: const String.fromEnvironment('PERF_TITLE'),
        store: store,
        settings: ReaderSettings(
          fontSize: double.parse(
            const String.fromEnvironment('PERF_FONT_SIZE', defaultValue: '21'),
          ),
          themeId: 'sepia',
          backgroundId: 'paper',
          pageTurnMode: _mode,
          keepScreenOn: true,
        ),
      ),
    ),
  );
  await WidgetsBinding.instance.endOfFrame;
  await _until(() => _sessionOrNull?.page != null && !_sessionOrNull!.loading);
  await WidgetsBinding.instance.endOfFrame;
  if (_mode == PageTurnMode.scroll) {
    await waitForScrollPerfPosition(
      () => _scroll,
      spine: _spine,
      page: startPage,
    );
  }
  final page = _session.page!;
  if (page.spineIndex != _spine || page.pageIndex != startPage) {
    throw StateError(
      '起点不一致：期望 $_spine:$startPage，实际 ${page.spineIndex}:${page.pageIndex}',
    );
  }
  _results['viewport'] = {
    'width': _context.size?.width,
    'height': _context.size?.height,
    'refresh_rate': View.of(_context).display.refreshRate,
  };
}

bool _has(String scene) => _sceneIds.split(',').contains(scene);

Future<void> _runRound(File file, String revision, int round) async {
  await _open(file, revision, round);
  if (_has('open')) await _turn('open', round, true);
  await Future<void>.delayed(const Duration(milliseconds: 1500));
  if (_has('continuous')) {
    for (final next in [
      true,
      true,
      true,
      true,
      true,
      true,
      false,
      false,
      false,
      false,
    ]) {
      await _turn('continuous', round, next);
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
  }
  if (_has('cross')) await _crossChapter(round);
  if (_has('far')) {
    final count = _session.source.chapterCount;
    final destinations = _farSpines.isEmpty
        ? {(_spine + 13) % count, (_spine + count ~/ 2) % count}
        : _farSpines.split(',').map(int.parse).toSet();
    for (final spine in destinations) {
      await _jump(spine);
      await _turn('far', round, true);
    }
  }
  if (_has('resume')) {
    await _send('background');
    await WidgetsBinding.instance.endOfFrame;
    await _turn('resume', round, true);
  }
  if (_mode == PageTurnMode.scroll) {
    await _scrollScenes(round);
  } else {
    await _pagedDragScenes(round);
  }
  if (_has('cold-cross')) {
    await _jump(_spine);
    final pages = await _session.chapterPages();
    await _open(file, revision, round, startPage: pages.last.pageIndex);
    await _turn('cold-cross', round, true);
    final actualSpine = _mode == PageTurnMode.scroll
        ? readScrollPerfPosition(_scroll!)?.spine
        : _session.page?.spineIndex;
    if (actualSpine != _spine + 1) {
      throw StateError('冷开书章末首翻未进入相邻章：$actualSpine');
    }
  }
  await _drainFrames();
  await _send('sample');
}

Future<void> _jump(int spine) async {
  await _session.jumpToChapter(spine);
  await WidgetsBinding.instance.endOfFrame;
  if (_mode == PageTurnMode.scroll) {
    final cfi = _session.cfiAtPageOffset(_session.page!, null);
    if (cfi == null) throw StateError('滚动跳章缺少章首锚点 $spine');
    // 章号导航可能先以旧进度重建窗口；连续 CFI 导航在最终位置确定后
    // 更新代次，随后仍须核验已挂载切片，不能只核验会话页。
    await _session.jumpToCfi(cfi, continuous: true);
    await waitForScrollPerfPosition(() => _scroll, spine: spine, page: 0);
  }
  if (_session.page?.spineIndex != spine) throw StateError('跳章未到指定位置 $spine');
}

Future<void> _crossChapter(int round) async {
  if (_mode == PageTurnMode.scroll) {
    await _jump(_spine + 1);
    await _turn('cross', round, false);
    final previous = readScrollPerfPosition(_scroll!);
    if (previous?.spine != _spine) {
      throw StateError('滚动前跨章未到相邻章：$previous');
    }
    await _turn('cross', round, true);
    final next = readScrollPerfPosition(_scroll!);
    if (next?.spine != _spine + 1) {
      throw StateError('滚动后跨章未到相邻章：$next');
    }
    return;
  }
  await _jump(_spine);
  final pages = await _session.chapterPages();
  final cfi = _session.cfiAtPageOffset(pages.last, null);
  if (cfi == null) throw StateError('章末缺少定位锚点');
  await _session.jumpToCfi(cfi);
  await WidgetsBinding.instance.endOfFrame;
  if (_session.page?.pageIndex != pages.last.pageIndex) {
    throw StateError('章末定位不一致');
  }
  await Future<void>.delayed(const Duration(milliseconds: 700));
  await _turn('cross', round, true);
  await Future<void>.delayed(const Duration(milliseconds: 120));
  await _turn('cross', round, false);
}

Future<void> _turn(String scene, int round, bool next) =>
    _measure(scene, round, next, (sample) async {
      if (_mode == PageTurnMode.scroll) {
        final before = readScrollPerfPosition(_scroll!);
        if (before == null) throw StateError('滚动输入前没有已挂载正文');
        sample['input_accepted_ms'] = (Timeline.now - _eventStart) / 1000;
        await _scroll!.scrollPage(next);
        final after = await waitForScrollPerfPosition(() => _scroll);
        if (!_scrollPositionMoved(before, after)) {
          throw StateError('滚动输入未推进实际视口：$before → $after');
        }
        await _scroll!.flushVisiblePosition();
        sample['landed_ms'] = (Timeline.now - _eventStart) / 1000;
      } else {
        await _pagedTurn(sample, next);
      }
    });

Future<void> _pagedTurn(
  Map<String, Object?> sample,
  bool next, {
  Future<void> Function()? input,
  bool completes = true,
}) async {
  final controller = _view!.controller;
  final origin = controller.session.page;
  final landed = Completer<void>();
  var firstFrameScheduled = false;
  var originFrameScheduled = false;
  var accepted = false;
  void changed() {
    double elapsed() => (Timeline.now - _eventStart) / 1000;
    if (controller.active) {
      accepted = true;
      sample.putIfAbsent('input_accepted_ms', elapsed);
    }
    if (controller.originImage != null) {
      sample.putIfAbsent('origin_ready_ms', elapsed);
      if (!originFrameScheduled) {
        originFrameScheduled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          sample['origin_feedback_ms'] = elapsed();
        });
      }
    }
    if (controller.targetImage != null) {
      sample.putIfAbsent('target_ready_ms', elapsed);
    }
    if (controller.originImage != null &&
        controller.progress > 0 &&
        !firstFrameScheduled) {
      firstFrameScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        sample['animation_first_frame_ms'] = elapsed();
        sample['animation_start_us'] = Timeline.now;
      });
    }
    if (accepted && !controller.active && !landed.isCompleted) {
      sample['landed_ms'] = elapsed();
      landed.complete();
    }
  }

  controller.addListener(changed);
  try {
    if (input == null) {
      controller.request(next);
    } else {
      await input();
    }
    changed();
    await landed.future.timeout(const Duration(seconds: 60));
    if (identical(controller.session.page, origin) == completes) {
      throw StateError(completes ? '翻页未推进正文位置' : '回拖取消却改变正文位置');
    }
  } finally {
    controller.removeListener(changed);
  }
}

Future<void> _pagedDragScenes(int round) async {
  for (final scene in ['drag', 'fling', 'reverse']) {
    if (!_has(scene)) continue;
    for (final next in [true, false]) {
      // 各次输入均从同一章内位置与暖缓存开始，回拖取消不借用上次的落页状态。
      await _jump(_spine);
      final pages = await _session.chapterPages();
      final page = pages[pages.length > 2 ? 2 : pages.length - 1];
      final cfi = _session.cfiAtPageOffset(page, null);
      if (cfi == null) throw StateError('手势基准缺少页首锚点');
      await _session.jumpToCfi(cfi);
      await Future<void>.delayed(const Duration(milliseconds: 700));
      await _measure(scene, round, next, (sample) {
        final box = _view!.context.findRenderObject()! as RenderBox;
        return _pagedTurn(
          sample,
          next,
          completes: scene != 'reverse',
          input: () => dispatchPageTurnDrag(
            box,
            next: next,
            fling: scene == 'fling',
            reverse: scene == 'reverse',
          ),
        );
      });
    }
  }
}

/// 使用正式手势识别器输入；测试与真机测量共用同一轨迹。
Future<void> dispatchPageTurnDrag(
  RenderBox box, {
  required bool next,
  bool fling = false,
  bool reverse = false,
  Duration Function()? timeStamp,
}) async {
  final stamp = timeStamp ?? () => Duration(microseconds: Timeline.now);
  final start = box.localToGlobal(
    Offset(box.size.width * (next ? .88 : .12), box.size.height * .5),
  );
  final steps = fling ? 6 : 24;
  final travel = box.size.width * (next ? -.7 : .7);
  var position = start;
  GestureBinding.instance.handlePointerEvent(
    PointerDownEvent(pointer: 43, position: start, timeStamp: stamp()),
  );
  for (var step = 1; step <= steps; step++) {
    await Future<void>.delayed(const Duration(milliseconds: 16));
    final t = step / steps;
    final fraction = reverse && t > .5 ? 1.9 - 1.8 * t : t * (reverse ? 2 : 1);
    final target = start + Offset(travel * fraction, 0);
    GestureBinding.instance.handlePointerEvent(
      PointerMoveEvent(
        pointer: 43,
        position: target,
        delta: target - position,
        timeStamp: stamp(),
      ),
    );
    position = target;
  }
  GestureBinding.instance.handlePointerEvent(
    PointerUpEvent(pointer: 43, position: position, timeStamp: stamp()),
  );
}

Future<void> _measure(
  String scene,
  int round,
  bool next,
  Future<void> Function(Map<String, Object?>) action,
) async {
  final origin = _session.page!;
  final scrollOrigin = _mode == PageTurnMode.scroll
      ? readScrollPerfPosition(_scroll!)
      : null;
  if (_mode == PageTurnMode.scroll && scrollOrigin == null) {
    throw StateError('采样前滚动视口未就绪');
  }
  final sample = <String, Object?>{
    'mode': _mode.id,
    'wall_start_ms': DateTime.now().millisecondsSinceEpoch,
    'scene': scene,
    'round': round,
    'next': next,
    if (scene == 'cold-cross')
      'cache_condition': '新建阅读页、源与进度存储后的章末首翻；不清系统文件缓存，不等待预热',
    'from': scrollOrigin == null
        ? [origin.spineIndex, origin.pageIndex]
        : [scrollOrigin.spine, scrollOrigin.page],
    if (scrollOrigin != null) 'from_scroll_offset': scrollOrigin.offset,
    'snapshots_before': _view?.snapshotCount,
  };
  ReaderTrace.instance.reset();
  _events = [];
  _eventStart = Timeline.now;
  _samples.start(
    _eventStart,
    refreshRate: View.of(_context).display.refreshRate,
  );
  try {
    await action(sample);
    await WidgetsBinding.instance.endOfFrame;
    final scrollTarget = _mode == PageTurnMode.scroll
        ? await waitForScrollPerfPosition(() => _scroll)
        : null;
    if (_mode == PageTurnMode.scroll && scrollTarget == null) {
      throw StateError('采样结束时滚动视口未就绪');
    }
    sample.addAll({
      'complete_ms': (Timeline.now - _eventStart) / 1000,
      'to': scrollTarget == null
          ? [_session.page!.spineIndex, _session.page!.pageIndex]
          : [scrollTarget.spine, scrollTarget.page],
      if (scrollTarget != null) 'to_scroll_offset': scrollTarget.offset,
      'snapshot_bytes': _view?.snapshotBytes,
      'snapshots_after': _view?.snapshotCount,
    });
  } finally {
    sample['wall_end_ms'] = DateTime.now().millisecondsSinceEpoch;
    sample['frames'] = _samples.finish(
      elapsedMicros: Timeline.now - _eventStart,
      rawFrameTimestampMicros: Timeline.now,
    );
    sample['events'] = _events;
    _events = null;
    sample['trace_us'] = {
      for (final entry
          in ReaderTrace.instance.summary(bookId: 'turn-perf').samples.entries)
        entry.key.name: entry.value,
    };
    _turns.add(sample);
  }
}

Future<void> _scrollScenes(int round) async {
  for (final scene in ['drag', 'fling', 'extend']) {
    if (!_has(scene)) continue;
    await _jump(_spine);
    await _measure(scene, round, true, (sample) async {
      final origin = readScrollPerfPosition(_scroll!)!;
      final loaded = _scroll!.debugLoadedSpineIndices.toSet();
      sample['input_accepted_ms'] = (Timeline.now - _eventStart) / 1000;
      final count = scene == 'extend' ? 12 : 3;
      for (var i = 0; i < count; i++) {
        await _dragScroll(fling: scene != 'drag');
      }
      final target = await waitForScrollPerfPosition(() => _scroll);
      await _scroll!.flushVisiblePosition();
      if (!_scrollPositionMoved(origin, target)) {
        throw StateError('$scene 未推进实际滚动位置');
      }
      if (scene == 'extend' &&
          _scroll!.debugLoadedSpineIndices.every(loaded.contains)) {
        throw StateError('补章场景没有加载新章节');
      }
      sample['loaded_spines'] = _scroll!.debugLoadedSpineIndices;
    });
  }
}

typedef ScrollPerfPosition = ({int spine, int page, double offset});

/// 采样入口以实际渲染盒为准，拒绝仅有会话页而列表尚未布局的状态。
ScrollPerfPosition? readScrollPerfPosition(ContinuousScrollViewState view) {
  if (!view.mounted || view.widget.session.loading) return null;
  final box = view.context.findRenderObject();
  if (box is! RenderBox || !box.attached || !box.hasSize) return null;
  final x = box.size.width / 2;
  // 与生产 _captureVisiblePage 的视口 0 坐标一致；padding.top 已包含在
  // 列表累计高度中，不能再次加到点击坐标。页缝容差沿用 pageAt 的 0.5px。
  final hit = view.pageAt(Offset(x, 0), includeMargins: true);
  if (hit == null ||
      !view.debugLoadedSpineIndices.contains(hit.page.spineIndex)) {
    return null;
  }
  return (
    spine: hit.page.spineIndex,
    page: hit.page.pageIndex,
    offset: hit.localPosition.dy,
  );
}

bool _scrollPositionMoved(ScrollPerfPosition from, ScrollPerfPosition to) =>
    from.spine != to.spine ||
    from.page != to.page ||
    (from.offset - to.offset).abs() > 0.5;

/// 等待实际切片连续三帧稳定；翻屏后裁窗可能还需一轮布局才能再次命中。
/// 开书/跳章额外传入目标页，普通翻屏则读取实际落点，不预设页号。
Future<ScrollPerfPosition> waitForScrollPerfPosition(
  ContinuousScrollViewState? Function() current, {
  int? spine,
  int? page,
}) async {
  final watch = Stopwatch()..start();
  ScrollPerfPosition? previous;
  var stableFrames = 0;
  while (watch.elapsed < const Duration(seconds: 60)) {
    await WidgetsBinding.instance.endOfFrame;
    final view = current();
    final position = view == null ? null : readScrollPerfPosition(view);
    if (position != null &&
        (spine == null || position.spine == spine) &&
        (page == null || position.page == page)) {
      stableFrames =
          previous != null && !_scrollPositionMoved(previous, position)
          ? stableFrames + 1
          : 1;
      if (stableFrames >= 3) return position;
    } else {
      stableFrames = 0;
    }
    previous = position;
  }
  throw TimeoutException('滚动实际视口未稳定在 $spine:$page，最后位置 $previous');
}

Future<void> _dragScroll({required bool fling}) async {
  final box = _scroll!.context.findRenderObject()! as RenderBox;
  final start = box.localToGlobal(
    Offset(box.size.width * .5, box.size.height * .8),
  );
  final steps = fling ? 8 : 40;
  final began = Timeline.now;
  void dispatch(PointerEvent event) =>
      GestureBinding.instance.handlePointerEvent(event);
  dispatch(
    PointerDownEvent(
      pointer: 41,
      position: start,
      timeStamp: Duration(microseconds: began),
    ),
  );
  for (var i = 1; i <= steps; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 16));
    final dy = -box.size.height * .6 / steps;
    dispatch(
      PointerMoveEvent(
        pointer: 41,
        position: start + Offset(0, dy * i),
        delta: Offset(0, dy),
        timeStamp: Duration(microseconds: Timeline.now),
      ),
    );
  }
  dispatch(
    PointerUpEvent(
      pointer: 41,
      position: start + Offset(0, -box.size.height * .6),
      timeStamp: Duration(microseconds: Timeline.now),
    ),
  );
  final moving = _find<ScrollableState>()!.position.isScrollingNotifier;
  if (!moving.value) return;
  final settled = Completer<void>();
  void changed() {
    if (!moving.value && !settled.isCompleted) settled.complete();
  }

  moving.addListener(changed);
  try {
    await settled.future.timeout(const Duration(seconds: 15));
  } finally {
    moving.removeListener(changed);
  }
}

T? _find<T extends State>() {
  T? result;
  void visit(Element element) {
    if (element is StatefulElement && element.state is T) {
      result = element.state as T;
    }
    if (result == null) element.visitChildren(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildren(visit);
  return result;
}

PageTurnViewState? get _view => _find<PageTurnViewState>();
ContinuousScrollViewState? get _scroll => _find<ContinuousScrollViewState>();
ReaderSession? get _sessionOrNull =>
    _view?.controller.session ?? _scroll?.widget.session;
ReaderSession get _session => _sessionOrNull ?? (throw StateError('阅读视口未挂载'));
BuildContext get _context => _view?.context ?? _scroll!.context;

Future<void> _until(bool Function() condition) async {
  final watch = Stopwatch()..start();
  while (!condition()) {
    if (watch.elapsed > const Duration(seconds: 60)) {
      throw TimeoutException(
        '等待正文超时：${_sessionOrNull?.page?.spineIndex}:${_sessionOrNull?.page?.pageIndex} / ${_sessionOrNull?.error}',
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

Future<void> _drainFrames() async {
  for (var attempt = 0; attempt < 25 && !_samples.complete; attempt++) {
    WidgetsBinding.instance.scheduleFrame();
    await WidgetsBinding.instance.endOfFrame;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  _samples.flush();
}

Future<void> _send(String endpoint) async {
  final client = HttpClient();
  try {
    final request = await client.postUrl(Uri.parse('$_server/$endpoint'));
    request.headers.contentType = ContentType.json;
    final bytes = utf8.encode(
      jsonEncode(endpoint == 'background' ? {} : _results),
    );
    request.contentLength = bytes.length;
    request.add(bytes);
    final response = await request.close();
    if (response.statusCode != 204) throw StateError('测量宿主请求失败 $endpoint');
    await response.drain<void>();
  } finally {
    client.close();
  }
}
