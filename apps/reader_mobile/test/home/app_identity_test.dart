import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:reader_mobile/home/profile_page.dart';
import 'package:reader_mobile/home/welcome_announcement.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/main.dart';
import 'package:reader_mobile/rea_micro/rea_micro_page.dart';
import 'package:reader_ui/reader_session.dart';

import '../support/reader_pump.dart';

void main() {
  testWidgets('应用启用公告时先等待确认，再初始化账号并进入必需登录页', (tester) async {
    await tester.pumpWidget(
      ReaderApp(
        library: LibraryStore.memory(),
        progressStore: MemoryReaderProgressStore(),
        showWelcomeAnnouncement: true,
      ),
    );
    await pumpReaderUntil(tester, find.byType(WelcomeAnnouncementDialog));
    final profile = tester.widget<ProfilePage>(
      find.byType(ProfilePage, skipOffstage: false),
    );
    expect(profile.reaMicro!.initialized, isFalse);
    await tester.tap(find.byKey(const ValueKey('welcome-agree-login')));
    await pumpReaderUntil(tester, find.text('连接阅微'));
    expect(profile.reaMicro!.initialized, isTrue);
    expect(find.byType(ReaMicroPage), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(ReaMicroPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('应用名称保留阅微Extend，未登录我的页使用墨白图标与登录提示', (tester) async {
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
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).title,
      '阅微Extend',
    );
    await tester.tap(
      find.descendant(
        of: find.byType(BottomNavigationBar),
        matching: find.text('我的'),
      ),
    );
    await pumpReaderUntil(tester, find.text('登录后查看阅读时长与阅微 ID'));
    expect(find.text('登录阅微'), findsOneWidget);
    final icon = tester.widget<Image>(
      find.descendant(
        of: find.byType(ProfilePage),
        matching: find.byType(Image),
      ),
    );
    expect(icon.image, const AssetImage('assets/branding/app_icon.png'));
    expect(tester.takeException(), isNull);
  });
}
