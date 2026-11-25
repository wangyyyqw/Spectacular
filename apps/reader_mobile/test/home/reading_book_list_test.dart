import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/home/reading_book_list.dart';
import 'package:reader_mobile/theme/app_theme.dart';

void main() {
  testWidgets('统计文本共享可用宽度，隐藏图标与关联图标等大并上下对齐', (tester) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(360, 800);
    addTearDown(tester.view.reset);
    var hidden = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReadingBookTile(
            item: ReadingBookItem(
              id: 'width',
              title: '魔王不必被打倒',
              author: '如倾如诉',
              duration: const Duration(hours: 57, minutes: 9),
              days: 8,
              recentOrder: 0,
              percent: 48,
              statusIcon: Icons.cloud_done_outlined,
              onHide: () => hidden = true,
              coverBuilder: (width, height) =>
                  SizedBox(width: width, height: height),
            ),
          ),
        ),
      ),
    );
    final stats = find.text('57 小时 9 分钟 · 读了 8 天');
    expect(
      tester.renderObject<RenderParagraph>(stats).didExceedMaxLines,
      isFalse,
    );
    final cloud = tester.getRect(find.byIcon(Icons.cloud_done_outlined));
    final hide = tester.getRect(find.byIcon(Icons.visibility_off_outlined));
    expect(hide.size, cloud.size);
    expect(hide.center.dx, cloud.center.dx);
    expect(hide.top, greaterThan(cloud.bottom));
    await tester.tap(find.byKey(const ValueKey('reading-book-hide-width')));
    expect(hidden, isTrue);
    expect(tester.takeException(), isNull);
  });

  for (final style in AppUiStyle.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('$style 字号 $scale 预览前三本、抽屉排序与封面三行对齐', (tester) async {
        tester.view
          ..devicePixelRatio = 1
          ..physicalSize = const Size(360, 800);
        addTearDown(tester.view.reset);
        String? opened;
        final books = [
          for (var index = 0; index < 5; index++)
            ReadingBookItem(
              id: '$index',
              title: '书籍$index 一段很长很长的书名',
              author: '作者$index',
              duration: Duration(minutes: 10 + index),
              days: 5 - index,
              recentOrder: index == 2 ? 100 : index,
              percent: 42,
              statusIcon: Icons.cloud_done_outlined,
              statusLabel: '已关联本地书籍',
              linked: true,
              onOpen: () => opened = '$index',
              coverBuilder: (width, height) => SizedBox(
                key: ValueKey('cover-$index'),
                width: width,
                height: height,
                child: const ColoredBox(color: Colors.teal),
              ),
            ),
        ];
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(uiStyle: style)
                .copyWith(platform: TargetPlatform.android),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Scaffold(
              body: ReadingBookList(
                title: '最近阅读',
                allKey: const ValueKey('all'),
                books: books,
              ),
            ),
          ),
        );
        expect(find.byKey(const ValueKey('reading-book-0')), findsNothing);
        expect(find.byKey(const ValueKey('reading-book-1')), findsNothing);
        expect(
          tester.getTopLeft(find.byKey(const ValueKey('reading-book-4'))).dy,
          lessThan(
            tester.getTopLeft(find.byKey(const ValueKey('reading-book-3'))).dy,
          ),
        );
        final cover = tester.getRect(find.byKey(const ValueKey('cover-4')));
        final title = tester.getRect(find.text(books[4].title));
        final stats = tester.getRect(find.text('14 分钟 · 读了 1 天'));
        expect(title.top, cover.top);
        expect(stats.bottom, closeTo(cover.bottom, .01));
        final icon = tester.getRect(
          find.byIcon(Icons.cloud_done_outlined).first,
        );
        expect(icon.left, greaterThan(title.right));
        await tester.tap(find.byKey(const ValueKey('all')));
        await tester.pumpAndSettle();
        final list = find.byKey(const ValueKey('reading-books-all-list'));
        Finder rows() =>
            find.descendant(of: list, matching: find.byType(ReadingBookTile));
        expect(tester.widget<ReadingBookTile>(rows().first).item.id, '2');
        expect(tester.widget<ReadingBookTile>(rows().first).showDays, isFalse);
        expect(
          find.descendant(of: list, matching: find.textContaining('读了')),
          findsNothing,
        );
        for (final (sort, first) in [
          ('阅读天数', '0'),
          ('阅读时长', '4'),
          ('最近阅读', '2'),
        ]) {
          await tester.tap(find.byKey(const ValueKey('reading-books-sort')));
          await tester.pumpAndSettle();
          await tester.tap(find.text(sort).last);
          await tester.pumpAndSettle();
          expect(tester.widget<ReadingBookTile>(rows().first).item.id, first);
        }
        await tester.tap(
          find.descendant(
            of: list,
            matching: find.byKey(const ValueKey('reading-book-2')),
          ),
        );
        await tester.pumpAndSettle();
        expect(opened, '2');
        expect(
          find.byKey(const ValueKey('reading-books-all-list')),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      });
    }
  }
}
