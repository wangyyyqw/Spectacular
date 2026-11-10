import 'dart:async';
import 'dart:convert';
import 'dart:developer' show Timeline;
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:reader_mobile/reader/epub_reader_page.dart';
import 'package:reader_mobile/reader/reader_settings.dart';
import 'package:reader_ui/paging/page_turn_mode.dart';
import 'package:reader_ui/paging/page_turn_view.dart';
import 'package:reader_ui/reader_session.dart';

import 'reader_perf_probe.dart';

/// 使用生产阅读页和控制器，在独立 release 包中重复同一组翻页。
const _server = String.fromEnvironment('PERF_SERVER');
const _rounds = int.fromEnvironment('PERF_ROUNDS', defaultValue: 3);
const _spine = int.fromEnvironment('PERF_SPINE', defaultValue: 10);
final _samples = ReaderPerfProbeSamples();
final _results = <String, Object?>{};
final _turns = <Map<String, Object?>>[];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  WidgetsBinding.instance.addTimingsCallback(_samples.addFrames);
  runApp(const MaterialApp(home: Scaffold(body: Text('准备翻页对比'))));
  try {
    final file = await _download();
    final revision = (await sha256.bind(file.openRead()).first).toString();
    _results.addAll({
      'book_sha256': revision,
      'turns': _turns,
      'contract': {
        'schema': 1,
        'mode': 'simulation3d',
        'input': '调用生产控制器 request；不计触摸识别和 Android 合成延迟',
        'ready': 'origin/target 快照交付时间；complete 为落页后 Flutter 帧',
        'frames': '按 buildStart 归属窗口；16.67ms 为固定参考阈值，并非系统丢帧数',
        'temperature': '原书传输和摘要预读；每轮重建阅读页，系统文件缓存不清空',
        'rounds': _rounds,
      },
    });
    for (var round = 0; round < _rounds; round++) {
      await _runRound(file, revision, round);
    }
    await _drainFrames();
    _results['frame_timings_complete'] = _samples.complete;
    await _send('done');
  } catch (error, stack) {
    _results.addAll({'error': '$error', 'stack': '$stack'});
    await _send('done');
  } finally {
    WidgetsBinding.instance.removeTimingsCallback(_samples.addFrames);
  }
}

Future<File> _download() async {
  final root = await getApplicationSupportDirectory();
  final file = File('${root.path}/page-turn-perf.epub');
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse('$_server/book.epub'));
    final response = await request.close();
    if (response.statusCode != 200) throw StateError('原书传输失败');
    await response.pipe(file.openWrite());
    return file;
  } finally {
    client.close();
  }
}

Future<void> _runRound(File file, String revision, int round) async {
  final store = MemoryReaderProgressStore();
  await store.save(
    'turn-perf',
    const ReaderProgress(spineIndex: _spine, pageIndex: 0),
  );
  runApp(
    MaterialApp(
      home: EpubReaderPage(
        key: ValueKey(round),
        sourcePath: file.path,
        contentRevision: revision,
        bookId: 'turn-perf',
        bookTitle: '格列佛游记',
        store: store,
        settings: ReaderSettings(
          fontSize: double.parse(
            const String.fromEnvironment('PERF_FONT_SIZE', defaultValue: '21'),
          ),
          themeId: 'sepia',
          backgroundId: 'paper',
          pageTurnMode: PageTurnMode.simulation3d,
          keepScreenOn: true,
        ),
      ),
    ),
  );
  await _until(
    () => _viewOrNull()?.controller.session.page?.spineIndex == _spine,
  );
  await WidgetsBinding.instance.endOfFrame;
  // 直接阅读入口没有书库的全书字符权重，不能依赖百分比就绪回调。
  await Future<void>.delayed(const Duration(milliseconds: 250));
  final view = _view;
  _results['viewport'] = {
    'width': view.controller.size.width,
    'height': view.controller.size.height,
    'refresh_rate': View.of(view.context).display.refreshRate,
  };
  await _turn('开书后立即前翻', round, true);
  await Future<void>.delayed(const Duration(milliseconds: 1500));
  for (var index = 0; index < 6; index++) {
    await _turn('连续前翻', round, true);
    await Future<void>.delayed(const Duration(milliseconds: 120));
  }
  for (var index = 0; index < 4; index++) {
    await _turn('连续后翻', round, false);
    await Future<void>.delayed(const Duration(milliseconds: 120));
  }
  await _crossChapter(round);
  for (final spine in [19, 33]) {
    await _view.controller.session.jumpToChapter(spine);
    await WidgetsBinding.instance.endOfFrame;
    await _turn('远跳$spine后立即前翻', round, true);
  }
  // 留出观察落页和后台补图的窗口；最后一轮保留阅读画面。
  await Future<void>.delayed(const Duration(seconds: 4));
  await _send('sample');
}

Future<void> _crossChapter(int round) async {
  final session = _view.controller.session;
  await session.jumpToChapter(_spine);
  final pages = await session.chapterPages();
  final cfi = session.cfiAtPageOffset(pages.last, null);
  if (cfi == null) throw StateError('章末缺少定位锚点');
  await session.jumpToCfi(cfi);
  await WidgetsBinding.instance.endOfFrame;
  if (session.page?.pageIndex != pages.last.pageIndex) {
    throw StateError('章末定位不一致');
  }
  await Future<void>.delayed(const Duration(milliseconds: 700));
  await _turn('章末跨章前翻', round, true);
  await Future<void>.delayed(const Duration(milliseconds: 120));
  await _turn('章首跨章后翻', round, false);
}

Future<void> _turn(String scene, int round, bool next) async {
  final view = _view;
  final controller = view.controller;
  final origin = controller.session.page!;
  final sample = <String, Object?>{
    'scene': scene,
    'round': round,
    'next': next,
    'from': [origin.spineIndex, origin.pageIndex],
    'snapshots_before': view.snapshotCount,
  };
  final watch = Stopwatch()..start();
  _samples.start(Timeline.now);
  final timer = Timer.periodic(const Duration(milliseconds: 4), (_) {
    _samples.tick(watch.elapsedMicroseconds);
  });
  void changed() {
    if (controller.originImage != null) {
      sample.putIfAbsent(
        'origin_ready_ms',
        () => watch.elapsedMicroseconds / 1000,
      );
    }
    if (controller.targetImage != null) {
      sample.putIfAbsent(
        'target_ready_ms',
        () => watch.elapsedMicroseconds / 1000,
      );
    }
  }

  controller.addListener(changed);
  try {
    controller.request(next);
    await _until(
      () => !controller.active && !identical(controller.session.page, origin),
    );
    await WidgetsBinding.instance.endOfFrame;
    sample['complete_ms'] = watch.elapsedMicroseconds / 1000;
    sample['to'] = [
      controller.session.page!.spineIndex,
      controller.session.page!.pageIndex,
    ];
    sample['snapshot_bytes'] = view.snapshotBytes;
  } finally {
    timer.cancel();
    controller.removeListener(changed);
    sample['frames'] = _samples.finish(
      elapsedMicros: watch.elapsedMicroseconds,
      rawFrameTimestampMicros: Timeline.now,
    );
    _turns.add(sample);
  }
}

PageTurnViewState get _view => _viewOrNull() ?? (throw StateError('阅读视口未挂载'));

PageTurnViewState? _viewOrNull() {
  PageTurnViewState? result;
  void visit(Element element) {
    if (element is StatefulElement && element.state is PageTurnViewState) {
      result = element.state as PageTurnViewState;
    }
    element.visitChildren(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildren(visit);
  return result;
}

Future<void> _until(bool Function() condition) async {
  final watch = Stopwatch()..start();
  while (!condition()) {
    if (watch.elapsed > const Duration(seconds: 60)) {
      final controller = _viewOrNull()?.controller;
      throw TimeoutException(
        '等待翻页或正文超时：${controller?.phase} / '
        '${controller?.session.page?.spineIndex}:${controller?.session.page?.pageIndex} / '
        '${controller?.session.error}',
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
}

Future<void> _drainFrames() async {
  for (var attempt = 0; attempt < 20 && !_samples.complete; attempt++) {
    WidgetsBinding.instance.scheduleFrame();
    await WidgetsBinding.instance.endOfFrame;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

Future<void> _send(String endpoint) async {
  final client = HttpClient();
  try {
    final request = await client.postUrl(Uri.parse('$_server/$endpoint'));
    request.headers.contentType = ContentType.json;
    final bytes = utf8.encode(jsonEncode(_results));
    request.contentLength = bytes.length;
    request.add(bytes);
    final response = await request.close();
    if (response.statusCode != 204) throw StateError('保存测量结果失败');
    await response.drain<void>();
  } finally {
    client.close();
  }
}
