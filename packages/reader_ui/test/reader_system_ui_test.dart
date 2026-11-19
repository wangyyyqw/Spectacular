import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/source/chapter_source.dart';
import 'package:reader_ui/menu/reader_menu_overlay.dart';
import 'package:reader_ui/reader_page.dart';
import 'package:reader_ui/reader_session.dart';
import 'package:reader_ui/reader_view.dart';
import 'package:reader_ui/system_ui.dart';
import 'package:reader_ui/theme/reader_theme.dart';

const _channel = MethodChannel('com.spectacular.reader_mobile/reader');

class _Source implements ReaderChapterSource {
  @override
  int get chapterCount => 1;

  @override
  Future<List<PageContent>> loadChapter(int spineIndex) async => [
    PageContent(
      spineIndex: spineIndex,
      pageIndex: 0,
      slices: const [],
      usedHeight: 0,
      pageHeight: 300,
      topPadding: 0,
    ),
  ];
}

ReaderPage _reader({bool editMode = false}) => ReaderPage(
  source: _Source(),
  store: MemoryReaderProgressStore(),
  bookId: 'system-bars',
  theme: ReaderTheme.white,
  editMode: editMode,
);

Widget _app({Widget? home, GlobalKey<NavigatorState>? navigator}) =>
    MaterialApp(navigatorKey: navigator, home: home ?? _reader());

Finder get _menu => find.byType(ReaderMenuOverlay);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final requests = <Map<Object?, Object?>>[];
  final platform = <MethodCall>[];

  setUp(() {
    requests.clear();
    platform.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          if (call.method == 'setSystemBars') {
            requests.add((call.arguments as Map).cast<Object?, Object?>());
          }
          return null;
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          platform.add(call);
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets('正文双隐藏，菜单和抽屉仅显示状态栏，关闭后恢复双隐藏', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    expect(requests.last, {'statusBar': false, 'navigationBar': false});
    await tester.tap(find.byType(ReaderView));
    await tester.pumpAndSettle();
    expect(requests.last, {'statusBar': true, 'navigationBar': false});
    expect(tester.widget<ReaderMenuOverlay>(_menu).open, isTrue);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Container &&
            widget.constraints?.maxWidth == 118 &&
            widget.constraints?.maxHeight == 4.5,
      ),
      findsNothing,
    );
    await tester.tap(find.byKey(const ValueKey('menu-entry-theme')));
    await tester.pumpAndSettle();
    expect(requests.last, {'statusBar': true, 'navigationBar': false});
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(requests.last, {'statusBar': false, 'navigationBar': false});
    expect(
      platform.where(
        (call) => call.method == 'SystemChrome.setEnabledSystemUIOverlays',
      ),
      isEmpty,
    );
  });

  testWidgets('其他路由显示两栏，返回菜单及退出阅读恢复各自状态', (tester) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      _app(
        home: const Scaffold(body: Text('书架')),
        navigator: navigator,
      ),
    );
    navigator.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => _reader()),
    );
    await tester.pumpAndSettle();
    expect(requests.last, {'statusBar': false, 'navigationBar': false});
    await tester.tap(find.byType(ReaderView));
    await tester.pumpAndSettle();
    final count = requests.length;
    navigator.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => _reader(editMode: true)),
    );
    await tester.pumpAndSettle();
    expect(
      requests.skip(count),
      everyElement({'statusBar': true, 'navigationBar': true}),
    );
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(requests.last, {'statusBar': true, 'navigationBar': false});
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.text('书架'), findsOneWidget);
    expect(requests.last, {'statusBar': true, 'navigationBar': true});
  });

  testWidgets('独立弹层显示两栏，返回菜单及关闭菜单恢复各自状态', (tester) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_app(navigator: navigator));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ReaderView));
    await tester.pumpAndSettle();
    unawaited(
      showDialog<void>(
        context: tester.element(find.byType(ReaderPage)),
        builder: (_) => const AlertDialog(content: Text('独立弹层')),
      ),
    );
    await tester.pumpAndSettle();
    expect(requests.last, {'statusBar': true, 'navigationBar': true});
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(requests.last, {'statusBar': true, 'navigationBar': false});
    await tester.tapAt(tester.getCenter(find.byType(ReaderView)));
    await tester.pumpAndSettle();
    expect(requests.last, {'statusBar': false, 'navigationBar': false});
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(requests.last, {'statusBar': true, 'navigationBar': true});
  });

  testWidgets('编辑预览不隐藏系统栏，重建和释放预览不更改已有显隐', (tester) async {
    await tester.pumpWidget(_app(home: _reader(editMode: true)));
    await tester.pumpAndSettle();
    expect(requests, [
      {'statusBar': true, 'navigationBar': true},
    ]);
    await tester.pumpWidget(_app(home: _reader(editMode: true)));
    await tester.pumpAndSettle();
    expect(requests, hasLength(1));
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(requests, hasLength(1));
  });

  testWidgets('状态栏图标随阅读菜单日夜主题切换，避免背景与图标同色', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ReaderView));
    await tester.pumpAndSettle();
    SystemUiOverlayStyle style() => tester
        .widget<AnnotatedRegion<SystemUiOverlayStyle>>(
          find.descendant(
            of: find.byType(ReaderPage),
            matching: find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
          ),
        )
        .value;
    expect(style().statusBarIconBrightness, Brightness.dark);
    expect(style().systemNavigationBarIconBrightness, Brightness.dark);
    await tester.tap(find.byKey(const ValueKey('menu-daynight')));
    await tester.pumpAndSettle();
    expect(style().statusBarIconBrightness, Brightness.light);
    expect(style().statusBarBrightness, Brightness.dark);
    expect(requests.last, {'statusBar': true, 'navigationBar': false});
  });

  testWidgets('前台恢复和键盘关闭后恢复当前菜单显隐', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ReaderView));
    await tester.pumpAndSettle();
    final count = requests.length;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(requests, hasLength(count + 1));
    expect(requests.last, {'statusBar': true, 'navigationBar': false});
    addTearDown(tester.view.resetViewInsets);
    tester.view.viewInsets = const FakeViewPadding(bottom: 200);
    await tester.pump();
    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(requests, hasLength(count + 2));
    expect(requests.last, {'statusBar': true, 'navigationBar': false});
  });

  testWidgets('菜单按实时状态栏安全区避让，正文边距不随系统栏改变', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    final before = tester.getRect(find.byType(ReaderView));
    addTearDown(tester.view.resetViewPadding);
    tester.view.viewPadding = const FakeViewPadding(top: 30);
    await tester.pump();
    await tester.tap(find.byType(ReaderView));
    await tester.pumpAndSettle();
    final menu = tester.widget<ReaderMenuOverlay>(_menu);
    expect(menu.safeTop, 30);
    expect(menu.safeBottom, 0);
    expect(tester.getRect(find.byType(ReaderView)), before);
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('menu-back'))).dy,
      greaterThanOrEqualTo(30),
    );
  });

  test('没有 Android 通道时使用 Flutter 对应的系统栏配置', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
    for (final bars in [
      (status: false, navigation: false),
      (status: true, navigation: false),
      (status: true, navigation: true),
    ]) {
      await setReaderSystemBars(
        statusBar: bars.status,
        navigationBar: bars.navigation,
      );
    }
    expect(platform.map((call) => call.method), [
      'SystemChrome.setEnabledSystemUIOverlays',
      'SystemChrome.setEnabledSystemUIOverlays',
      'SystemChrome.setEnabledSystemUIMode',
    ]);
    expect(platform.map((call) => call.arguments), [
      <String>[],
      ['SystemUiOverlay.top'],
      'SystemUiMode.edgeToEdge',
    ]);
  });
}
