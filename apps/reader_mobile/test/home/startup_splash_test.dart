import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/home/app_brand_icon.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/main.dart';
import 'package:reader_ui/reader_session.dart';

import '../support/reader_pump.dart';

void main() {
  testWidgets('应用首屏就绪后立即进入书架，无自绘启动图标或额外点击拦截', (tester) async {
    var ready = 0;
    await tester.pumpWidget(
      ReaderApp(
        library: LibraryStore.memory(),
        progressStore: MemoryReaderProgressStore(),
        onStartupReady: () => ready++,
      ),
    );
    await pumpReaderUntilComplete(
      tester,
      () => find.byType(BottomNavigationBar).evaluate().isNotEmpty,
    );
    expect(ready, 1);
    expect(find.byType(AppBrandIcon), findsNothing);
    expect(find.text('阅微 Extend'), findsNothing);
    await tester.tap(find.text('统计'));
    await tester.pump();
    expect(
      tester
          .widget<BottomNavigationBar>(find.byType(BottomNavigationBar))
          .currentIndex,
      1,
    );
    expect(ready, 1);
    expect(tester.takeException(), isNull);
  });
}
