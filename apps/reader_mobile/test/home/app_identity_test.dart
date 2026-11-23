import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:reader_mobile/home/profile_page.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/main.dart';
import 'package:reader_ui/reader_session.dart';

import '../support/reader_pump.dart';

void main() {
  testWidgets('应用标题与我的页保留现有名称并使用附件图标', (tester) async {
    PackageInfo.setMockInitialValues(
      appName: '阅微Extend',
      packageName: 'com.spectacular.reamicro',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
    await tester.pumpWidget(
      ReaderApp(
        library: LibraryStore.memory(),
        progressStore: MemoryReaderProgressStore(),
      ),
    );
    await pumpReaderUntil(tester, find.text('书架还是空的'));
    expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).title, '阅微Extend');
    await tester.tap(
      find.descendant(
        of: find.byType(BottomNavigationBar),
        matching: find.text('我的'),
      ),
    );
    await pumpReaderUntil(tester, find.text('版本 1.0.0 · 1'));
    expect(find.text('Spectacular Reader'), findsOneWidget);
    final icon = tester.widget<Image>(
      find.descendant(
        of: find.byType(ProfilePage),
        matching: find.byType(Image),
      ),
    );
    expect(
      (icon.image as ResizeImage).imageProvider,
      const AssetImage('assets/branding/app_icon.png'),
    );
    expect(tester.takeException(), isNull);
  });
}
