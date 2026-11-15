import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_ui/panels/search_panel.dart';

List<SearchPanelResult> _results() => <SearchPanelResult>[
  const SearchPanelResult(
    spineIndex: 0,
    charOffset: 3,
    chapterTitle: '第一章 简单正文',
    context: '沈河昨天收到了一个包裹。',
    matchLength: 2,
    cfi: 'epubcfi(/6/4!/4/2/1:3)',
  ),
  const SearchPanelResult(
    spineIndex: 0,
    charOffset: 20,
    chapterTitle: '第一章 简单正文',
    context: '沈河并不想知道生命的意义。',
    matchLength: 2,
    cfi: 'epubcfi(/6/4!/4/2/1:20)',
  ),
  const SearchPanelResult(
    spineIndex: 1,
    charOffset: 5,
    chapterTitle: '第二章',
    context: '第二个沈河出现了。',
    matchLength: 2,
    cfi: 'epubcfi(/6/6!/4/2/1:5)',
  ),
];

void main() {
  testWidgets('输入防抖：300ms 内只查一次，出结果后按章分组（P4-26）', (tester) async {
    var calls = 0;
    final selected = <SearchPanelResult>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SearchPanel(
            debounce: const Duration(milliseconds: 300),
            onSearch: (query) async {
              calls++;
              return query == '沈河'
                  ? _results()
                  : const <SearchPanelResult>[];
            },
            onSelect: selected.add,
          ),
        ),
      ),
    );

    // 初始空态。
    expect(find.byKey(const ValueKey<String>('search-empty')), findsOneWidget);
    expect(find.text('输入关键词搜索全书'), findsOneWidget);

    // 连续输入：只有最后一次在防抖后触发查询。
    await tester.enterText(find.byKey(const ValueKey<String>('search-input')), '沈');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(find.byKey(const ValueKey<String>('search-input')), '沈河');
    await tester.pump(const Duration(milliseconds: 100));
    expect(calls, 0, reason: '防抖期间不查');

    await tester.pump(const Duration(milliseconds: 320));
    await tester.pumpAndSettle();
    expect(calls, 1, reason: '300ms 内只触发一次');

    // 分组：两个章标题 + 三条命中。
    expect(find.byKey(const ValueKey<String>('search-results')), findsOneWidget);
    expect(find.textContaining('第一章 简单正文'), findsOneWidget);
    expect(find.textContaining('第二章'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('search-hit-0-3')),
      findsOneWidget,
    );

    // 命中词高亮：Text.rich 里带专色 span。
    final richText = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const ValueKey<String>('search-hit-0-3')),
        matching: find.byType(Text),
      ),
    );
    final span = richText.textSpan as TextSpan;
    expect(span.children, hasLength(3), reason: '前文 + 命中 + 后文');

    await tester.tap(find.byKey(const ValueKey<String>('search-hit-0-3')));
    expect(selected.single.charOffset, 3);
  });

  testWidgets('空结果与加载态（P4-26）', (tester) async {
    final completer = Completer<List<SearchPanelResult>>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SearchPanel(
            debounce: const Duration(milliseconds: 10),
            onSearch: (query) => completer.future,
            onSelect: (_) {},
          ),
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('search-input')),
      'zzz',
    );
    await tester.pump(const Duration(milliseconds: 20));
    // 查询未返回 → 加载态。
    expect(
      find.byKey(const ValueKey<String>('search-loading')),
      findsOneWidget,
    );
    completer.complete(const <SearchPanelResult>[]);
    await tester.pumpAndSettle();
    expect(find.text('没有找到「zzz」'), findsOneWidget);
  });

  testWidgets('输入变化立即使旧查询失效，不等待新查询防抖结束', (tester) async {
    final oldQuery = Completer<List<SearchPanelResult>>();
    final newQuery = Completer<List<SearchPanelResult>>();
    final queries = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SearchPanel(
            onSearch: (query) {
              queries.add(query);
              return query == '旧词' ? oldQuery.future : newQuery.future;
            },
            onSelect: (_) {},
          ),
        ),
      ),
    );
    final input = find.byKey(const ValueKey<String>('search-input'));
    await tester.enterText(input, '旧词');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.enterText(input, '新词');
    await tester.pump(const Duration(milliseconds: 100));
    oldQuery.complete(_results());
    await tester.pump();

    expect(queries, ['旧词']);
    expect(find.byKey(const ValueKey<String>('search-results')), findsNothing);
    expect(find.byKey(const ValueKey<String>('search-loading')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 250));
    newQuery.complete(const []);
    await tester.pumpAndSettle();
    expect(queries, ['旧词', '新词']);
    expect(find.text('没有找到「新词」'), findsOneWidget);
  });

  testWidgets('清空输入后旧流式批次不能恢复到下一次输入', (tester) async {
    final oldQuery = StreamController<SearchProgress>.broadcast();
    final newQuery = StreamController<SearchProgress>.broadcast();
    addTearDown(oldQuery.close);
    addTearDown(newQuery.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SearchPanel(
            onSearch: (_) async => const [],
            onSearchStream: (query) =>
                query == '旧词' ? oldQuery.stream : newQuery.stream,
            onSelect: (_) {},
          ),
        ),
      ),
    );
    final input = find.byKey(const ValueKey<String>('search-input'));
    await tester.enterText(input, '旧词');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.enterText(input, '');
    oldQuery.add(SearchProgress(results: _results(), scanned: 1, total: 1));
    await tester.pump();
    await tester.enterText(input, '新词');
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byKey(const ValueKey<String>('search-results')), findsNothing);
    expect(find.byKey(const ValueKey<String>('search-loading')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 250));
    newQuery.add(const SearchProgress(results: [], scanned: 1, total: 1));
    await tester.pumpAndSettle();
    expect(find.text('没有找到「新词」'), findsOneWidget);
  });

  testWidgets('100 条结果用 builder 懒构建（滚动不卡）', (tester) async {
    final many = <SearchPanelResult>[
      for (var i = 0; i < 100; i++)
        SearchPanelResult(
          spineIndex: i ~/ 10,
          charOffset: i,
          chapterTitle: '第 ${i ~/ 10 + 1} 章',
          context: '第 $i 条命中沈河',
          matchLength: 2,
          cfi: 'epubcfi(/6/4!/4/2/1:$i)',
        ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SearchPanel(
            debounce: const Duration(milliseconds: 10),
            onSearch: (query) async => many,
            onSelect: (_) {},
          ),
        ),
      ),
    );
    await tester.enterText(find.byKey(const ValueKey<String>('search-input')), '沈河');
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pumpAndSettle();

    // 只构建可视范围内的项（10 章标题 + 若干命中，远少于 100+10）。
    final rendered = find.byKey(const ValueKey<String>('search-results'));
    expect(rendered, findsOneWidget);
    final listView = tester.widget<ListView>(rendered);
    expect(listView.childrenDelegate, isA<SliverChildBuilderDelegate>());

    await tester.drag(rendered, const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('search-hit-0-0')),
      findsNothing,
      reason: '滚出视口的项已被回收',
    );
  });
}
