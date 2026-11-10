import 'dart:ui' show FrameTiming;

import 'package:flutter_test/flutter_test.dart';

import '../integration_test/reader_perf_probe.dart';

void main() {
  test('结束事件时结算最后一次 tick 后的间隔', () {
    final samples = ReaderPerfProbeSamples()..start(1000);
    samples.tick(4000);
    samples.tick(8000);

    final result = samples.finish(
      elapsedMicros: 23500,
      rawFrameTimestampMicros: 25000,
    );

    expect(result['longest_ui_gap_ms'], 15.5);
    expect(result['longest_build_ms'], 0.0);
    expect(result['longest_raster_ms'], 0.0);
    expect(result['frame_count'], 0);
    expect(result['frame_timings_complete'], isFalse);
  });

  test('延迟批次更新旧结果且当前事件只累计自身帧', () {
    final samples = ReaderPerfProbeSamples()..start(1000);
    final previous = samples.finish(
      elapsedMicros: 1000,
      rawFrameTimestampMicros: 2000,
    );
    samples.start(3000);
    samples.addFrames([
      _frame(1000, build: 9000),
      _frame(1500, build: 500, raster: 800),
      _frame(2000, build: 700, raster: 600),
      _frame(2500, build: 9000),
      _frame(3500, build: 200, raster: 300),
    ]);

    expect(previous['frame_count'], 2);
    expect(previous['longest_build_ms'], 0.7);
    expect(previous['longest_raster_ms'], 0.8);
    expect(previous['raster_p95_ms'], 0.8);
    expect(previous['frames_over_16_67_ms'], 0);
    expect(previous['frame_timings_complete'], isTrue);
    expect(samples.complete, isFalse, reason: '当前事件仍在进行');

    final current = samples.finish(
      elapsedMicros: 1000,
      rawFrameTimestampMicros: 4000,
    );
    expect(current['frame_count'], 1);
    expect(current['longest_build_ms'], 0.2);
    expect(current['longest_raster_ms'], 0.3);
    expect(current['frame_timings_complete'], isFalse);

    samples.addFrames([_frame(4000, build: 400, raster: 100)]);
    expect(current['frame_count'], 2);
    expect(current['longest_build_ms'], 0.4);
    expect(previous['frame_count'], 2);
    expect(samples.complete, isTrue);
  });

  test('已有事件帧仍须等到结束边界的帧才算完整', () {
    final samples = ReaderPerfProbeSamples();
    expect(samples.complete, isTrue);
    samples.start(1000);
    samples.addFrames([_frame(1500)]);
    final result = samples.finish(
      elapsedMicros: 1000,
      rawFrameTimestampMicros: 2000,
    );
    expect(result['frame_count'], 1);
    expect(result['frame_timings_complete'], isFalse);

    samples.addFrames([_frame(1999)]);
    expect(result['frame_timings_complete'], isFalse);
    samples.addFrames([_frame(2000)]);
    expect(result['frame_count'], 3);
    expect(result['frame_timings_complete'], isTrue);
    expect(samples.complete, isTrue);
  });

  test('P95 使用最近秩且固定阈值统计真实窗口内的帧', () {
    final samples = ReaderPerfProbeSamples()..start(0);
    samples.addFrames([
      for (var index = 1; index <= 20; index++)
        _frame(index * 1000, raster: index * 1000),
    ]);
    final result = samples.finish(
      elapsedMicros: 20000,
      rawFrameTimestampMicros: 20000,
    );
    expect(result['raster_p95_ms'], 19);
    expect(result['frames_over_16_67_ms'], 4);
    expect(result['frame_count'], 20);
  });

  test('观察到后续帧但事件内无帧时不误报完整', () {
    final samples = ReaderPerfProbeSamples()..start(1000);
    final result = samples.finish(
      elapsedMicros: 1000,
      rawFrameTimestampMicros: 2000,
    );
    samples.addFrames([_frame(2500)]);
    expect(result['frame_count'], 0);
    expect(result['frame_timings_complete'], isFalse);
    expect(samples.complete, isFalse);

    samples.addFrames([_frame(1500)]);
    expect(result['frame_count'], 1);
    expect(result['frame_timings_complete'], isTrue);
    expect(samples.complete, isTrue);
  });

  test('多个已结束窗口接收乱序批次且共享边界只归属前一事件', () {
    final samples = ReaderPerfProbeSamples()..start(1000);
    final first = samples.finish(
      elapsedMicros: 1000,
      rawFrameTimestampMicros: 2000,
    );
    samples.start(2000);
    final second = samples.finish(
      elapsedMicros: 1000,
      rawFrameTimestampMicros: 3000,
    );
    samples.start(4000);
    final third = samples.finish(
      elapsedMicros: 1000,
      rawFrameTimestampMicros: 5000,
    );

    samples.addFrames([
      _frame(5000),
      _frame(2000),
      _frame(4500),
      _frame(1000),
      _frame(3000),
      _frame(3500),
      _frame(4000),
      _frame(2500),
      _frame(6000),
    ]);

    expect(first['frame_count'], 1);
    expect(second['frame_count'], 2);
    expect(third['frame_count'], 2);
    expect(samples.complete, isTrue);
  });
}

FrameTiming _frame(int buildStart, {int build = 100, int raster = 100}) =>
    FrameTiming(
      vsyncStart: buildStart - 100,
      buildStart: buildStart,
      buildFinish: buildStart + build,
      rasterStart: buildStart + build,
      rasterFinish: buildStart + build + raster,
      rasterFinishWallTime: buildStart + build + raster,
    );
