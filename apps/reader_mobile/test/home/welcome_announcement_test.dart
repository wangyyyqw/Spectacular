import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/home/welcome_announcement.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/rea_micro/rea_micro_controller.dart';
import 'package:reader_mobile/rea_micro/rea_micro_models.dart';
import 'package:reader_mobile/rea_micro/rea_micro_page.dart';
import 'package:reader_mobile/rea_micro/rea_micro_store.dart';

class _Controller extends ReaMicroController {
  _Controller()
    : super(library: LibraryStore.memory(), enableLanLoginServer: false);
  int initializations = 0;
  bool loggedIn = false;
  @override
  bool get signedIn => loggedIn;
  @override
  bool get initialized => true;
  @override
  ReaMicroUser? get user =>
      loggedIn ? const ReaMicroUser(id: 123, nickName: '测试读者') : null;
  @override
  Future<void> initialize() async {
    initializations++;
  }

  @override
  Future<void> refreshIfStale({
    Duration maxAge = const Duration(minutes: 5),
  }) async {}
  void completeLogin() {
    loggedIn = true;
    notifyListeners();
  }
}

Future<void> _pumpFlow(
  WidgetTester tester,
  LibraryStore library,
  _Controller controller, {
  Future<void> Function()? onExit,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) {
          return TextButton(
            onPressed: () => unawaited(
              runWelcomeFlow(
                context: context,
                library: library,
                controller: controller,
                onExit: onExit,
              ),
            ),
            child: const Text('书架启动'),
          );
        },
      ),
    ),
  );
  await tester.tap(find.text('书架启动'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('本次更新旧账号仍弹公告，同意保存后直接进入书架且下次不弹', (tester) async {
    final library = LibraryStore.memory();
    await ReaMicroStore(library).saveToken('测试令牌');
    final controller = _Controller();
    addTearDown(controller.dispose);
    await _pumpFlow(tester, library, controller);
    expect(find.text('欢迎使用阅微 Extend'), findsOneWidget);
    expect(controller.initializations, 0);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(WelcomeAnnouncementDialog), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('welcome-agree-login')));
    await tester.pumpAndSettle();
    expect(
      await library.getSetting(welcomeAgreementKey),
      welcomeAgreementRevision,
    );
    expect(controller.initializations, 1);
    expect(find.byType(ReaMicroPage), findsNothing);
    expect(find.text('书架启动'), findsOneWidget);
    await tester.tap(find.text('书架启动'));
    await tester.pumpAndSettle();
    expect(find.byType(WelcomeAnnouncementDialog), findsNothing);
  });

  testWidgets('未登录同意后进入登录页，返回不能跳过，登录成功回书架', (tester) async {
    final library = LibraryStore.memory();
    final controller = _Controller();
    addTearDown(controller.dispose);
    await _pumpFlow(tester, library, controller);
    await tester.tap(find.byKey(const ValueKey('welcome-agree-login')));
    await tester.pumpAndSettle();
    expect(find.byType(ReaMicroPage), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(ReaMicroPage), findsOneWidget);
    controller.completeLogin();
    await tester.pumpAndSettle();
    expect(find.byType(ReaMicroPage), findsNothing);
    expect(find.text('书架启动'), findsOneWidget);
  });

  testWidgets('已确认但未登录的再次启动仍要求登录', (tester) async {
    final library = LibraryStore.memory();
    await library.setSetting(welcomeAgreementKey, welcomeAgreementRevision);
    final controller = _Controller();
    addTearDown(controller.dispose);
    await _pumpFlow(tester, library, controller);
    expect(find.byType(WelcomeAnnouncementDialog), findsNothing);
    expect(find.byType(ReaMicroPage), findsOneWidget);
    controller.completeLogin();
    await tester.pumpAndSettle();
  });

  testWidgets('拒绝只退出，不保存协议或初始化账号', (tester) async {
    final library = LibraryStore.memory();
    final controller = _Controller();
    addTearDown(controller.dispose);
    var exits = 0;
    await _pumpFlow(
      tester,
      library,
      controller,
      onExit: () async {
        exits++;
      },
    );
    await tester.tap(find.byKey(const ValueKey('welcome-disagree-exit')));
    await tester.pumpAndSettle();
    expect(exits, 1);
    expect(await library.getSetting(welcomeAgreementKey), isNull);
    expect(controller.initializations, 0);
  });

  testWidgets('公告保留三个可打开的准确链接，大字号窄屏可滚动且按钮可见', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final opened = <Uri>[];
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          body: WelcomeAnnouncementDialog(
            onAgree: () async {},
            onExit: () async {},
            onOpenLink: (uri) async => opened.add(uri),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final rich = tester.widget<Text>(
      find.byWidgetPredicate(
        (widget) => widget is Text && widget.textSpan != null,
      ),
    );
    final spans = (rich.textSpan! as TextSpan).children!
        .whereType<TextSpan>()
        .toList();
    for (final span in spans.where((span) => span.recognizer != null)) {
      (span.recognizer! as TapGestureRecognizer).onTap!();
    }
    await tester.pump();
    expect(opened.map((uri) => uri.toString()), [
      'https://github.com/wangyyyqw/Spectacular',
      'https://www.zhendong.ltd',
      'https://github.com/YGHFv/ReaMicro-Extend',
    ]);
    final content = (rich.textSpan! as TextSpan).toPlainText();
    expect(content, contains('本项目非阅微官方作品'));
    expect(content, contains('24 小时内自行删除'));
    expect(find.byKey(const ValueKey('welcome-agree-login')), findsOneWidget);
    final buttonRect = tester.getRect(
      find.byKey(const ValueKey('welcome-agree-login')),
    );
    expect(buttonRect.top, greaterThanOrEqualTo(0));
    expect(buttonRect.bottom, lessThanOrEqualTo(640));
    final scroll = tester.state<ScrollableState>(
      find.descendant(
        of: find.byKey(const ValueKey('welcome-announcement-content')),
        matching: find.byType(Scrollable),
      ),
    );
    expect(scroll.position.maxScrollExtent, greaterThan(0));
    scroll.position.jumpTo(scroll.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(scroll.position.extentAfter, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('保存确认失败时保留公告并允许重试', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WelcomeAnnouncementDialog(
            onAgree: () async => throw StateError('保存失败'),
            onExit: () async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('welcome-agree-login')));
    await tester.pumpAndSettle();
    expect(find.text('保存确认失败，请重试'), findsOneWidget);
    expect(find.byType(WelcomeAnnouncementDialog), findsOneWidget);
  });
}
