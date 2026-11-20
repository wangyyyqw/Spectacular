import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_ui/panels/toc_panel.dart';

void main() {
  testWidgets('宿主未提供章节规则时隐藏入口，提供后点击调用且窄屏不溢出', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var opened = 0;
    Widget page(VoidCallback? callback) => MaterialApp(
      home: Scaffold(
        body: TocPanel(
          entries: const [],
          currentSpineIndex: 0,
          onSelect: (_) {},
          onChapterRules: callback,
        ),
      ),
    );
    await tester.pumpWidget(page(null));
    expect(find.text('章节正则'), findsNothing);
    await tester.pumpWidget(page(() => opened++));
    await tester.tap(find.byKey(const ValueKey('toc-chapter-rules')));
    expect(opened, 1);
    expect(tester.takeException(), isNull);
  });
}
