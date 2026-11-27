import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_ui/theme/reader_ui_components.dart';

void main() {
  testWidgets('公共提示条自动暴露动态播报语义并保留重试操作', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      var retries = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => ReaderInlineNotice(
                message: retries == 0 ? '字体加载失败' : '字体仍无法读取',
                isError: true,
                trailing: TextButton(
                  onPressed: () => setState(() => retries++),
                  child: const Text('重试'),
                ),
              ),
            ),
          ),
        ),
      );
      final banner = find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.liveRegion == true,
      );
      expect(banner, findsOneWidget);
      expect(
        tester.getSemantics(find.text('字体加载失败')),
        matchesSemantics(
          label: '字体加载失败',
          isLiveRegion: true,
          textDirection: TextDirection.ltr,
        ),
      );
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
      expect(retries, 1);
      expect(banner, findsOneWidget);
      expect(find.text('字体仍无法读取'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });
}
