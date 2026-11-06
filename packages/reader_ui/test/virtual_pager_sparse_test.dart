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
    expect(
      pager.mappedPageCount,
      14,
      reason: '只淘汰页面内容，保留每章页数元数据以稳定虚拟页码',
    );
    expect(await pager.previous(), isTrue);
    expect((pager.current!.spineIndex, pager.current!.pageIndex), (59, 1));
  });
}
