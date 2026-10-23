import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/api.dart';
import 'package:reader_mobile/main.dart';
import 'package:reader_ui/reader_page.dart';

void main() {
  testWidgets('应用启动后进入最小阅读页', (tester) async {
    await tester.pumpWidget(const ReaderApp());
    await tester.pumpAndSettle();
    expect(find.byType(Scaffold), findsOneWidget);
    expect(find.byType(ReaderPage), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
    expect(find.byTooltip('导出日志'), findsOneWidget);
  });

  test('宿主可导入核心契约', () {
    expect(CancelToken().isCancelled, isFalse);
  });
}
