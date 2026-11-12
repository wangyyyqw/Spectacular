import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/editing/epub_editing.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/epub/epub_chapter_source.dart';
import 'package:reader_core/epub/chapter/chapter_layout_cache.dart';
import 'package:reader_core/epub/chapter/chapter_preview_cache.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/source/format_opener.dart';

const _enabled = bool.fromEnvironment('RUN_EDITOR_STRESS');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    '144 MiB 单章 200 页编辑、预览、图片和流式导出',
    () async {
      final input = File(
        const String.fromEnvironment(
          'STRESS_EPUB',
          defaultValue: '../../apps/reader_mobile/dist/performance-stress.epub',
        ),
      );
      final report = <String, Object?>{
        'platform': Platform.operatingSystem,
        'contract': '本地 Flutter 测试进程，非真机帧率',
        'fileBytes': input.lengthSync(),
      };
      final temporary = await Directory.systemTemp.createTemp('editor-stress-');
      EpubEditSession? session;
      EpubChapterSource? preview;
      var maximumGap = 0;
      var lastTick = DateTime.now().microsecondsSinceEpoch;
      final probe = Timer.periodic(const Duration(milliseconds: 8), (_) {
        final now = DateTime.now().microsecondsSinceEpoch;
        if (now - lastTick > maximumGap) maximumGap = now - lastTick;
        lastTick = now;
      });
      Future<T> measure<T>(String name, FutureOr<T> Function() action) =>
          _measureStage(report, name, action);
      try {
        session = await measure('openMs', () => EpubEditSession.open(input));
        final active = session!;
        final path = active.spinePaths[1];
        final original = active.readText(path);
        final filesBefore = temporary.listSync().length;
        await measure('continuousInputMs', () {
          for (var i = 0; i < 20; i++) {
            ClassStyleEditor(active)
                .writeSource(path, original.replaceFirst('本节结束', '第 $i 次编辑结束'));
          }
        });
        expect(
          temporary.listSync().length,
          filesBefore,
          reason: '输入期间不得重新打包整本 EPUB',
        );
        final inspection = await measure(
          'classStyleInspectMs',
          () => inspectClassStyleAsync(
            active,
            'note',
            proposed: {'color': '#246813'},
          ),
        );
        report['classStyleTargets'] = inspection.elementCount;
        await measure(
          'classStyleMs',
          () => applyClassStyleAsync(active, 'note', {
            'color': '#246813',
          }, unifyConflicts: true),
        );
        preview = await measure(
          'previewOpenMs',
          () => active.createPreviewSource(
            options: const ReaderOpenOptions(
              contentWidth: 360,
              contentHeight: 600,
            ),
          ),
        );
        await preview!.applyOverrides(const ReaderOverrides(fontSize: 18));
        final pages = await measure(
          'previewLayoutMs',
          () => preview!.loadChapter(1),
        );
        report['pageCount'] = pages.length;
        expect(pages.length, greaterThanOrEqualTo(200));
        for (var round = 1; round <= 3; round++) {
          preview = await _checkPreviewReuse(
            active,
            preview!,
            pages,
            report,
            round,
          );
        }
        _checkCacheBounds(active, report);
        final image = active.resources.firstWhere(
          (r) => r.mediaType == 'image/png',
        );
        final bytes = active.readBytes(image.path)!;
        await measure(
          'imageReplaceMs',
          () => active.transaction(
            '替换图片',
            (tx) => tx.writeBytes(image.path, bytes),
          ),
        );
        final exported = File('${temporary.path}/edited.epub');
        await measure('writeMs', () => EpubWriter.write(active, exported));
        final reopened = await measure(
          'reopenMs',
          () => EpubEditSession.open(exported),
        );
        expect(reopened.readText(path), contains('第 19 次编辑结束'));
        expect(reopened.readBytes(image.path), bytes);
        final css = reopened.metadata['classStylesheet'] as String;
        expect(reopened.readText(css), contains('#246813'));
        reopened.close();
        final blobs = <String, Uint8List>{};
        final draft = active.toDraft(
          storeBlob: (path, bytes) {
            blobs[path] = bytes;
            return path;
          },
        );
        final restored = await EpubEditSession.open(
          input,
          draft: draft,
          readBlob: (reference) => blobs[reference]!,
        );
        expect(restored.readText(path), active.readText(path));
        restored.close();
        report['rssBytes'] = ProcessInfo.currentRss;
        report['maxRssBytes'] = ProcessInfo.maxRss;
        report['maximumEventLoopGapMs'] = maximumGap / 1000;
        report['changedResources'] = active.changedPaths.length;
        report['outputBytes'] = exported.lengthSync();
      } finally {
        probe.cancel();
        preview?.close();
        session?.close();
        final output = File(
          '../../apps/reader_mobile/dist/epub-editor-stress.json',
        );
        await output.parent.create(recursive: true);
        await output.writeAsString(
          const JsonEncoder.withIndent('  ').convert(report),
        );
        await temporary.delete(recursive: true);
      }
    },
    skip: !_enabled,
    timeout: const Timeout(Duration(minutes: 8)),
  );
}

Future<EpubChapterSource> _checkPreviewReuse(
  EpubEditSession session,
  EpubChapterSource previous,
  List<PageContent> pages,
  Map<String, Object?> report,
  int round,
) async {
  final path = session.spinePaths[0];
  session.transaction(
    '只改封面章正文',
    (tx) => tx.writeText(
      path,
      session
          .readText(path)
          .replaceFirst('</body>', '<p>缓存切换 $round</p></body>'),
    ),
  );
  previous.close();
  await previous.preparationsStopped;
  final next = await _measureStage(
    report,
    'previewReuseOpen${round}Ms',
    () => _previewForStress(session),
  );
  try {
    final reused = await _measureStage(
      report,
      'previewReuseLayout${round}Ms',
      () => next.loadChapter(1),
    );
    expect(reused.length, greaterThanOrEqualTo(200));
    expect(identical(reused, pages), isTrue);
    expect(next.anchorPreparationCount, 0);
    expect(next.chapterLayoutCount, 0);
    report['previewCacheSwitches'] = round;
    return next;
  } catch (_) {
    next.close();
    await next.preparationsStopped;
    rethrow;
  }
}

Future<EpubChapterSource> _previewForStress(EpubEditSession session) async {
  final source = await session.createPreviewSource(
    options: const ReaderOpenOptions(contentWidth: 360, contentHeight: 600),
  );
  await source.applyOverrides(const ReaderOverrides(fontSize: 18));
  return source;
}

void _checkCacheBounds(EpubEditSession session, Map<String, Object?> report) {
  final layouts = ChapterLayoutCache.recent;
  expect(
    session.previewCacheEntryCount,
    lessThanOrEqualTo(ChapterPreviewCache.maxEntries),
  );
  expect(layouts.length, lessThanOrEqualTo(ChapterLayoutCache.maxEntries));
  expect(
    layouts.estimatedBytes,
    lessThanOrEqualTo(ChapterLayoutCache.maxBytes),
  );
  report['previewStructureEntries'] = session.previewCacheEntryCount;
  report['previewCompletedEntries'] = layouts.length;
  report['previewCompletedBytes'] = layouts.estimatedBytes;
}

/// 与界面使用相同异步入口，单独记录每个阶段的事件循环间隔。
Future<T> _measureStage<T>(
  Map<String, Object?> report,
  String name,
  FutureOr<T> Function() action,
) async {
  final watch = Stopwatch()..start();
  final gaps = <int>[];
  var previous = 0;
  final timer = Timer.periodic(const Duration(milliseconds: 8), (_) {
    final now = watch.elapsedMicroseconds;
    gaps.add(now - previous);
    previous = now;
  });
  try {
    final result = await action();
    report[name] = watch.elapsedMicroseconds / 1000;
    await Future<void>.delayed(const Duration(milliseconds: 10));
    gaps.sort();
    final label = name.replaceFirst(RegExp(r'Ms$'), '');
    report['${label}EventLoopMaxMs'] = gaps.isEmpty ? 0 : gaps.last / 1000;
    report['${label}EventLoopP95Ms'] = gaps.isEmpty
        ? 0
        : gaps[((gaps.length * 0.95).ceil() - 1).clamp(0, gaps.length - 1)] /
              1000;
    report['${label}HeartbeatSamples'] = gaps.length;
    return result;
  } finally {
    timer.cancel();
  }
}
