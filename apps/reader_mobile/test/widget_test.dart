import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/api.dart';
import 'package:reader_mobile/main.dart';
import 'package:reader_ui/reader_page.dart';
import 'package:reader_ui/reader_session.dart';

void main() {
  testWidgets('应用启动后进入最小阅读页', (tester) async {
    await tester.pumpWidget(ReaderApp(store: MemoryReaderProgressStore()));
    await tester.pumpAndSettle();
    expect(find.byType(Scaffold), findsOneWidget);
    expect(find.byType(ReaderPage), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
    expect(find.byTooltip('导出日志'), findsOneWidget);

    // 测试环境没有分享插件/可写目录时，导出应显示失败提示而不是崩溃。
    await tester.tap(find.byTooltip('导出日志'));
    await tester.pumpAndSettle();
    expect(find.textContaining('日志导出失败'), findsOneWidget);
  });

  test('宿主可导入核心契约', () {
    expect(CancelToken().isCancelled, isFalse);
  });
}
