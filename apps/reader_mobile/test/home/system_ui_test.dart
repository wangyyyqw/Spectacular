import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/main.dart';
import 'package:reader_ui/reader_session.dart';

Future<void> _pumpApp(WidgetTester tester) async {
  for (var frame = 0; frame < 4; frame++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _showApp(WidgetTester tester) async {
  await tester.pumpWidget(
    ReaderApp(
      library: LibraryStore.memory(),
      progressStore: MemoryReaderProgressStore(),
    ),
  );
  await _pumpApp(tester);
}

Iterable<AnnotatedRegion<SystemUiOverlayStyle>> _regions(WidgetTester tester) =>
    tester.widgetList<AnnotatedRegion<SystemUiOverlayStyle>>(
      find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
    );

void main() {
  testWidgets('应用四页保留可见的状态栏和导航栏图标样式', (tester) async {
    await _showApp(tester);
    for (final label in ['书架', '统计', '书评', '我的']) {
      await tester.tap(
        find.descendant(
          of: find.byType(BottomNavigationBar),
          matching: find.text(label),
        ),
      );
      await _pumpApp(tester);
      final region = _regions(tester).first;
      expect(region.value.statusBarIconBrightness, Brightness.dark);
      expect(region.value.systemNavigationBarIconBrightness, Brightness.dark);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('独立页面继承应用导航栏图标样式，状态栏图标与页面背景形成对比', (tester) async {
    await _showApp(tester);
    tester
        .state<NavigatorState>(find.byType(Navigator))
        .push(
          MaterialPageRoute<void>(
            builder: (_) => Scaffold(appBar: AppBar(title: const Text('独立页面'))),
          ),
        );
    await _pumpApp(tester);
    final regions = _regions(tester);
    expect(
      regions.first.value.systemNavigationBarIconBrightness,
      Brightness.dark,
    );
    expect(regions.last.value.statusBarIconBrightness, Brightness.dark);
    expect(tester.takeException(), isNull);
  });
}
