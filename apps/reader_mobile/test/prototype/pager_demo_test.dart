import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/prototype/pager_demo.dart';

void main() {
  testWidgets('初始为第 1 页，共 200 页', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: PagerDemoPage()));
    expect(find.text('第 1 页'), findsOneWidget);
    expect(find.textContaining('第 1/200 页'), findsOneWidget);
  });

  testWidgets('左滑翻到第 2 页，页码同步', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: PagerDemoPage()));
    await tester.fling(find.byType(PageView), const Offset(-400, 0), 1200);
    await tester.pumpAndSettle();
    expect(find.text('第 2 页'), findsOneWidget);
    expect(find.textContaining('第 2/200 页'), findsOneWidget);
  });

  testWidgets('可跳转到最后一页并准确显示', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: PagerDemoPage()));
    final pageView = tester.widget<PageView>(find.byType(PageView));
    pageView.controller!.jumpToPage(199);
    await tester.pumpAndSettle();
    expect(find.text('第 200 页'), findsOneWidget);
    expect(find.textContaining('第 200/200 页'), findsOneWidget);
  });
}
