import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/home/startup_splash.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/main.dart';
import 'package:reader_ui/reader_session.dart';

void main() {
  testWidgets('冷启动先显示开屏，约 0.8 秒后露出可操作的书架', (tester) async {
    await tester.pumpWidget(
      ReaderApp(
        library: LibraryStore.memory(),
        progressStore: MemoryReaderProgressStore(),
      ),
    );
    await tester.pump();
    expect(find.byType(StartupSplash), findsOneWidget);

    // 开屏期间拦截点击，避免误触书架。
    await tester.tap(find.text('统计'), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      tester
          .widget<BottomNavigationBar>(find.byType(BottomNavigationBar))
          .currentIndex,
      0,
    );

    await tester.pump(StartupSplash.duration);
    await tester.pump();
    expect(find.byType(StartupSplash), findsNothing);

    await tester.tap(find.text('统计'));
    await tester.pump();
    expect(
      tester
          .widget<BottomNavigationBar>(find.byType(BottomNavigationBar))
          .currentIndex,
      1,
    );
    expect(tester.takeException(), isNull);
  });
}
