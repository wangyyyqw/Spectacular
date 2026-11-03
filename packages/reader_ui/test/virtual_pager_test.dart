import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_ui/virtual_pager.dart';

PageContent _page(int spine, int index) => PageContent(
  spineIndex: spine,
  pageIndex: index,
  slices: const <PageBlockSlice>[],
  usedHeight: 0,
  pageHeight: 100,
  topPadding: 0,
);

void main() {
  late List<int> counts;
  late List<int> loads;
  late VirtualPager pager;

  setUp(() {
    counts = <int>[2, 3, 2];
    loads = <int>[];
    pager = VirtualPager(
      spineCount: counts.length,
      loader: (spine) async {
        loads.add(spine);
        return <PageContent>[
          for (var i = 0; i < counts[spine]; i++) _page(spine, i),
        ];
      },
    );
  });

  test('跨章连续翻页页码递增、无重复断号', () async {
    await pager.initialize();
    final visited = <(int, int)>[];
    visited.add((pager.current!.spineIndex, pager.current!.pageIndex));
    while (await pager.next()) {
      final page = pager.current!;
      visited.add((page.spineIndex, page.pageIndex));
      expect(page.virtualIndex, visited.length - 1);
    }
    expect(visited, <(int, int)>[
      (0, 0),
      (0, 1),
      (1, 0),
      (1, 1),
      (1, 2),
      (2, 0),
      (2, 1),
    ]);
    expect(pager.mappedPageCount, 7);
    expect(pager.currentVirtualPage, 6);
    expect(loads, <int>[0, 1, 2]);
    expect(await pager.next(), isFalse);
  });

  test('向前翻页页码递减，回到首页停止', () async {
    await pager.initialize();
    while (await pager.next()) {}
    final visited = <(int, int)>[];
    while (true) {
      final page = pager.current!;
      visited.add((page.spineIndex, page.pageIndex));
      if (!await pager.previous()) {
        break;
      }
    }
    expect(visited, <(int, int)>[
      (2, 1),
      (2, 0),
      (1, 2),
      (1, 1),
      (1, 0),
      (0, 1),
      (0, 0),
    ]);
    expect(pager.currentVirtualPage, 0);
    expect(await pager.previous(), isFalse);
  });

  test('前后邻页复用已加载页，章边界不提前排版其他章节', () async {
    await pager.initialize();
    expect(pager.prefetchedPages.map((page) => page.pageIndex), contains(1));
    await pager.next(); // 页 0.1，章末仍只需要当前章
    expect(loads, [0]);
    final prefetched = pager.prefetchedPages;
    expect(
      prefetched.map((page) => (page.spineIndex, page.pageIndex)),
      [(0, 0)],
    );
  });

  test('边界章不加载越界章节', () async {
    await pager.initialize();
    expect(loads.contains(-1), isFalse);
    while (await pager.next()) {}
    expect(loads.contains(3), isFalse);
    expect(pager.current!.spineIndex, 2);
    expect(pager.current!.pageIndex, 1);
  });

  test('指定起始章只加载目标章，窗口页码从零开始', () async {
    await pager.initialize(startSpine: 1);
    expect(loads, [1]);
    expect(pager.currentVirtualPage, 0);
    expect((pager.current!.spineIndex, pager.current!.pageIndex), (1, 0));
  });

  test('goTo 跳转后前后翻页仍连续', () async {
    await pager.initialize();
    expect(await pager.goTo(2, 1), isTrue);
    expect(pager.currentVirtualPage, 3);
    expect(await pager.previous(), isTrue);
    expect(pager.currentVirtualPage, 2);
    expect((pager.current!.spineIndex, pager.current!.pageIndex), (2, 0));
  });

  test('空章不产生虚拟页且不崩溃', () async {
    counts = <int>[1, 0, 1];
    pager = VirtualPager(
      spineCount: counts.length,
      loader: (spine) async => <PageContent>[
        for (var i = 0; i < counts[spine]; i++) _page(spine, i),
      ],
    );
    await pager.initialize();
    expect(pager.mappedPageCount, 1);
    expect(await pager.next(), isTrue);
    expect(pager.current!.spineIndex, 2);
    expect(pager.current!.pageIndex, 0);
    expect(pager.currentVirtualPage, 1);
  });

  test('越界 goTo：章节越界返回 false，页码越界钳制到章末页（P2-32）', () async {
    await pager.initialize();
    expect(await pager.goTo(-1, 0), isFalse);
    expect(await pager.goTo(3, 0), isFalse);
    expect(await pager.goTo(0, 99), isTrue);
    expect(pager.current!.spineIndex, 0);
    expect(pager.current!.pageIndex, 1, reason: '0 章共 2 页，钳制到末页');
  });

  test('准备邻页不提前改变当前位置', () async {
    await pager.initialize();
    final origin = pager.current!.content;

    final prepared = await pager.prepareAdjacent(1);

    expect(prepared, isNotNull);
    expect((prepared!.spineIndex, prepared.pageIndex), (0, 1));
    expect(identical(pager.current!.content, origin), isTrue);
    expect(pager.currentVirtualPage, 0);
  });

  test('动画收尾只提交一次目标页', () async {
    await pager.initialize();
    final origin = pager.current!.content;
    final prepared = await pager.prepareAdjacent(1);

    expect(pager.commitPrepared(origin, prepared!), isTrue);
    expect((pager.current!.spineIndex, pager.current!.pageIndex), (0, 1));
    expect(pager.commitPrepared(origin, prepared), isFalse);
  });

  test('外部跳转后旧动画目标不能回写', () async {
    await pager.initialize();
    final origin = pager.current!.content;
    final stale = await pager.prepareAdjacent(1);
    expect(await pager.goTo(2, 0), isTrue);

    expect(pager.commitPrepared(origin, stale!), isFalse);
    expect((pager.current!.spineIndex, pager.current!.pageIndex), (2, 0));
  });
}
