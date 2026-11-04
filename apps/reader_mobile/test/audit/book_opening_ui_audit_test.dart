import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/reader/book_opening_view.dart';
import 'package:reader_mobile/theme/app_theme.dart';

final _book = BookEntry(
  id: '开书界面审计',
  title: '山海之间的一段漫长阅读旅程',
  author: '测试作者',
  filePath: '',
  addedAt: DateTime(2026, 11, 4),
);

Future<void> _showRoute(WidgetTester tester, bool disableAnimations) async {
  await tester.pumpWidget(
    MaterialApp(
      key: UniqueKey(),
      theme: buildAppTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(disableAnimations: disableAnimations),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push<void>(
              PageRouteBuilder(
                transitionDuration: Duration.zero,
                reverseTransitionDuration: Duration.zero,
                pageBuilder: (_, _, _) => BookOpeningView(book: _book),
              ),
            ),
            child: const Text('打开测试书籍'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开测试书籍'));
  await tester.pump();
}

void main() {
  testWidgets('窄屏开书动画完成后显示完整反馈和纵向小圆角封面', (tester) async {
    tester.view.physicalSize = const Size(320, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _showRoute(tester, false);
    await tester.pump(BookOpeningView.revealDuration);
    final page = find.byType(BookOpeningView);
    expect(find.text(_book.title), findsOneWidget);
    expect(find.text('正在打开'), findsOneWidget);
    expect(find.byTooltip('取消打开'), findsOneWidget);
    final cover = find.descendant(of: page, matching: find.byType(ClipRRect));
    final size = tester.getSize(cover);
    expect(size.width / size.height, closeTo(3 / 4, 0.001));
    expect(
      tester.widget<ClipRRect>(cover).borderRadius,
      const BorderRadius.all(Radius.circular(4)),
    );
    for (final box in tester.widgetList<DecoratedBox>(
      find.descendant(of: page, matching: find.byType(DecoratedBox)),
    )) {
      if (box.decoration case final BoxDecoration decoration) {
        expect(decoration.gradient, isNull);
        expect(decoration.boxShadow, isNull);
      }
    }
    final opacities = tester.widgetList<Opacity>(
      find.descendant(of: page, matching: find.byType(Opacity)),
    );
    expect(opacities.every((opacity) => opacity.opacity == 1), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('开书期间可取消，关闭系统动画时反馈立即可见', (tester) async {
    for (final disabled in [false, true]) {
      await _showRoute(tester, disabled);
      if (disabled) {
        final opacities = tester.widgetList<Opacity>(
          find.descendant(
            of: find.byType(BookOpeningView),
            matching: find.byType(Opacity),
          ),
        );
        expect(opacities.every((opacity) => opacity.opacity == 1), isTrue);
      }
      await tester.tap(find.byTooltip('取消打开'));
      await tester.pumpAndSettle();
      expect(find.byType(BookOpeningView), findsNothing);
      expect(find.text('打开测试书籍'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
}
