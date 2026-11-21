import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
  testWidgets('每章结果支持独立折叠与展开', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SearchPanel(
            debounce: Duration.zero,
            onSearch: (_) async => _results(),
            onSelect: (_) {},
          ),
        ),
      ),
    );
    await tester.enterText(find.byKey(const ValueKey('search-input')), '沈河');
    await tester.pumpAndSettle();
    final chapter = find.byKey(const ValueKey('search-chapter-0'));
    final hit = find.byKey(const ValueKey('search-hit-0-3'));
    expect(tester.getSize(chapter).height, 40);
    expect(tester.getSize(hit).height, 40);
    expect(
      tester.getTopLeft(hit).dy - tester.getBottomLeft(chapter).dy,
      closeTo(2, 1),
    );
    final lineFinder = find.byKey(const ValueKey('search-chapter-line-0'));
    final expandedLine = tester.widget<AnimatedContainer>(lineFinder);
    expect(expandedLine.duration, const Duration(milliseconds: 180));
    final expandedBorder =
        (expandedLine.decoration! as BoxDecoration).border! as Border;
    expect(expandedBorder.bottom.color, isNot(Colors.transparent));
    await tester.tap(chapter);
    await tester.pump();
    final collapsedLine = tester.widget<AnimatedContainer>(lineFinder);
    final collapsedBorder =
        (collapsedLine.decoration! as BoxDecoration).border! as Border;
    expect(collapsedBorder.bottom.color, Colors.transparent);
    await tester.pump(const Duration(milliseconds: 90));
    expect(tester.hasRunningAnimations, isTrue);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('search-hit-0-3')), findsNothing);
    expect(find.byKey(const ValueKey('search-hit-0-20')), findsNothing);
    expect(find.byKey(const ValueKey('search-hit-1-5')), findsOneWidget);
    await tester.tap(chapter);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('search-hit-0-3')), findsOneWidget);
    expect(find.byKey(const ValueKey('search-hit-0-20')), findsOneWidget);
  });

  testWidgets('结果从章内阅读位置开始，下拉看之前，上滑看之后', (tester) async {
    final hits = List.generate(
      60,
      (i) => SearchPanelResult(
        spineIndex: i ~/ 20,
        charOffset: i % 20 * 10,
        chapterTitle: '章节 ${i ~/ 20}',
        context: '命中 $i',
        matchLength: 2,
        cfi: 'epubcfi(/6/${4 + i ~/ 20 * 2}!/4/2/1:${i % 20 * 10})',
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 360,
            child: SearchPanel(
              currentSpineIndex: 1,
              currentCfi: 'epubcfi(/6/6!/4/2/1:95)',
              debounce: Duration.zero,
              onSearch: (_) async => hits,
              onSelect: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.enterText(find.byKey(const ValueKey('search-input')), '命中');
    await tester.pumpAndSettle();
    final list = find.byKey(const ValueKey('search-results'));
    final next = find.byKey(const ValueKey('search-hit-1-100'));
    expect(tester.getTopLeft(next).dy, closeTo(tester.getTopLeft(list).dy, 1));
    await tester.drag(list, const Offset(0, 220));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('search-hit-1-80')).hitTestable(),
      findsOneWidget,
    );
    await tester.drag(list, const Offset(0, -360));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('search-hit-1-150')).hitTestable(),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('流式跨章追加后仍以当前阅读位置为起点', (tester) async {
    final batches = StreamController<SearchProgress>();
    addTearDown(batches.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SearchPanel(
            currentSpineIndex: 1,
            currentCfi: 'epubcfi(/6/6!/4/2/1:3)',
            debounce: Duration.zero,
            onSearch: (_) async => const [],
            onSearchStream: (_) => batches.stream,
            onSelect: (_) {},
          ),
        ),
      ),
    );
    await tester.enterText(find.byKey(const ValueKey('search-input')), '沈河');
    await tester.pump();
    batches.add(
      SearchProgress(
        results: _results().take(2).toList(),
        scanned: 1,
        total: 3,
      ),
    );
    await tester.pump();
    batches.add(SearchProgress(results: _results(), scanned: 2, total: 3));
    await tester.pump();
    batches.add(SearchProgress(results: _results(), scanned: 3, total: 3));
    await tester.pumpAndSettle();
    final list = find.byKey(const ValueKey('search-results'));
    final header = find.byKey(const ValueKey('search-chapter-1'));
    expect(
      tester.getTopLeft(header).dy,
      closeTo(tester.getTopLeft(list).dy, 1),
    );
    await tester.drag(list, const Offset(0, 250));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('search-hit-0-20')).hitTestable(),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    testWidgets('搜索页与目录统一排版并适配 ${brightness.name} 主题', (tester) async {
      final theme = ThemeData(brightness: brightness);
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: SearchPanel(
              debounce: Duration.zero,
              onSearch: (_) async => _results(),
              onSelect: (_) {},
            ),
          ),
        ),
      );
      final panel = find.byType(SearchPanel);
      final material = tester.widget<Material>(
        find.descendant(of: panel, matching: find.byType(Material)).first,
      );
      expect(
        material.color,
        brightness == Brightness.dark
            ? theme.colorScheme.surface
            : Colors.white,
      );
      final input = find.byKey(const ValueKey<String>('search-input'));
      final field = tester.widget<TextField>(input);
      expect(field.style?.fontFamily, 'serif');
      expect(field.style?.fontSize, 14);
      final border = field.decoration!.enabledBorder! as OutlineInputBorder;
      expect(border.borderRadius, BorderRadius.circular(20));
      expect(border.borderSide, BorderSide.none);
      expect(field.decoration?.focusedBorder, border);
      expect(field.decoration?.filled, isTrue);
      expect(field.decoration?.fillColor, theme.colorScheme.surface);
      expect(
        field.decoration?.contentPadding,
        const EdgeInsets.symmetric(vertical: 8),
      );
      final inputSurface = tester.widget<Material>(
        find.byKey(const ValueKey('search-input-surface')),
      );
      expect(inputSurface.elevation, 2);
      expect(inputSurface.borderRadius, BorderRadius.circular(20));
      await tester.enterText(input, '沈河');
      await tester.pumpAndSettle();
      final title = tester.widget<Text>(find.text('第一章 简单正文 · 2 处'));
      expect(title.style?.fontFamily, 'serif');
      expect(title.style?.fontSize, 14);
      final hit = tester.widget<ListTile>(
        find.byKey(const ValueKey<String>('search-hit-0-3')),
      );
      expect(hit.contentPadding, EdgeInsets.zero);
      final hitSurface = tester.widget<Container>(
        find
            .ancestor(
              of: find.byKey(const ValueKey('search-hit-0-3')),
              matching: find.byType(Container),
            )
            .first,
      );
      expect(hitSurface.margin, const EdgeInsets.only(left: 58, right: 24));
      expect((hitSurface.decoration! as BoxDecoration).border, isA<Border>());
      final span = (hit.title! as Text).textSpan! as TextSpan;
      expect(span.style?.height, 1.5);
      final highlighted = span.children![1] as TextSpan;
      expect(highlighted.style?.fontWeight, FontWeight.w600);
      expect(
        highlighted.style?.color,
        brightness == Brightness.dark
            ? theme.colorScheme.onSurface
            : const Color(0xFF333333),
      );
      await tester.tap(find.byKey(const ValueKey<String>('search-clear')));
      await tester.pumpAndSettle();
      expect(find.text('输入关键词搜索全书'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('search-results')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });
  }

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
              return query == '沈河' ? _results() : const <SearchPanelResult>[];
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
    await tester.enterText(
      find.byKey(const ValueKey<String>('search-input')),
      '沈',
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(
      find.byKey(const ValueKey<String>('search-input')),
      '沈河',
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(calls, 0, reason: '防抖期间不查');

    await tester.pump(const Duration(milliseconds: 320));
    await tester.pumpAndSettle();
    expect(calls, 1, reason: '300ms 内只触发一次');

    // 分组：两个章标题 + 三条命中。
    expect(
      find.byKey(const ValueKey<String>('search-results')),
      findsOneWidget,
    );
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

  for (final (query, context, expectedContext) in [
    ('魔王', '。\r\n\n　　毕竟连神以及魔王都存在，这样也不值得惊讶', '。 毕竟连神以及魔王都存在，这样也不值得惊讶'),
    ('魔王  存在', ' \n。\t\r\n魔王  存在。\n ', '。 魔王 存在。'),
  ]) {
    testWidgets('搜索片段折叠正文空白，命中词保持可见且跳转位置不变：$query', (tester) async {
      final result = SearchPanelResult(
        spineIndex: 12,
        charOffset: 164,
        chapterTitle: '冒险者公会',
        context: context,
        matchLength: query.length,
        cfi: 'epubcfi(/6/26!/4/2/1:164)',
      );
      SearchPanelResult? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 320,
                child: SearchPanel(
                  debounce: Duration.zero,
                  onSearch: (_) async => [result],
                  onSelect: (value) => selected = value,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.enterText(find.byKey(const ValueKey('search-input')), query);
      await tester.pumpAndSettle();

      final hit = find.byKey(const ValueKey('search-hit-12-164'));
      final text = find.descendant(of: hit, matching: find.byType(Text));
      final span = tester.widget<Text>(text).textSpan! as TextSpan;
      expect(span.toPlainText(), expectedContext);
      final highlighted = span.children![1] as TextSpan;
      expect(highlighted.text, query.replaceAll(RegExp(r'\s+'), ' '));
      expect(highlighted.style?.fontWeight, FontWeight.w600);
      final paragraph = tester.renderObject<RenderParagraph>(
        find.descendant(of: text, matching: find.byType(RichText)),
      );
      final start = expectedContext.indexOf(highlighted.text!);
      expect(
        paragraph.getBoxesForSelection(
          TextSelection(
            baseOffset: start,
            extentOffset: start + highlighted.text!.length,
          ),
        ),
        isNotEmpty,
        reason: '命中词不能被两行上限裁掉',
      );
      await tester.tap(hit);
      expect(selected, same(result), reason: '保留原始上下文、字符偏移和 CFI');
    });
  }

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
    expect(
      find.byKey(const ValueKey<String>('search-loading')),
      findsOneWidget,
    );
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
    expect(
      find.byKey(const ValueKey<String>('search-loading')),
      findsOneWidget,
    );
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
    await tester.enterText(
      find.byKey(const ValueKey<String>('search-input')),
      '沈河',
    );
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pumpAndSettle();

    // 只构建可视范围内的项（10 章标题 + 若干命中，远少于 100+10）。
    final rendered = find.byKey(const ValueKey<String>('search-results'));
    expect(rendered, findsOneWidget);
    final scrollView = tester.widget<CustomScrollView>(rendered);
    expect(
      scrollView.slivers.whereType<SliverList>().every(
        (sliver) => sliver.delegate is SliverChildBuilderDelegate,
      ),
      isTrue,
    );

    await tester.drag(rendered, const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('search-hit-0-0')),
      findsNothing,
      reason: '滚出视口的项已被回收',
    );
  });
}
