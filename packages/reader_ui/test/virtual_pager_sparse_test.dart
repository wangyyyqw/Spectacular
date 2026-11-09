import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_ui/virtual_pager.dart';

List<PageContent> _pages(int spine, {int count = 2}) => [
  for (var page = 0; page < count; page++)
    PageContent(
      spineIndex: spine,
      pageIndex: page,
      slices: const [],
      usedHeight: 0,
      pageHeight: 100,
      topPadding: 0,
    ),
];

void main() {
  for (final cancelWarm in [false, true]) {
    test('连续空章预热取消=$cancelWarm，活动目标仍可提交且缓存不超五章', () async {
      final gate = Completer<List<PageContent>>();
      final blocked = Completer<void>();
      var warming = true;
      final pager = VirtualPager(
        spineCount: 8,
        loader: (spine) async {
          if (spine == 5) {
            blocked.complete();
            return gate.future;
          }
          return _pages(spine, count: [0, 1, 7].contains(spine) ? 1 : 0);
        },
      );
      await pager.initialize();
      final origin = pager.current!.content;
      final target = await pager.prepareAdjacent(1, retainTarget: true);
      final pending = pager.prepareAdjacent(
        1,
        prefetch: true,
        distance: 2,
        shouldContinue: () => warming,
      );
      await blocked.future;
      if (cancelWarm) warming = false;
      gate.complete(const []);
      final warmed = await pending;

      expect(warmed?.spineIndex, cancelWarm ? isNull : 7);
      expect(pager.loadedSpines, contains(1));
      expect(
        pager.loadedSpines.length,
        lessThanOrEqualTo(VirtualPager.loadedSpineLimit),
      );
      expect(pager.commitPrepared(origin, target!), isTrue);
      expect(pager.current!.spineIndex, 1);
    });
  }

  for (final invalidate in ['释放目标', '取消导航', '外部跳转']) {
    test('$invalidate 后旧目标可被淘汰，缓存仍不超五章', () async {
      final pager = VirtualPager(
        spineCount: 8,
        loader: (spine) async =>
            _pages(spine, count: [0, 1, 7].contains(spine) ? 1 : 0),
      );
      await pager.initialize();
      final target = await pager.prepareAdjacent(1, retainTarget: true);
      switch (invalidate) {
        case '释放目标':
          pager.releasePrepared(target!);
          pager.releasePrepared(target);
        case '取消导航':
          pager.cancelPendingNavigation();
        case '外部跳转':
          await pager.goTo(0, 0);
      }
      await pager.prepareAdjacent(1, prefetch: true, distance: 2);

      expect(pager.loadedSpines, isNot(contains(1)));
      expect(
        pager.loadedSpines.length,
        lessThanOrEqualTo(VirtualPager.loadedSpineLimit),
      );
      expect(pager.current!.spineIndex, 0);
    });
  }

  test('旧目标重复释放不影响同章新目标，提交后释放其他目标保护', () async {
    final pager = VirtualPager(
      spineCount: 14,
      loader: (spine) async =>
          _pages(spine, count: [0, 1, 7, 13].contains(spine) ? 1 : 0),
    );
    await pager.initialize();
    final origin = pager.current!.content;
    final old = await pager.prepareAdjacent(1, retainTarget: true);
    final current = await pager.prepareAdjacent(1, retainTarget: true);
    pager.releasePrepared(old!);
    pager.releasePrepared(old);
    await pager.prepareAdjacent(1, distance: 2, retainTarget: true);

    expect(pager.loadedSpines, contains(1));
    expect(pager.commitPrepared(origin, current!), isTrue);
    await pager.prepareAdjacent(1, prefetch: true, distance: 2);

    expect(pager.loadedSpines, isNot(contains(7)));
    expect(
      pager.loadedSpines.length,
      lessThanOrEqualTo(VirtualPager.loadedSpineLimit),
    );
    expect(pager.current!.spineIndex, 1);
  });

  test('两页预热跨过空章且只使用低优先级加载', () async {
    final reading = <int>[];
    final prefetch = <int>[];
    final pager = VirtualPager(
      spineCount: 6,
      prefetchRadius: 2,
      loader: (spine) async {
        reading.add(spine);
        return _pages(spine, count: 1);
      },
      prefetchLoader: (spine) async {
        prefetch.add(spine);
        return _pages(spine, count: spine == 3 ? 0 : 1);
      },
    );
    await pager.initialize(startSpine: 2);
    final origin = pager.current!.content;
    final next = await pager.prepareAdjacent(1, prefetch: true, distance: 2);
    final previous = await pager.prepareAdjacent(
      -1,
      prefetch: true,
      distance: 2,
    );
    expect(next!.spineIndex, 5);
    expect(previous!.spineIndex, 0);
    expect(reading, [2]);
    expect(prefetch, [3, 4, 5, 1, 0]);
    expect(identical(pager.current!.content, origin), isTrue);
  });

  test('两页预热取消后不继续加载第二章且不提交位置', () async {
    final gate = Completer<List<PageContent>>();
    final prefetch = <int>[];
    var active = true;
    final pager = VirtualPager(
      spineCount: 4,
      loader: (spine) async => _pages(spine, count: 1),
      prefetchLoader: (spine) async {
        prefetch.add(spine);
        return gate.future;
      },
    );
    await pager.initialize();
    final pending = pager.prepareAdjacent(
      1,
      prefetch: true,
      distance: 2,
      shouldContinue: () => active,
    );
    active = false;
    gate.complete(_pages(1, count: 1));
    expect(await pending, isNull);
    expect(prefetch, [1]);
    expect(pager.current!.spineIndex, 0);
  });

  test('高章序打开及远距离跳转均只加载目标章，不等待邻章', () async {
    final loads = <int>[];
    final never = Completer<List<PageContent>>();
    final pager = VirtualPager(
      spineCount: 2000,
      loader: (spine) async {
        loads.add(spine);
        return spine == 1500 || spine == 20 ? _pages(spine) : never.future;
      },
    );
    await pager.initialize(startSpine: 1500, startPage: 1);
    expect(loads, [1500]);
    expect(pager.current!.pageIndex, 1);
    await pager.goTo(20, 0);
    expect(loads, [1500, 20]);
    expect(pager.current!.spineIndex, 20);
    expect(pager.prefetchedPages.map((p) => p.spineIndex), everyElement(20));
  });

  test('断档窗口双向翻页必须加载真实邻章，不能直接跨到已缓存远章', () async {
    final loads = <int>[];
    final pager = VirtualPager(
      spineCount: 100,
      loader: (spine) async {
        loads.add(spine);
        return _pages(spine);
      },
    );
    await pager.initialize(startSpine: 50);
    await pager.goTo(2, 1);
    await pager.next();
    expect((pager.current!.spineIndex, pager.current!.pageIndex), (3, 0));
    await pager.goTo(50, 0);
    await pager.previous();
    expect((pager.current!.spineIndex, pager.current!.pageIndex), (49, 1));
    expect(loads, [50, 2, 3, 49]);
  });

  test('空章按指定方向查找，上一章落在首页，上一页落在末页', () async {
    final pager = VirtualPager(
      spineCount: 6,
      loader: (spine) async =>
          _pages(spine, count: spine == 2 || spine == 3 ? 0 : 2),
    );
    await pager.initialize(startSpine: 4);
    await pager.goTo(3, 0, emptyDirection: -1);
    expect((pager.current!.spineIndex, pager.current!.pageIndex), (1, 0));
    await pager.goTo(4, 0);
    await pager.previous();
    expect((pager.current!.spineIndex, pager.current!.pageIndex), (1, 1));
  });

  test('慢旧跳转加载完成后不得覆盖新位置或因映射扩展而漂移', () async {
    final gate = Completer<List<PageContent>>();
    final pager = VirtualPager(
      spineCount: 100,
      loader: (spine) async => spine == 3 ? gate.future : _pages(spine),
    );
    await pager.initialize(startSpine: 40);
    final old = pager.goTo(3, 0);
    expect(await pager.goTo(80, 1), isTrue);
    gate.complete(_pages(3));
    expect(await old, isFalse);
    expect((pager.current!.spineIndex, pager.current!.pageIndex), (80, 1));
    expect(pager.loadedSpines, contains(3));
  });

  test('同章并发加载去重，取消后旧导航不能提交', () async {
    final gate = Completer<List<PageContent>>();
    var calls = 0;
    final pager = VirtualPager(
      spineCount: 3,
      loader: (spine) async {
        if (spine != 2) return _pages(spine);
        calls++;
        return gate.future;
      },
    );
    await pager.initialize();
    final a = pager.goTo(2, 0);
    final b = pager.goTo(2, 1);
    pager.cancelPendingNavigation();
    gate.complete(_pages(2));
    expect(await a, isFalse);
    expect(await b, isFalse);
    expect(calls, 1);
    expect((pager.current!.spineIndex, pager.current!.pageIndex), (0, 0));
  });

  test('远距离连续跳转只保留 5 章页窗口且当前章可继续导航', () async {
    final loads = <int>[];
    final pager = VirtualPager(
      spineCount: 100,
      loader: (spine) async {
        loads.add(spine);
        return _pages(spine);
      },
    );
    await pager.initialize();
    for (final spine in [10, 20, 30, 40, 50, 60]) {
      expect(await pager.goTo(spine, 0), isTrue);
    }

    expect(
      pager.loadedSpines.length,
      lessThanOrEqualTo(VirtualPager.loadedSpineLimit),
    );
    expect(pager.loadedSpines, contains(60));
    expect(pager.mappedPageCount, 14, reason: '只淘汰页面内容，保留每章页数元数据以稳定虚拟页码');
    expect(await pager.previous(), isTrue);
    expect((pager.current!.spineIndex, pager.current!.pageIndex), (59, 1));
  });
}
