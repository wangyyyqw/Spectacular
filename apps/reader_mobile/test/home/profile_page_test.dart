import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/home/profile_page.dart';
import 'package:reader_mobile/library/library_store.dart';

void main() {
  testWidgets('我的页可查看诊断日志且不显示浮动提示', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: ProfilePage(library: LibraryStore.memory())),
    );
    await tester.pumpAndSettle();
    expect(find.text('查看诊断日志'), findsOneWidget);

    await tester.tap(find.text('查看诊断日志'));
    await tester.pumpAndSettle();
    expect(find.text('诊断日志'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
  });
}
