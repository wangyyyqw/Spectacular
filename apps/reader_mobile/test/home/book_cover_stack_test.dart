import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/home/book_cover_image.dart';
import 'package:reader_mobile/home/book_cover_stack.dart';
import 'package:reader_mobile/library/library_store.dart';

List<BookEntry> _books(int count) => [
  for (var index = 0; index < count; index++)
    BookEntry(
      id: 'stack-$index',
      title: '合成书籍 $index 的完整长标题',
      author: '作者',
      filePath: '',
      addedAt: DateTime(2026),
    ),
];

Future<void> _show(
  WidgetTester tester,
  Widget child, {
  ThemeData? theme,
  double textScale = 1,
}) => tester.pumpWidget(
  MaterialApp(
    theme: theme,
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: Scaffold(body: Center(child: child)),
    ),
  ),
);

Finder _cover(String position) =>
    find.byKey(ValueKey('book-cover-stack-$position'));

void main() {
  testWidgets('只渲染前三本封面，前景位于最上层且不添加 Hero', (tester) async {
    final books = _books(8);
    await _show(tester, BookCoverStack(books: books, width: 120, height: 160));
    expect(find.byType(BookCoverImage), findsNWidgets(3));
    expect(tester.widget<BookCoverImage>(_cover('front')).book, same(books[0]));
    expect(
      tester.widget<BookCoverImage>(_cover('back-left')).book,
      same(books[1]),
    );
    expect(
      tester.widget<BookCoverImage>(_cover('back-right')).book,
      same(books[2]),
    );
    final stack = tester.widget<Stack>(
      find.descendant(
        of: find.byType(BookCoverStack),
        matching: find.byType(Stack),
      ),
    );
    expect(
      (stack.children.last as Positioned).child.key,
      const ValueKey('book-cover-stack-front'),
    );
    expect(find.byType(Hero), findsNothing);
    expect(
      find.descendant(
        of: find.byType(BookCoverStack),
        matching: find.byType(Transform),
      ),
      findsNothing,
    );
  });

  testWidgets('前景居中保持三比四，后景稍矮左右露边且底部对齐', (tester) async {
    await _show(
      tester,
      BookCoverStack(books: _books(3), width: 120, height: 160),
    );
    final bounds = tester.getRect(find.byType(BookCoverStack));
    final front = tester.getRect(_cover('front'));
    final left = tester.getRect(_cover('back-left'));
    final right = tester.getRect(_cover('back-right'));
    expect(front.width, closeTo(bounds.width * .82, .001));
    expect(front.height, closeTo(bounds.height * .82, .001));
    expect(front.center.dx, closeTo(bounds.center.dx, .001));
    for (final cover in [front, left, right]) {
      expect(cover.width / cover.height, closeTo(3 / 4, .001));
      expect(cover.bottom, closeTo(bounds.bottom, .001));
    }
    expect(left.left, closeTo(bounds.left, .001));
    expect(right.right, closeTo(bounds.right, .001));
    expect(left.height, lessThan(front.height));
    expect(right.height, lessThan(front.height));
    expect(left.left, lessThan(front.left));
    expect(right.right, greaterThan(front.right));
  });

  testWidgets('空列表和单本安全显示，单本不构建后景', (tester) async {
    await _show(
      tester,
      const BookCoverStack(books: [], width: 120, height: 160),
    );
    expect(find.byType(BookCoverImage), findsNothing);
    expect(tester.getSize(find.byType(BookCoverStack)), const Size(120, 160));
    expect(tester.takeException(), isNull);
    await _show(
      tester,
      BookCoverStack(books: _books(1), width: 120, height: 160),
    );
    expect(find.byType(BookCoverImage), findsOneWidget);
    expect(_cover('front'), findsOneWidget);
    expect(_cover('back-left'), findsNothing);
    expect(_cover('back-right'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    testWidgets('$brightness 窄宽和大字布局无异常，沿用封面主题及占位', (tester) async {
      final theme = ThemeData(brightness: brightness);
      for (final size in [
        const Size(36, 48),
        const Size(90, 120),
        const Size(160, 160),
        const Size(240, 320),
      ]) {
        await _show(
          tester,
          BookCoverStack(
            books: _books(3),
            width: size.width,
            height: size.height,
          ),
          theme: theme,
          textScale: 3.2,
        );
        expect(tester.getSize(find.byType(BookCoverStack)), size);
        final bounds = tester.getRect(find.byType(BookCoverStack));
        for (final position in ['front', 'back-left', 'back-right']) {
          final cover = tester.getRect(_cover(position));
          expect(bounds.contains(cover.topLeft), isTrue);
          expect(cover.right, lessThanOrEqualTo(bounds.right));
          expect(cover.bottom, closeTo(bounds.bottom, .001));
          expect(cover.width / cover.height, closeTo(3 / 4, .001));
          final material = tester.widget<Material>(
            find.descendant(
              of: _cover(position),
              matching: find.byType(Material),
            ),
          );
          expect(material.color, theme.colorScheme.surface);
          expect(material.borderRadius, BorderRadius.circular(4));
          expect(material.elevation, 2);
        }
        expect(
          find.byKey(const ValueKey('cover-placeholder-stack-0')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      }
    });
  }

  testWidgets('仅给宽度时按三比四展开，语义由外层描述整组', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await _show(
        tester,
        Semantics(
          label: '文学，三本书',
          child: BookCoverStack(books: _books(3), width: 120),
        ),
      );
      expect(tester.getSize(find.byType(BookCoverStack)), const Size(120, 160));
      expect(find.bySemanticsLabel('文学，三本书'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('.*封面')), findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });
}
