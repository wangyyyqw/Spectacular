import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_ui/a11y/semantics_layer.dart';

ComputedStyle _style({int fontWeight = 400}) =>
    ComputedStyle(<String, String>{
      'font-size': '16px',
      'line-height': '1.5',
      'font-family': 'Ahem',
      'font-weight': '$fontWeight',
    });

PageContent _page() {
  final blocks = <PageBlock>[
    PageBlock(
      layout: TextLayoutEngine.layout(
        text: '第一章 开局',
        style: _style(fontWeight: 700),
        maxWidth: 320,
      ),
      style: _style(fontWeight: 700),
      startCfi: 'epubcfi(/6/4!/4/2/1)',
    ),
    PageBlock(
      layout: TextLayoutEngine.layout(
        text: '这是正文段落内容。',
        style: _style(),
        maxWidth: 320,
      ),
      style: _style(),
      startCfi: 'epubcfi(/6/4!/4/2/3)',
    ),
  ];
  final slices = <PageBlockSlice>[
    for (final block in blocks)
      PageBlockSlice(
        block: block,
        startLine: 0,
        endLine: block.layout.lineCount,
        height: block.layout.height,
      ),
  ];
  return PageContent(
    spineIndex: 0,
    pageIndex: 0,
    slices: slices,
    usedHeight: slices.fold<double>(0, (sum, s) => sum + s.height),
    pageHeight: 400,
    topPadding: 8,
  );
}

void main() {
  testWidgets('语义层：读屏能读到标题与正文，标题带 header 标志（P4-27）', (tester) async {
    final handle = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 320,
              height: 400,
              child: ReaderSemanticsLayer(page: _page(), pageWidth: 320),
            ),
          ),
        ),
      );

      // 块文本进入了语义树（读屏可读），标题带 header。
      expect(
        tester.getSemantics(
          find.byKey(const ValueKey<String>('page-semantics-1')),
        ),
        matchesSemantics(
          label: '第一章 开局',
          isHeader: true,
          isReadOnly: true,
        ),
      );
      expect(
        tester.getSemantics(
          find.byKey(const ValueKey<String>('page-semantics-2')),
        ),
        matchesSemantics(label: '这是正文段落内容。', isReadOnly: true),
      );

      // 页面节点 + 两个块节点。
      expect(
        find.byKey(const ValueKey<String>('page-semantics-0')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('page-semantics-2')),
        findsOneWidget,
      );
    } finally {
      handle.dispose();
    }
  });

  testWidgets('焦点遍历顺序与朗读顺序一致（P4-28）', (tester) async {
    final firstFocus = FocusNode(debugLabel: 'first-block');
    addTearDown(firstFocus.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            height: 400,
            child: ReaderSemanticsLayer(
              page: _page(),
              pageWidth: 320,
              firstNodeFocus: firstFocus,
            ),
          ),
        ),
      ),
    );

    // 每个语义节点都包了 FocusTraversalOrder，顺序号与朗读顺序一致。
    final orders = tester
        .widgetList<FocusTraversalOrder>(find.byType(FocusTraversalOrder))
        .map((widget) => (widget.order as NumericFocusOrder).order)
        .toList();
    expect(orders, isNotEmpty);
    expect(orders, orderedEquals(<double>[...orders]..sort()));
    expect(orders.first, 0, reason: '页面节点在最前');

    // 首块焦点节点可以请求焦点。
    expect(firstFocus.canRequestFocus, isTrue);
    firstFocus.requestFocus();
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'first-block');
  });

  testWidgets('语义动作：页级下一页/上一页，块级复制本段（P4-29）', (tester) async {
    var next = 0;
    var previous = 0;
    final copied = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            height: 400,
            child: ReaderSemanticsLayer(
              page: _page(),
              pageWidth: 320,
              onNextPage: () => next++,
              onPreviousPage: () => previous++,
              onCopyBlock: copied.add,
            ),
          ),
        ),
      ),
    );

    // 页面级节点挂翻页动作。
    final pageNode = tester.widget<Semantics>(
      find.byKey(const ValueKey<String>('page-semantics-0')),
    );
    final pageActions = pageNode.properties.customSemanticsActions!;
    expect(
      pageActions.keys.map((action) => action.label),
      containsAll(<String>['下一页', '上一页']),
    );
    pageActions[ReaderSemanticsLayer.nextPageAction]!();
    pageActions[ReaderSemanticsLayer.previousPageAction]!();
    expect(<int>[next, previous], <int>[1, 1]);

    // 块级节点挂复制本段。
    final blockNode = tester.widget<Semantics>(
      find.byKey(const ValueKey<String>('page-semantics-1')),
    );
    final blockActions = blockNode.properties.customSemanticsActions!;
    expect(
      blockActions.keys.map((action) => action.label),
      contains('复制本段'),
    );
    blockActions[ReaderSemanticsLayer.copyBlockAction]!();
    expect(copied.single, '第一章 开局');
  });

  testWidgets('语义层外层是 IgnorePointer，不接收指针事件', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReaderSemanticsLayer(page: _page(), pageWidth: 320),
        ),
      ),
    );
    final ignorePointer = tester.widget<IgnorePointer>(
      find.descendant(
        of: find.byType(ReaderSemanticsLayer),
        matching: find.byType(IgnorePointer),
      ),
    );
    expect(ignorePointer.ignoring, isTrue);
  });
}
