import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/home/startup_splash.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/main.dart';
import 'package:reader_ui/reader_session.dart';

void main() {
  testWidgets('开屏图标可以在 Flutter 首帧前预解码', (tester) async {
    await tester.runAsync(preloadStartupSplashIcon);
    expect(tester.takeException(), isNull);
  });

  testWidgets('冷启动先显示开屏，约 0.8 秒后露出可操作的书架', (tester) async {
    await tester.pumpWidget(
      ReaderApp(
        library: LibraryStore.memory(),
        progressStore: MemoryReaderProgressStore(),
      ),
    );
    // 推进偏好、书架和首帧就绪回调，但不推进动画时钟。
    for (var frame = 0; frame < 4; frame++) {
      await tester.pump();
    }
    expect(find.byType(StartupSplash), findsOneWidget);
    expect(
      tester.widget<StartupSplash>(find.byType(StartupSplash)).ready,
      isTrue,
    );

    // 开屏期间拦截点击，避免误触书架。
    final statsTab = find.descendant(
      of: find.byType(BottomNavigationBar),
      matching: find.text('统计'),
    );
    await tester.tap(statsTab, warnIfMissed: false);
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

    await tester.tap(statsTab);
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
