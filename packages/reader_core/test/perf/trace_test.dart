import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/perf/trace.dart';

void main() {
  group('性能埋点（P4-31，§44）', () {
    setUp(() => ReaderTrace.instance = ReaderTrace(capacity: 64));
    tearDown(() => ReaderTrace.instance = ReaderTrace());

    test('计时记录：耗时进采样，平均/最大可算', () {
      final trace = ReaderTrace.instance;
      final handle = trace.start(ReaderTraceName.chapterLayout, bookId: 'book-1');
      handle.stop();
      trace.record(
        ReaderTraceName.chapterLayout,
        2000,
        bookId: 'book-1',
      );
      trace.record(
        ReaderTraceName.chapterLayout,
        4000,
        bookId: 'book-1',
      );
      final summary = trace.summary(bookId: 'book-1');
      expect(summary.counts[ReaderTraceName.chapterLayout], 3);
      expect(summary.maxMs(ReaderTraceName.chapterLayout), 4);
      expect(summary.averageMs(ReaderTraceName.chapterLayout), greaterThan(0));
      expect(summary.p95Ms(ReaderTraceName.chapterLayout), greaterThan(0));
    });

    test('按书聚合：不同书互不混淆', () {
      final trace = ReaderTrace.instance;
      trace.record(ReaderTraceName.bookOpen, 500000, bookId: 'a');
      trace.record(ReaderTraceName.pageRenderReuse, 3000, bookId: 'b');
      expect(trace.summary(bookId: 'a').counts[ReaderTraceName.bookOpen], 1);
      expect(
        trace.summary(bookId: 'b').counts[ReaderTraceName.pageRenderReuse],
        1,
      );
      expect(trace.summary(bookId: 'a').counts[ReaderTraceName.chapterLayout], isNull);
    });

    test('页缓存命中率 = 命中 /（命中 + 未命中）', () {
      final trace = ReaderTrace.instance;
      for (var i = 0; i < 3; i++) {
        trace.count(ReaderTraceCounter.pageCacheHit, bookId: 'c');
      }
      trace.count(ReaderTraceCounter.pageCacheMiss, bookId: 'c');
      trace.record(ReaderTraceName.chapterLayout, 1000, bookId: 'c');
      final summary = trace.summary(bookId: 'c');
      expect(summary.pageCacheHitRate, closeTo(0.75, 0.001));
    });

    test('采样上限：capacity 之外丢最旧的', () {
      final trace = ReaderTrace(capacity: 4);
      for (var i = 0; i < 10; i++) {
        trace.record(ReaderTraceName.pageRenderBuild, i, bookId: 'd');
      }
      expect(trace.summary(bookId: 'd').counts[ReaderTraceName.pageRenderBuild], 4);
    });

    test('开销：一万次记录远低于 1ms/次（P4-31 验收）', () {
      final trace = ReaderTrace(capacity: 512);
      final watch = Stopwatch()..start();
      for (var i = 0; i < 10000; i++) {
        trace.record(ReaderTraceName.pageRenderBuild, i, bookId: 'e');
      }
      watch.stop();
      final perRecordMs = watch.elapsedMicroseconds / 10000 / 1000;
      expect(
        perRecordMs,
        lessThan(1.0),
        reason: '单次记录 ${perRecordMs.toStringAsFixed(4)}ms',
      );
    });

    test('stop 幂等：重复 stop 不会重复记录', () {
      final trace = ReaderTrace.instance;
      final handle = trace.start(ReaderTraceName.fontLoad, bookId: 'f');
      handle.stop();
      handle.stop();
      expect(trace.summary(bookId: 'f').counts[ReaderTraceName.fontLoad], 1);
    });

    test('reset 清空全部', () {
      final trace = ReaderTrace.instance;
      trace.record(ReaderTraceName.import, 1000, bookId: 'g');
      trace.reset();
      expect(trace.summary(bookId: 'g').counts, isEmpty);
    });
  });
}
