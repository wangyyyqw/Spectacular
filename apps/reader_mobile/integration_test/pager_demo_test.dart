import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:reader_mobile/prototype/pager_demo.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('200 页快速翻页的帧耗时', (tester) async {
    final timings = <FrameTiming>[];
    SchedulerBinding.instance.addTimingsCallback(timings.addAll);

    await tester.pumpWidget(const MaterialApp(home: PagerDemoPage()));
    await tester.pumpAndSettle();

    for (var i = 0; i < 200; i++) {
      await tester.fling(find.byType(PageView), const Offset(-400, 0), 1500);
      await tester.pump(const Duration(milliseconds: 250));
    }
    await tester.pump(const Duration(seconds: 1));

    expect(timings, isNotEmpty);
    final totalMs = timings
        .map((timing) => timing.totalSpan.inMicroseconds / 1000)
        .toList(growable: false);
    totalMs.sort();
    final maxMs = totalMs.last;
    final p95Ms =
        totalMs[(totalMs.length * 0.95).floor().clamp(0, totalMs.length - 1)];
    final medianMs = totalMs[totalMs.length ~/ 2];

    var consecutiveLong = 0;
    var maxConsecutiveLong = 0;
    for (final timing in timings) {
      final ms = timing.totalSpan.inMicroseconds / 1000;
      if (ms > 16) {
        consecutiveLong++;
        maxConsecutiveLong = math.max(maxConsecutiveLong, consecutiveLong);
      } else {
        consecutiveLong = 0;
      }
    }

    // ignore: avoid_print
    print(
      'P0-15 frames=${timings.length} median_ms=${medianMs.toStringAsFixed(1)} '
      'p95_ms=${p95Ms.toStringAsFixed(1)} max_ms=${maxMs.toStringAsFixed(1)} '
      'max_consecutive_over_16ms=$maxConsecutiveLong '
      'builder=${tester.binding.runtimeType}',
    );

    expect(maxConsecutiveLong, lessThan(3));
  });
}
