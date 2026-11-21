import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/home/profile_page.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/rea_micro/rea_micro_controller.dart';

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

  testWidgets('账号与同步中社区入口位于野社入口下方', (tester) async {
    final library = LibraryStore.memory();
    final controller = ReaMicroController(
      library: library,
      enableLanLoginServer: false,
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ProfilePage(library: library, reaMicro: controller),
      ),
    );
    await tester.pumpAndSettle();

    final community = find.byKey(const ValueKey<String>('community-entry'));
    await tester.scrollUntilVisible(
      community,
      220,
      scrollable: find.byType(Scrollable).first,
    );
    expect(community, findsOneWidget);
    expect(find.byKey(const ValueKey<String>('ye-she-entry')), findsOneWidget);
    expect(
      tester.getTopLeft(community).dy,
      greaterThan(
        tester
            .getTopLeft(find.byKey(const ValueKey<String>('ye-she-entry')))
            .dy,
      ),
    );
  });
}
