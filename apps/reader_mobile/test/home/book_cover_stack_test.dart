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

List<double> _regionRatios(WidgetTester tester, int count, Size size) {
  final paths = [
    for (var index = 0; index < count; index++)
      tester
          .widget<ClipPath>(
            find.byKey(ValueKey('book-cover-stack-region-$index')),
          )
          .clipper!
          .getClip(size),
  ];
  final hits = List.filled(count, 0);
  const columns = 120;
  const rows = 160;
  for (var y = 0; y < rows; y++) {
    for (var x = 0; x < columns; x++) {
      final point = Offset(
        (x + .5) * size.width / columns,
        (y + .5) * size.height / rows,
      );
      final matching = [
        for (var index = 0; index < count; index++)
          if (paths[index].contains(point)) index,
      ];
      expect(matching, hasLength(1), reason: '拼接区域需无缝且不互相覆盖');
      hits[matching.single]++;
    }
  }
  return [for (final hit in hits) hit / (columns * rows)];
}

void main() {
  testWidgets('最多渲染四本封面，按拼接分区展示且不添加 Hero', (tester) async {
    final books = _books(8);
    await _show(tester, BookCoverStack(books: books, width: 120, height: 160));
    expect(find.byType(BookCoverImage), findsNWidgets(4));
    for (var index = 0; index < 4; index++) {
      final cover = tester.widget<BookCoverImage>(_cover('$index'));
      expect(cover.book, same(books[index]));
      expect(cover.showFrame, isFalse);
    }
    expect(find.byType(ClipPath), findsNWidgets(8));
    expect(find.byType(Hero), findsNothing);
  });

  testWidgets('两三四本分别使用均衡斜向拼接布局', (tester) async {
    for (final count in [2, 3, 4]) {
      const size = Size(120, 160);
      await _show(
        tester,
        BookCoverStack(
          books: _books(count),
          width: size.width,
          height: size.height,
        ),
      );
      expect(find.byType(BookCoverImage), findsNWidgets(count));
      expect(find.byType(ClipPath), findsNWidgets(count * 2));
      final ratios = _regionRatios(tester, count, size);
      final expected = 1 / count;
      for (final ratio in ratios) {
        expect(ratio, closeTo(expected, count == 3 ? .012 : .01));
      }
      final coverSizes = [
        for (var index = 0; index < count; index++)
          tester.getSize(_cover('$index')),
      ];
      for (final coverSize in coverSizes.skip(1)) {
        expect(coverSize.width, closeTo(coverSizes.first.width, .001));
        expect(coverSize.height, closeTo(coverSizes.first.height, .001));
      }
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('拼接容器保持三比四且适配窄宽和大字布局', (tester) async {
    await _show(
      tester,
      BookCoverStack(books: _books(3), width: 120, height: 160),
    );
    final bounds = tester.getRect(find.byType(BookCoverStack));
    expect(bounds.size, const Size(120, 160));
    expect(find.byType(BookCoverImage), findsNWidgets(3));
    expect(tester.takeException(), isNull);

    for (final size in [const Size(36, 48), const Size(90, 120)]) {
      await _show(
        tester,
        BookCoverStack(
          books: _books(4),
          width: size.width,
          height: size.height,
        ),
        textScale: 3.2,
      );
      expect(tester.getSize(find.byType(BookCoverStack)), size);
      expect(find.byType(BookCoverImage), findsNWidgets(4));
      expect(tester.takeException(), isNull);
    }
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
    expect(_cover('0'), findsOneWidget);
    expect(_cover('1'), findsNothing);
    expect(_cover('2'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    testWidgets('$brightness 拼接布局在窄宽和大字下无异常，沿用封面主题及占位', (tester) async {
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
        expect(find.byType(BookCoverImage), findsNWidgets(3));
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
