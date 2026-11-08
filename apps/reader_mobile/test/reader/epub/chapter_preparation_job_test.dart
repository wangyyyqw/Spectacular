import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/reader/epub/chapter_preparation_job.dart';
import 'package:reader_ui/reader_session.dart';

Future<void> _expectCancelled(ChapterPreparationHandle<Object?> handle) =>
    expectLater(handle.result, throwsA(isA<ChapterLoadCancelled>()));

void main() {
  test('取消全部后同键新任务不被旧结果回填或移除', () async {
    final scheduler = ChapterPreparationScheduler();
    addTearDown(scheduler.close);
    final started = Completer<void>();
    final oldResult = Completer<String>();
    final first = scheduler.schedule('同键', (_) {
      started.complete();
      return oldResult.future;
    });
    final second = scheduler.schedule('同键', (_) async => '不应重复执行');
    await started.future;
    final cancelled = Future.wait([
      _expectCancelled(first),
      _expectCancelled(second),
    ]);
    scheduler.cancelAll();
    var replacementRuns = 0;
    final replacement = scheduler.schedule('同键', (_) async {
      replacementRuns += 1;
      return '新结果';
    });
    oldResult.complete('旧结果');

    await cancelled;
    expect(await replacement.result, '新结果');
    expect(replacementRuns, 1);
    await scheduler.idle;
  });

  test('取消阅读等待者后共享任务降为后台并被另一阅读请求抢占', () async {
    final scheduler = ChapterPreparationScheduler();
    addTearDown(scheduler.close);
    final started = Completer<PreparationTask>();
    final gate = Completer<String>();
    final background = scheduler.schedule('共享', (task) {
      started.complete(task);
      return task.waitFuture(gate.future);
    }, priority: ChapterLayoutPriority.background);
    final reading = scheduler.schedule('共享', (_) async => '不应重复执行');
    final task = await started.future;
    expect(task.priority, ChapterLayoutPriority.reading);
    final cancelled = Future.wait([
      _expectCancelled(background),
      _expectCancelled(reading),
    ]);
    final next = scheduler.schedule('另一阅读', (_) async => '新章节');
    expect(task.isActive, isTrue);
    reading.cancel();

    expect(task.priority, ChapterLayoutPriority.background);
    await cancelled;
    expect(await next.result, '新章节');
    await scheduler.idle;
  });

  test('关闭取消运行和排队请求，拒绝新请求且最终进入空闲', () async {
    final scheduler = ChapterPreparationScheduler();
    addTearDown(scheduler.close);
    final started = Completer<void>();
    final gate = Completer<String>();
    final running = scheduler.schedule('运行中', (task) {
      started.complete();
      return task.waitFuture(gate.future);
    });
    await started.future;
    var unexpectedRuns = 0;
    Future<String> unexpected(PreparationTask _) async {
      unexpectedRuns += 1;
      return '不应执行';
    }

    final queued = scheduler.schedule('排队中', unexpected);
    final cancelled = Future.wait([
      _expectCancelled(running),
      _expectCancelled(queued),
    ]);
    scheduler.close();
    final rejected = scheduler.schedule('关闭后', unexpected);

    await cancelled;
    await _expectCancelled(rejected);
    await scheduler.idle;
    expect(unexpectedRuns, 0);
  });

  test('排队任务按阅读、预取、后台的优先级依次执行', () async {
    final scheduler = ChapterPreparationScheduler();
    addTearDown(scheduler.close);
    final started = Completer<void>();
    final gate = Completer<String>();
    final blocker = scheduler.schedule('占位阅读', (_) {
      started.complete();
      return gate.future;
    });
    await started.future;
    final order = <String>[];
    ChapterPreparationHandle<String> enqueue(
      String key,
      ChapterLayoutPriority priority,
    ) => scheduler.schedule(key, (_) async {
      order.add(key);
      return key;
    }, priority: priority);

    final counting = enqueue('后台', ChapterLayoutPriority.background);
    final prefetch = enqueue('预取', ChapterLayoutPriority.prefetch);
    final reading = enqueue('阅读', ChapterLayoutPriority.reading);
    gate.complete('释放槽位');

    expect(await blocker.result, '释放槽位');
    expect(
      await Future.wait([counting.result, prefetch.result, reading.result]),
      ['后台', '预取', '阅读'],
    );
    await scheduler.idle;
    expect(order, ['阅读', '预取', '后台']);
  });
}
