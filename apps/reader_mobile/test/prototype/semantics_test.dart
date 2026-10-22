import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/prototype/semantics_demo.dart';

void main() {
  testWidgets('5 个段落按阅读顺序暴露语义标签', (tester) async {
    final handle = tester.ensureSemantics();

    await tester.pumpWidget(const MaterialApp(home: SemanticsDemoPage()));
    await tester.pumpAndSettle();

    for (final paragraph in SemanticsDemoPage.paragraphs) {
      expect(find.bySemanticsLabel(paragraph), findsOneWidget);
    }

    // ignore: deprecated_member_use
    final dump = tester.binding.pipelineOwner.semanticsOwner!.rootSemanticsNode!
        .toStringDeep();

    var cursor = -1;
    for (final paragraph in SemanticsDemoPage.paragraphs) {
      final index = dump.indexOf(paragraph);
      expect(index, greaterThan(cursor), reason: '语义顺序错误：$paragraph');
      cursor = index;
    }

    handle.dispose();
  });
}
