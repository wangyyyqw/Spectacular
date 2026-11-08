import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/reader/epub/cancellable_isolate_worker.dart';
import 'package:reader_ui/reader_session.dart';

int _runUntilCancelled(SendPort started) {
  started.send('已启动');
  while (true) {}
}

int _double(int value) => value * 2;

int _fail(int value) => throw StateError('准备失败：$value');

Future<void> _expectReleased(CancellableIsolateWorker worker) async {
  await worker.idle;
  expect(worker.activeIsolates, 0);
  expect(worker.openPortCount, 0);
}

void main() {
  test('真实 isolate 长循环取消后退出并关闭端口', () async {
    final worker = CancellableIsolateWorker();
    final started = ReceivePort();
    addTearDown(worker.close);
    addTearDown(started.close);
    final handle = worker.schedule(
      '长循环',
      () => started.sendPort,
      _runUntilCancelled,
    );

    expect(await started.first, '已启动');
    expect(worker.activeIsolates, 1);
    expect(worker.openPortCount, 1);
    final cancelled = expectLater(
      handle.result,
      throwsA(isA<ChapterLoadCancelled>()),
    );
    handle.cancel();

    await cancelled;
    await _expectReleased(worker);
  });

  test('计算抛错后释放 isolate 和端口且仍可接受新任务', () async {
    final worker = CancellableIsolateWorker();
    addTearDown(worker.close);
    final failed = worker.schedule('失败', () => 7, _fail);

    await expectLater(
      failed.result,
      throwsA(
        isA<StateError>().having((error) => error.message, '错误消息', '准备失败：7'),
      ),
    );
    await _expectReleased(worker);

    expect(await worker.schedule('恢复', () => 21, _double).result, 42);
    await _expectReleased(worker);
  });

  test('同键两个等待者共享计算，取消其中一个仍返回另一结果', () async {
    final worker = CancellableIsolateWorker();
    addTearDown(worker.close);
    var inputReads = 0;
    int input() {
      inputReads += 1;
      return 21;
    }

    final first = worker.schedule('共享', input, _double);
    final second = worker.schedule('共享', input, _double);
    final cancelled = expectLater(
      first.result,
      throwsA(isA<ChapterLoadCancelled>()),
    );
    first.cancel();

    await cancelled;
    expect(await second.result, 42);
    expect(inputReads, 1);
    await _expectReleased(worker);
  });

  test('阅读请求抢占已运行的后台长循环并等待其资源释放', () async {
    final worker = CancellableIsolateWorker();
    final started = ReceivePort();
    addTearDown(worker.close);
    addTearDown(started.close);
    final background = worker.schedule(
      '后台排版',
      () => started.sendPort,
      _runUntilCancelled,
      priority: ChapterLayoutPriority.background,
    );
    expect(await started.first, '已启动');
    final cancelled = expectLater(
      background.result,
      throwsA(isA<ChapterLoadCancelled>()),
    );

    final reading = worker.schedule(
      '阅读',
      () {
        expect(worker.activeIsolates, 0);
        expect(worker.openPortCount, 0);
        return 21;
      },
      _double,
      priority: ChapterLayoutPriority.reading,
    );

    await cancelled;
    expect(await reading.result, 42);
    await _expectReleased(worker);
  });
}
