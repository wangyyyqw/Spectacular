import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/home/startup_splash.dart';
import 'package:reader_mobile/home/app_brand_icon.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/main.dart';
import 'package:reader_ui/reader_session.dart';

import '../support/reader_pump.dart';

void main() {
  testWidgets('主题尚未恢复时首帧已绘制图标，等待期间不隐藏或结束开屏', (tester) async {
    var finished = 0;
    Widget splash(bool ready) => Directionality(
      textDirection: TextDirection.ltr,
      child: Theme(
        data: ThemeData(),
        child: StartupSplash(ready: ready, onFinished: () => finished++),
      ),
    );
    await tester.pumpWidget(splash(false));
    final icon = find.byType(AppBrandIcon);
    expect(icon, findsOneWidget);
    void expectVisible() {
      final opacity = find.ancestor(of: icon, matching: find.byType(Opacity));
      for (final element in opacity.evaluate()) {
        expect((element.widget as Opacity).opacity, 1);
      }
      expect(find.text('阅微 Extend'), findsOneWidget);
    }

    expectVisible();
    await tester.pump(const Duration(seconds: 3));
    expectVisible();
    expect(finished, 0);
    await tester.pumpWidget(splash(true));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(finished, 1);
  });

  testWidgets('冷启动先显示开屏，约 0.8 秒后露出可操作的书架', (tester) async {
    await tester.pumpWidget(
      ReaderApp(
        library: LibraryStore.memory(),
        progressStore: MemoryReaderProgressStore(),
      ),
    );
    await pumpReaderUntilComplete(
      tester,
      () => find.byType(BottomNavigationBar).evaluate().isNotEmpty,
    );
    expect(find.byType(StartupSplash), findsOneWidget);
    expect(find.text('阅微 Extend'), findsOneWidget);
    expect(find.byType(AppBrandIcon), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(StartupSplash),
        matching: find.byType(Image),
      ),
      findsNothing,
    );

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
