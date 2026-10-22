import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:reader_mobile/prototype/semantics_demo.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('P0-21 5 个段落的语义标签与阅读顺序', (tester) async {
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

    // ignore: avoid_print
    print(
      'P0-21 semantics_labels=${SemanticsDemoPage.paragraphs.length} '
      'order=ok',
    );

    handle.dispose();
  });
}
