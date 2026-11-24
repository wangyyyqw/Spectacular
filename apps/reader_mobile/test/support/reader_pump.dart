import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/home/startup_splash.dart';

/// 等开屏动画结束；开屏期间会拦截点击。
Future<void> pumpStartupFinished(WidgetTester tester) async {
  for (var frame = 0; frame < 40; frame++) {
    if (find.byType(StartupSplash).evaluate().isEmpty) return;
    await tester.pump(const Duration(milliseconds: 40));
  }
}

/// 同时交付假时钟回调与真实 IO，再返回原任务结果或原错误。
Future<T> pumpReaderTask<T>(WidgetTester tester, Future<T> task) async {
  var completed = false;
  late T result;
  Object? failure;
  StackTrace? failureStack;
  unawaited(
    task.then<void>(
      (value) {
        result = value;
        completed = true;
      },
      onError: (Object error, StackTrace stack) {
        failure = error;
        failureStack = stack;
        completed = true;
      },
    ),
  );
  await pumpReaderUntilComplete(tester, () => completed);
  if (failure != null) Error.throwWithStackTrace(failure!, failureStack!);
  return result;
}

/// 真实 isolate 解析需要事件循环；仅推进测试假时钟不能交付 isolate 消息。
Future<void> pumpReaderUntil(
  WidgetTester tester,
  Finder ready, {
  int maxFrames = 80,
}) async {
  await pumpReaderUntilComplete(
    tester,
    () => ready.evaluate().isNotEmpty,
    description: '$ready',
    maxFrames: maxFrames,
  );
  await pumpStartupFinished(tester);
}

/// 落盘队列同时包含测试区与真实 IO 区的 Future，两侧都需交付事件。
Future<void> pumpReaderUntilComplete(
  WidgetTester tester,
  bool Function() isComplete, {
  String description = '阅读异步任务',
  int maxFrames = 80,
}) async {
  for (var frame = 0; frame < maxFrames; frame++) {
    await tester.pump(const Duration(milliseconds: 16));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    if (isComplete()) {
      await tester.pump();
      return;
    }
  }
  fail('$description 未在 $maxFrames 帧内完成');
}
