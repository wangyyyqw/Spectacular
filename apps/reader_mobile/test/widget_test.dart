import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/main.dart';

void main() {
  testWidgets('应用壳启动为空白页', (tester) async {
    await tester.pumpWidget(const ReaderApp());
    expect(find.byType(Scaffold), findsOneWidget);
    expect(find.byType(SizedBox), findsWidgets);
  });
}
