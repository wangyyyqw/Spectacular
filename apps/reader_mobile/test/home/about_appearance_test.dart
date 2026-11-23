import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:reader_mobile/home/about_page.dart';
import 'package:reader_mobile/home/app_settings_page.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/reader/reader_settings.dart';
import 'package:reader_mobile/home/welcome_announcement.dart';

void main() {
  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: '阅微 Extend',
      packageName: 'com.spectacular.reamicro',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  testWidgets('外观保存墨水屏偏好，关于入口进入独立页面', (tester) async {
    final library = LibraryStore.memory();
    await tester.pumpWidget(
      MaterialApp(home: AppSettingsPage(library: library)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('appearance-ink-mode')));
    await tester.pumpAndSettle();
    expect((await ReaderSettingsStore(library).load()).inkMode, isTrue);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('about-entry')),
      250,
    );
    await tester.tap(find.byKey(const ValueKey('about-entry')));
    await tester.pumpAndSettle();
    expect(find.byType(AboutPage), findsOneWidget);
    expect(find.text('Ver 1.0.0 (1)'), findsOneWidget);
    expect(find.textContaining('构建时间：'), findsOneWidget);
  });

  testWidgets('关于链接沿用阅微，公告只显示内容可返回，窄屏大字号不溢出', (tester) async {
    tester.view.physicalSize = const Size(320, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final links = <Uri>[];
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(1.5)),
          child: child!,
        ),
        home: AboutPage(onOpenLink: (uri) async => links.add(uri)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('阅微用户协议'));
    await tester.tap(find.text('阅微用户协议'));
    await tester.ensureVisible(find.text('阅微隐私政策'));
    await tester.tap(find.text('阅微隐私政策'));
    expect(links.map((uri) => uri.toString()), [
      AboutPage.agreementUrl,
      AboutPage.privacyUrl,
    ]);
    await tester.ensureVisible(find.widgetWithText(ListTile, '阅微 Extend'));
    await tester.tap(find.widgetWithText(ListTile, '阅微 Extend'));
    await tester.pumpAndSettle();
    expect(find.byType(WelcomeAnnouncementDialog), findsOneWidget);
    expect(find.byKey(const ValueKey('welcome-agree-login')), findsNothing);
    expect(find.byKey(const ValueKey('welcome-disagree-exit')), findsNothing);
    Navigator.of(tester.element(find.byType(WelcomeAnnouncementDialog))).pop();
    await tester.pumpAndSettle();
    expect(find.byType(WelcomeAnnouncementDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
