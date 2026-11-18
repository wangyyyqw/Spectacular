import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/scheduler.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/epub/epub_document.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/text/reader_text_overlay.dart';
import 'package:reader_core/epub/chapter/book_fonts.dart';
import 'package:reader_core/epub/chapter/book_resources.dart';
import 'package:reader_core/epub/chapter/chapter_layout_job.dart';

import '../support/css_chapter_book.dart';

import 'package:reader_core/source/chapter_source.dart';

late BookFontView _fonts;

LayoutSnapshot _snapshot(String key, {int generation = 1}) => LayoutSnapshot(
  spineIndex: 0,
  key: key,
  contentVersion: '调度测试',
  generation: generation,
  width: 320,
  height: 480,
  pageHeight: 480,
  topInset: 0,
  baseStyle: ComputedStyle(const {'font-size': '16px'}),
  overrides: const ReaderOverrides(),
  textOverlays: ReaderTextOverlayResolver(const []),
  fontDependency: _fonts.dependency(const {}),
  fonts: _fonts,
  fontFamilies: const {},
  trimTextEdges: true,
);

List<PageContent> _pages() => [
  PageContent(
    spineIndex: 0,
    pageIndex: 0,
    slices: const [],
    usedHeight: 0,
    pageHeight: 480,
    topPadding: 0,
  ),
];

class _LayoutQueueProbe {
  final committed = <String>[];
  final finished = <String>[];
  late LayoutBudget runningBudget;
  late final scheduler = ChapterLayoutScheduler(
    isCurrent: (_) => true,
    run: _run,
    onFinished: (snapshot) => finished.add(snapshot.key),
  );

  ChapterLoadHandle request(String key, ChapterLayoutPriority priority) =>
      scheduler.schedule(
        _snapshot(key),
        priority: priority,
        retainResult: false,
      );

  Future<List<PageContent>> _run(
    LayoutSnapshot snapshot,
    LayoutBudget budget,
    bool Function() retain,
  ) async {
    if (snapshot.key == '共享') {
      runningBudget = budget;
      await budget.checkpoint(force: true);
    }
    budget.check();
    committed.add(snapshot.key);
    return _pages();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final document = (await openEpub(
      buildCssChapterBook(body: '<p>调度</p>'),
      verifyCrc: false,
    )).document!;
    final resources = BookResources(document);
    final fonts = BookFonts(resources, onFontsChanged: (_) {});
    _fonts = fonts.freeze();
    fonts.close();
    resources.close();
  });

  test('同键共享一次作业，取消一个等待者不影响另外两个', () async {
    final gate = Completer<void>();
    final pages = _pages();
    var runs = 0;
    final scheduler = ChapterLayoutScheduler(
      isCurrent: (_) => true,
      run: (_, budget, retain) async {
        runs += 1;
        await gate.future;
        budget.check();
        return pages;
      },
    );
    addTearDown(scheduler.close);
    final first = scheduler.schedule(
      _snapshot('共享'),
      priority: ChapterLayoutPriority.reading,
      retainResult: true,
    );
    final second = scheduler.schedule(
      _snapshot('共享'),
      priority: ChapterLayoutPriority.reading,
      retainResult: true,
    );
    final third = scheduler.schedule(
      _snapshot('共享'),
      priority: ChapterLayoutPriority.prefetch,
      retainResult: false,
    );
    first.cancel();
    await expectLater(first.result, throwsA(isA<ChapterLoadCancelled>()));
    gate.complete();
    expect(await second.result, same(pages));
    expect(await third.result, same(pages));
    expect(runs, 1);
    expect(scheduler.contains('共享'), isFalse);
  });

  test('没有稳定首页时总数只更新元数据，不提前交付空首批', () async {
    final gate = Completer<void>();
    final pages = _pages();
    final scheduler = ChapterLayoutScheduler(
      isCurrent: (_) => true,
      run: (_, budget, _) async {
        budget.publishPageCount!(pages.length);
        await gate.future;
        return pages;
      },
    );
    addTearDown(scheduler.close);
    final handle = scheduler.schedule(
      _snapshot('无前缀总数'),
      priority: ChapterLayoutPriority.reading,
      retainResult: true,
      progressive: true,
    );
    var firstReady = false;
    unawaited(handle.firstPages.then((_) => firstReady = true));
    await Future<void>.delayed(Duration.zero);
    expect(handle.pageCount, 1);
    expect(firstReady, isFalse);
    expect(handle.availablePages, isEmpty);
    expect(handle.isComplete, isFalse);
    gate.complete();
    expect(await handle.firstPages, same(pages));
    expect(await handle.result, same(pages));
  });

  test('首页交付后余章降级，同键前台接管与取消不会重启作业', () async {
    final gate = Completer<void>();
    final first = _pages();
    var runs = 0;
    late LayoutBudget budget;
    final scheduler = ChapterLayoutScheduler(
      isCurrent: (_) => true,
      run: (_, current, retain) async {
        runs += 1;
        budget = current;
        current.publishPages!(first);
        await gate.future;
        current.check();
        return first;
      },
    );
    addTearDown(scheduler.close);
    final initial = scheduler.schedule(
      _snapshot('渐进'),
      priority: ChapterLayoutPriority.prefetch,
      retainResult: true,
      progressive: true,
    );
    expect(await initial.firstPages, same(first));
    expect(budget.priority, ChapterLayoutPriority.background);
    final replay = scheduler.schedule(
      _snapshot('渐进'),
      priority: ChapterLayoutPriority.prefetch,
      retainResult: true,
      progressive: true,
    );
    expect(await replay.firstPages, same(first));
    expect(budget.token.isCancelled, isFalse, reason: '同键重放不能抢占自己的后台作业');
    initial.setPriority(ChapterLayoutPriority.reading);
    expect(budget.priority, ChapterLayoutPriority.reading);
    final full = scheduler.schedule(
      _snapshot('渐进'),
      priority: ChapterLayoutPriority.reading,
      retainResult: true,
    );
    expect(await full.firstPages, same(first));
    initial.cancel();
    expect(initial.isComplete, isFalse, reason: '取消不代表完整章节就绪');
    expect(budget.token.isCancelled, isFalse);
    gate.complete();
    expect(await full.result, same(first));
    expect(await replay.result, same(first));
    expect(runs, 1);
  });

  test('保留页面的等待者取消后，剩余后台等待者不常驻完整结果', () async {
    final gate = Completer<void>();
    bool? retained;
    ChapterLayoutPriority? priority;
    final scheduler = ChapterLayoutScheduler(
      isCurrent: (_) => true,
      run: (_, budget, retain) async {
        await gate.future;
        budget.check();
        retained = retain();
        priority = budget.priority;
        return _pages();
      },
    );
    addTearDown(scheduler.close);
    final reading = scheduler.schedule(
      _snapshot('降级'),
      priority: ChapterLayoutPriority.reading,
      retainResult: true,
    );
    final counting = scheduler.schedule(
      _snapshot('降级'),
      priority: ChapterLayoutPriority.background,
      retainResult: false,
    );
    reading.cancel();
    await expectLater(reading.result, throwsA(isA<ChapterLoadCancelled>()));
    gate.complete();
    expect(await counting.result, hasLength(1));
    expect(retained, isFalse);
    expect(priority, ChapterLayoutPriority.background);
  });

  for (final priority in [
    ChapterLayoutPriority.prefetch,
    ChapterLayoutPriority.reading,
  ]) {
    test('共享阅读取消后已排队的 ${priority.name} 抢占降级作业', () async {
      final probe = _LayoutQueueProbe();
      addTearDown(probe.scheduler.close);
      final reading = probe.request('共享', ChapterLayoutPriority.reading);
      final counting = probe.request('共享', ChapterLayoutPriority.background);
      final alsoCounting = probe.request(
        '共享',
        ChapterLayoutPriority.background,
      );
      final next = probe.request('排队', priority);
      expect(probe.runningBudget.token.isCancelled, isFalse);

      reading.cancel();

      expect(probe.runningBudget.token.isCancelled, isTrue);
      await expectLater(reading.result, throwsA(isA<ChapterLoadCancelled>()));
      await expectLater(counting.result, throwsA(isA<ChapterLoadCancelled>()));
      await expectLater(
        alsoCounting.result,
        throwsA(isA<ChapterLoadCancelled>()),
      );
      expect(await next.result, hasLength(1));
      expect(probe.committed, ['排队']);
      expect(probe.finished, ['共享', '排队']);
    });
  }

  for (final priority in [
    ChapterLayoutPriority.reading,
    ChapterLayoutPriority.background,
  ]) {
    test('取消共享阅读后剩余 ${priority.name} 不被同优先级排队请求抢占', () async {
      final probe = _LayoutQueueProbe();
      addTearDown(probe.scheduler.close);
      final first = probe.request('共享', ChapterLayoutPriority.reading);
      final remaining = probe.request('共享', priority);
      final next = probe.request('排队', priority);

      first.cancel();

      expect(probe.runningBudget.token.isCancelled, isFalse);
      await expectLater(first.result, throwsA(isA<ChapterLoadCancelled>()));
      expect(await remaining.result, hasLength(1));
      expect(await next.result, hasLength(1));
      expect(probe.committed, ['共享', '排队']);
      expect(probe.finished, ['共享', '排队']);
    });
  }

  test('后台等待空闲时前台可抢占，取消立即唤醒旧预算', () async {
    final started = Completer<void>();
    final order = <String>[];
    final scheduler = ChapterLayoutScheduler(
      isCurrent: (_) => true,
      run: (snapshot, budget, _) async {
        order.add(snapshot.key);
        if (snapshot.key == '后台') {
          started.complete();
          await budget.checkpoint(force: true);
          fail('被抢占的后台作业不能继续提交');
        }
        return _pages();
      },
    );
    addTearDown(scheduler.close);
    final background = scheduler.schedule(
      _snapshot('后台'),
      priority: ChapterLayoutPriority.background,
      retainResult: false,
    );
    await started.future;
    final reading = scheduler.schedule(
      _snapshot('前台'),
      priority: ChapterLayoutPriority.reading,
      retainResult: true,
    );
    await expectLater(background.result, throwsA(isA<ChapterLoadCancelled>()));
    expect(await reading.result, hasLength(1));
    expect(order, ['后台', '前台']);
  });

  for (final priority in [ChapterLayoutPriority.background]) {
    test('${priority.name} 等待动画结束期间升为阅读立即继续同一作业', () async {
      final binding = SchedulerBinding.instance;
      final callback = binding.scheduleFrameCallback((_) {});
      addTearDown(() => binding.cancelFrameCallbackWithId(callback));
      final budget = LayoutBudget(priority: priority, isCurrent: () => true);
      var completed = false;
      final waiting = budget.checkpoint(force: true).then((_) {
        completed = true;
      });
      await Future<void>.delayed(Duration.zero);
      expect(completed, isFalse, reason: '动画活动期间框架不能执行空闲任务');
      budget.promote(ChapterLayoutPriority.reading);
      await waiting;
      expect(completed, isTrue);
      expect(budget.yieldCount, 1);
    });
  }

  test('邻章预取让出事件循环后继续，无需额外绘制一帧', () async {
    final budget = LayoutBudget(
      priority: ChapterLayoutPriority.prefetch,
      isCurrent: () => true,
    );
    var completed = false;
    final waiting = budget
        .checkpoint(force: true)
        .then((_) => completed = true);
    await Future<void>.value();
    expect(completed, isFalse, reason: '必须离开当前微任务队列，允许输入和前台抢占');
    await waiting;
    expect(completed, isTrue);
    expect(budget.yieldCount, 1);
    final cancelled = budget.checkpoint(force: true);
    budget.cancel();
    await expectLater(cancelled, throwsA(isA<ChapterLoadCancelled>()));
  });

  test('后台工作从首批之前就在空闲时继续，动画期间暂停并允许预取接管', () async {
    final budget = LayoutBudget(
      priority: ChapterLayoutPriority.background,
      isCurrent: () => true,
    );
    var completed = false;
    final idle = budget.checkpoint(force: true).then((_) => completed = true);
    await Future<void>.value();
    expect(completed, isFalse, reason: '静止时也必须让出事件循环处理输入');
    await idle;
    final binding = SchedulerBinding.instance;
    final callback = binding.scheduleFrameCallback((_) {});
    addTearDown(() => binding.cancelFrameCallbackWithId(callback));
    completed = false;
    final animated = budget
        .checkpoint(force: true)
        .then((_) => completed = true);
    await Future<void>.delayed(Duration.zero);
    expect(completed, isFalse, reason: '动画活动期间不再每帧继续后台排版');
    budget.promote(ChapterLayoutPriority.prefetch);
    await animated;
    expect(completed, isTrue);
    expect(budget.yieldCount, 2);
  });

  test('翻页暂停后台作业，恢复后接着计算而不重新构块', () async {
    final gate = Completer<void>();
    final started = Completer<void>();
    var runs = 0;
    var continued = false;
    final scheduler = ChapterLayoutScheduler(
      isCurrent: (_) => true,
      run: (_, budget, _) async {
        runs += 1;
        started.complete();
        await gate.future;
        await budget.checkpoint();
        continued = true;
        return _pages();
      },
    );
    addTearDown(scheduler.close);
    final handle = scheduler.schedule(
      _snapshot('暂停恢复'),
      priority: ChapterLayoutPriority.background,
      retainResult: true,
    );
    await started.future;
    scheduler.setBackgroundPaused(true);
    gate.complete();
    await Future<void>.delayed(Duration.zero);
    expect(continued, isFalse, reason: '手势阶段即使没有活动动画帧也暂停');
    scheduler.setBackgroundPaused(false);
    expect(await handle.result, hasLength(1));
    expect(continued, isTrue);
    expect(runs, 1);
  });

  test('暂停中的同键阅读请求立即接管，后台取消也不依赖恢复', () async {
    var runs = 0;
    final scheduler = ChapterLayoutScheduler(
      isCurrent: (_) => true,
      run: (_, budget, _) async {
        runs += 1;
        return _pages();
      },
    )..setBackgroundPaused(true);
    addTearDown(scheduler.close);
    final background = scheduler.schedule(
      _snapshot('接管'),
      priority: ChapterLayoutPriority.background,
      retainResult: true,
    );
    await Future<void>.delayed(Duration.zero);
    expect(runs, 0, reason: '后台作业启动也必须等待空闲');
    final reading = scheduler.schedule(
      _snapshot('接管'),
      priority: ChapterLayoutPriority.reading,
      retainResult: true,
    );
    expect(await reading.result, hasLength(1));
    expect(await background.result, hasLength(1));
    expect(runs, 1);
    final cancelled = scheduler.schedule(
      _snapshot('取消'),
      priority: ChapterLayoutPriority.background,
      retainResult: true,
    );
    cancelled.cancel();
    await expectLater(cancelled.result, throwsA(isA<ChapterLoadCancelled>()));
    expect(runs, 1);
  });

  test('待执行队列依次处理阅读、预取、后台，几何作业不并发', () async {
    final gate = Completer<void>();
    final order = <String>[];
    var concurrent = 0;
    var maximum = 0;
    final scheduler = ChapterLayoutScheduler(
      isCurrent: (_) => true,
      run: (snapshot, _, _) async {
        concurrent += 1;
        if (concurrent > maximum) maximum = concurrent;
        order.add(snapshot.key);
        if (snapshot.key == '当前') await gate.future;
        concurrent -= 1;
        return _pages();
      },
    );
    addTearDown(scheduler.close);
    ChapterLoadHandle request(String key, ChapterLayoutPriority priority) =>
        scheduler.schedule(
          _snapshot(key),
          priority: priority,
          retainResult: false,
        );
    final current = request('当前', ChapterLayoutPriority.reading);
    final counting = request('后台', ChapterLayoutPriority.background);
    final prefetch = request('预取', ChapterLayoutPriority.prefetch);
    final reading = request('阅读', ChapterLayoutPriority.reading);
    gate.complete();
    await Future.wait([
      current.result,
      counting.result,
      prefetch.result,
      reading.result,
    ]);
    expect(order, ['当前', '阅读', '预取', '后台']);
    expect(maximum, 1);
  });

  test('设置过期在结果提交前再次核验，失败释放输入且可以重试', () async {
    final gate = Completer<void>();
    var generation = 1;
    final commits = <int>[];
    final finished = <int>[];
    final scheduler = ChapterLayoutScheduler(
      isCurrent: (snapshot) => snapshot.generation == generation,
      onFinished: (snapshot) => finished.add(snapshot.generation),
      run: (snapshot, budget, _) async {
        if (snapshot.generation == 1) await gate.future;
        budget.check();
        commits.add(snapshot.generation);
        return _pages();
      },
    );
    addTearDown(scheduler.close);
    final old = scheduler.schedule(
      _snapshot('同键'),
      priority: ChapterLayoutPriority.reading,
      retainResult: true,
    );
    old.cancel();
    generation = 2;
    final latest = scheduler.schedule(
      _snapshot('同键', generation: 2),
      priority: ChapterLayoutPriority.reading,
      retainResult: true,
    );
    gate.complete();
    await expectLater(old.result, throwsA(isA<ChapterLoadCancelled>()));
    expect(await latest.result, hasLength(1));
    expect(commits, [2]);
    expect(finished, [1, 2]);
  });

  test('关闭立即取消所有等待者，晚到结果及新请求均不能提交', () async {
    final gate = Completer<void>();
    var runs = 0;
    var commits = 0;
    final finished = <String>[];
    final scheduler = ChapterLayoutScheduler(
      isCurrent: (_) => true,
      onFinished: (snapshot) => finished.add(snapshot.key),
      run: (_, budget, _) async {
        runs += 1;
        await gate.future;
        budget.check();
        commits += 1;
        return _pages();
      },
    );
    final running = scheduler.schedule(
      _snapshot('运行'),
      priority: ChapterLayoutPriority.reading,
      retainResult: true,
    );
    final pending = scheduler.schedule(
      _snapshot('排队'),
      priority: ChapterLayoutPriority.prefetch,
      retainResult: true,
    );
    scheduler.close();
    scheduler.close();
    final late = scheduler.schedule(
      _snapshot('关闭后'),
      priority: ChapterLayoutPriority.reading,
      retainResult: true,
    );
    for (final handle in [running, pending, late]) {
      await expectLater(handle.result, throwsA(isA<ChapterLoadCancelled>()));
    }
    gate.complete();
    await Future<void>.delayed(Duration.zero);
    expect(runs, 1);
    expect(commits, 0);
    expect(finished, containsAll(['运行', '排队', '关闭后']));
    expect(finished, hasLength(3));
  });

  for (final completedBeforePreparation in [false, true]) {
    test(
      '准备句柄完整交付保持终态：${completedBeforePreparation ? '已有完整结果' : '实时完成'}',
      () async {
        final gate = Completer<void>();
        final pages = _pages();
        final scheduler = ChapterLayoutScheduler(
          isCurrent: (_) => true,
          run: (_, budget, retain) async {
            await gate.future;
            return pages;
          },
        );
        addTearDown(scheduler.close);
        final scheduled = scheduler.schedule(
          _snapshot('完整转发'),
          priority: ChapterLayoutPriority.reading,
          retainResult: true,
          progressive: true,
        );
        if (completedBeforePreparation) {
          gate.complete();
          await scheduled.result;
        }
        final handle = PreparingChapterHandle((_) async => scheduled);
        if (!completedBeforePreparation) {
          await Future<void>.delayed(Duration.zero);
          gate.complete();
        }
        expect(await handle.firstPages, same(pages));
        expect(handle.isComplete, isTrue, reason: '完整页不能先被转发成未知总数的部分章');
        expect(await handle.result, same(pages));
      },
    );
  }

  test('原文准备期间提升阅读优先级会传给准备任务', () async {
    final gate = Completer<void>();
    final priorities = <ChapterLayoutPriority>[];
    final handle = PreparingChapterHandle(
      (_) async {
        await gate.future;
        throw const ChapterLoadCancelled();
      },
      priority: ChapterLayoutPriority.background,
      onPriorityChanged: priorities.add,
    );
    handle.setPriority(ChapterLayoutPriority.reading);
    expect(priorities, [ChapterLayoutPriority.reading]);
    handle.cancel();
    gate.complete();
    await expectLater(handle.result, throwsA(isA<ChapterLoadCancelled>()));
  });

  test('原文与字体准备期间取消可立即结束，不进入实际排版', () async {
    final gate = Completer<void>();
    var scheduled = false;
    var cancellations = 0;
    final handle = PreparingChapterHandle((cancelled) async {
      await gate.future;
      if (cancelled()) throw const ChapterLoadCancelled();
      scheduled = true;
      throw StateError('取消后不应调用此分支');
    }, onCancel: () => cancellations += 1);
    handle.cancel();
    handle.cancel();
    await expectLater(handle.result, throwsA(isA<ChapterLoadCancelled>()));
    expect(cancellations, 1);
    gate.complete();
    await Future<void>.delayed(Duration.zero);
    expect(scheduled, isFalse);
  });
}
