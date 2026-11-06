import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/perf/trace.dart';
import 'package:reader_mobile/reader/epub_chapter_source.dart';
import 'package:reader_ui/panels/settings_panel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final book = File('../../test_corpus/real/zhushen-yuxi.epub');

  test(
    '真实书打开、目录首访、缓存与索引重放耗时',
    () async {
      final watch = Stopwatch()..start();
      final bytes = book.readAsBytesSync();
      final report = <String, Object>{
        'readMs': watch.elapsedMicroseconds / 1000,
      };
      watch.reset();
      final source = await EpubChapterSource.open(bytes, verifyCrc: false);
      report['openMs'] = watch.elapsedMicroseconds / 1000;
      await source.applyOverrides(ReaderSettingsDefaults.overrides);
      await source.applyContentSize(width: 344, height: 700);
      final pageCounts = <int, int>{};
      for (final phase in ['first', 'cached', 'replay']) {
        if (phase == 'replay') source.clearPaginationCache();
        final samples = <String, Object>{};
        for (final spine in [29, 30, 47]) {
          watch.reset();
          final pages = await source.loadChapter(spine);
          samples['$spine'] = {
            'ms': watch.elapsedMicroseconds / 1000,
            'pages': pages.length,
          };
          pageCounts.putIfAbsent(spine, () => pages.length);
          expect(pages.length, pageCounts[spine]);
        }
        report[phase] = samples;
      }
      report['cacheReport'] = source.cacheReport;
      final trace = ReaderTrace.instance.summary();
      report['trace'] = {
        for (final name in [
          ReaderTraceName.chapterStructure,
          ReaderTraceName.chapterStyles,
          ReaderTraceName.chapterAggregate,
          ReaderTraceName.chapterCollect,
          ReaderTraceName.chapterTables,
          ReaderTraceName.chapterPagination,
          ReaderTraceName.chapterLayout,
        ])
          name.name: {
            'count': trace.counts[name] ?? 0,
            'averageMs': trace.averageMs(name),
            'maxMs': trace.maxMs(name),
            'p95Ms': trace.p95Ms(name),
          },
      };
      final encoded = const JsonEncoder.withIndent('  ').convert(report);
      const reportPath = String.fromEnvironment('EPUB_BENCHMARK_REPORT');
      if (reportPath.isNotEmpty) await File(reportPath).writeAsString(encoded);
      // 仅显式运行基准时输出；不以易受机器负载影响的毫秒阈值断言正确性。
      // ignore: avoid_print
      print(encoded);
    },
    skip:
        !const bool.fromEnvironment('RUN_REAL_BOOK_BENCHMARK') ||
        !book.existsSync(),
  );
}
