import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_ui/icons/app_icon.dart';
import 'package:reader_ui/menu/reader_menu_overlay.dart';

Finder _button(String name) => find.byKey(ValueKey('menu-$name'));

Finder _icon(String name) =>
    find.descendant(of: _button(name), matching: find.byType(AppIcon));

double _settingsRight(WidgetTester tester) {
  final label = tester.renderObject<RenderBox>(
    find.descendant(
      of: find.byKey(const ValueKey('menu-entry-settings')),
      matching: find.text('设置'),
    ),
  );
  return label.localToGlobal(label.size.bottomRight(Offset.zero)).dx;
}

void main() {
  for (final (width, scale, title, extras) in [
    (384.0, 1.0, '资治通鉴', false),
    (320.0, 2.0, '很长的书名在操作按钮前省略，不能挤开右侧入口', false),
    (800.0, 1.0, '桌面阅读', true),
  ]) {
    testWidgets('$width 宽度下阅读操作组对齐设置，大字号保留完整点击区域', (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final calls = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: Size(width, 800),
              textScaler: TextScaler.linear(scale),
              disableAnimations: true,
            ),
            child: ReaderMenuOverlay(
              open: true,
              theme: null,
              bookTitle: title,
              progress: .1,
              chapterLabel: '第一章',
              onBack: () => calls.add('back'),
              onToggleDayNight: () => calls.add('daynight'),
              nightMode: false,
              onAddBookmark: () => calls.add('add-bookmark'),
              onTts: () => calls.add('tts'),
              onEdit: extras ? () => calls.add('edit') : null,
              onShowShortcuts: extras ? () {} : null,
              onPreviousChapter: null,
              onNextChapter: null,
              onSeek: (_) {},
              onEntry: (_) {},
              drawerTitle: '',
              drawerChild: null,
              onCloseDrawer: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final actions = ['daynight', 'add-bookmark', if (extras) 'edit', 'tts'];
      final iconRight = tester.getRect(_icon('tts')).right;
      if (scale == 1) {
        expect(iconRight, closeTo(_settingsRight(tester), .01));
      } else {
        // 超大字号把“设置”撑到屏幕边缘时，按钮仍完整保留在屏内。
        expect(tester.getRect(_button('tts')).right, closeTo(width, .01));
        expect(_settingsRight(tester) - iconRight, inInclusiveRange(0, 10));
      }
      expect(
        tester.getRect(find.text(title)).right,
        lessThanOrEqualTo(tester.getRect(_button(actions.first)).left),
      );
      for (var index = 0; index < actions.length; index++) {
        final button = _button(actions[index]);
        final rect = tester.getRect(button);
        expect(rect.width, greaterThanOrEqualTo(40));
        expect(rect.height, greaterThanOrEqualTo(40));
        if (index > 0) {
          expect(
            rect.left,
            closeTo(tester.getRect(_button(actions[index - 1])).right, .01),
          );
        }
        expect(tester.getSize(_icon(actions[index])), const Size.square(22));
        await tester.tap(button);
      }
      expect(calls, actions);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('日间与已有书签状态仍使用对应图标和提示，缺少听书时末尾不留空位', (tester) async {
    await tester.binding.setSurfaceSize(const Size(384, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderMenuOverlay(
          open: true,
          theme: null,
          bookTitle: '资治通鉴',
          progress: .1,
          chapterLabel: '第一章',
          onBack: () {},
          onToggleDayNight: () {},
          nightMode: true,
          onAddBookmark: () {},
          bookmarked: true,
          onPreviousChapter: null,
          onNextChapter: null,
          onSeek: (_) {},
          onEntry: (_) {},
          drawerTitle: '',
          drawerChild: null,
          onCloseDrawer: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    final day = tester.widget<IconButton>(_button('daynight'));
    final bookmark = tester.widget<IconButton>(_button('add-bookmark'));
    expect((day.icon as AppIcon).glyph, AppGlyph.lightMode);
    expect(day.tooltip, '日间');
    expect((bookmark.icon as AppIcon).glyph, AppGlyph.bookmark);
    expect(bookmark.tooltip, '当前页已有书签');
    expect(_button('tts'), findsNothing);
    expect(
      tester.getRect(_icon('add-bookmark')).right,
      closeTo(_settingsRight(tester), .01),
    );
    expect(tester.takeException(), isNull);
  });
}
