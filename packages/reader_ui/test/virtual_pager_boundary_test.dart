import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_ui/virtual_pager.dart';

/// 按章节页数生成空白页（边界逻辑只关心页身份，不关心内容）。
SpinePagesLoader _loader(Map<int, int> pageCounts) {
  return (int spineIndex) async {
    final count = pageCounts[spineIndex] ?? 0;
    return <PageContent>[
      for (var page = 0; page < count; page++)
        PageContent(
          spineIndex: spineIndex,
          pageIndex: page,
          slices: const <PageBlockSlice>[],
          usedHeight: 0,
          pageHeight: 100,
          topPadding: 0,
        ),
    ];
  };
}

Future<VirtualPager> _open(Map<int, int> counts, {int startSpine = 0}) async {
  final pager = VirtualPager(
    spineCount: counts.length,
    loader: _loader(counts),
  );
  await pager.initialize(startSpine: startSpine);
  return pager;
}

Future<List<(int, int)>> _walkForward(VirtualPager pager, int maxSteps) async {
  final visited = <(int, int)>[];
  final current = pager.current;
  if (current != null) {
    visited.add((current.spineIndex, current.pageIndex));
  }
  for (var i = 0; i < maxSteps; i++) {
    final page = pager.current;
    if (page == null) {
      break;
    }
    final moved = await pager.next();
    if (!moved || !_hasMoved(pager, page)) {
      break;
    }
    final next = pager.current;
    if (next == null) {
      break;
    }
    visited.add((next.spineIndex, next.pageIndex));
  }
  return visited;
}

bool _hasMoved(VirtualPager pager, VirtualPage before) {
  final now = pager.current;
  return now != null && now.virtualIndex != before.virtualIndex;
}

void main() {
  test('30 章样本连续翻到底：无空白页、页码不回跳', () async {
    final counts = <int, int>{for (var i = 0; i < 30; i++) i: 2};
    final pager = await _open(counts);

    var steps = 0;
    var lastVirtual = pager.current!.virtualIndex;
    while (await pager.next()) {
      steps += 1;
      final page = pager.current;
      expect(page, isNotNull, reason: '翻页不应落到空白页');
      expect(page!.virtualIndex, lastVirtual + 1, reason: '连续页码每次 +1');
      expect(page.content.pageIndex, page.pageIndex);
      lastVirtual = page.virtualIndex;
    }

    expect(steps, 59, reason: '30 章 × 2 页，从首页起应再翻 59 次');
    expect(pager.current!.spineIndex, 29);
    expect(pager.current!.pageIndex, 1);
    final end = pager.current!.virtualIndex;
    expect(await pager.next(), isFalse, reason: '最后一页不再前进');
    expect(pager.current!.virtualIndex, end);
  });

  test('空章前向跳过，不出现空白页', () async {
    final counts = <int, int>{0: 2, 1: 0, 2: 1, 3: 2, 4: 1};
    final pager = await _open(counts);
    final visited = await _walkForward(pager, 20);
    expect(visited, [(0, 0), (0, 1), (2, 0), (3, 0), (3, 1), (4, 0)]);
  });

  test('章首向前翻页跨空章，回到上一章末页', () async {
    final counts = <int, int>{0: 2, 1: 0, 2: 2, 3: 1};
    final pager = await _open(counts);
    await pager.goTo(2, 0);
    expect(pager.current!.spineIndex, 2);
    expect(pager.current!.pageIndex, 0);

    expect(await pager.previous(), isTrue);
    final page = pager.current!;
    expect(
      (page.spineIndex, page.pageIndex),
      (0, 1),
      reason: '跳过空章 1 回到章 0 末页',
    );
    expect(page.virtualIndex, pager.currentVirtualPage);
  });

  test('文档首章首页 previous 返回 false', () async {
    final pager = await _open(<int, int>{0: 2, 1: 1});
    expect(await pager.previous(), isFalse);
    expect(pager.current!.spineIndex, 0);
    expect(pager.current!.pageIndex, 0);
  });

  test('goTo 页码越界钳制到章末页', () async {
    final pager = await _open(<int, int>{0: 3, 1: 2});
    expect(await pager.goTo(0, 99), isTrue);
    expect(pager.current!.pageIndex, 2);
  });

  test('goTo 空章落到下一个有页章节', () async {
    final pager = await _open(<int, int>{0: 1, 1: 0, 2: 2});
    expect(await pager.goTo(1, 0), isTrue);
    expect(pager.current!.spineIndex, 2);
    expect(pager.current!.pageIndex, 0);
  });

  test('initialize 从空章开始落到下一个有页章节', () async {
    final pager = await _open(<int, int>{0: 1, 1: 0, 2: 2}, startSpine: 1);
    expect(pager.current!.spineIndex, 2);
    expect(pager.current!.pageIndex, 0);
  });

  test('全空文档不会前进也不会崩溃', () async {
    final pager = await _open(<int, int>{0: 0, 1: 0});
    expect(pager.current, isNull);
    expect(await pager.next(), isFalse);
    expect(await pager.previous(), isFalse);
    expect(await pager.goTo(0, 0), isFalse);
  });
}
