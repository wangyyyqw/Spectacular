import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/home/book_cover_image.dart';
import 'package:reader_mobile/home/book_notes_list.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/theme/app_theme.dart';
import 'package:reader_ui/annotations/annotation.dart';

BookEntry _book(String id, String title, {String author = '林川'}) => BookEntry(
  id: id,
  title: title,
  author: author,
  filePath: '',
  addedAt: DateTime(2026, 11),
);

BookNoteCounts _counts(int thoughts, int marks, {int day = 18}) =>
    (thoughts: thoughts, marks: marks, updatedAt: DateTime(2026, 11, day));

ReaderAnnotation _annotation(String quote, {String? note, int day = 18}) {
  final date = DateTime(2026, 11, day);
  return ReaderAnnotation(
    id: quote,
    type: note == null
        ? ReaderAnnotationType.mark
        : ReaderAnnotationType.thought,
    startCfi: 'epubcfi(/6/2!/4/2:0)',
    endCfi: 'epubcfi(/6/2!/4/2:3)',
    quote: quote,
    note: note,
    createdAt: date,
    updatedAt: date,
  );
}

Widget _app({
  required List<BookEntry> books,
  required Map<String, BookNoteCounts> counts,
  Future<List<ReaderAnnotation>> Function(String)? loadNotes,
  Future<void> Function()? onRefresh,
  double scale = 1,
}) => MaterialApp(
  theme: buildAppTheme(),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: Scaffold(
    body: BookNotesList(
      books: books,
      counts: counts,
      loadNotes: loadNotes ?? (_) async => const <ReaderAnnotation>[],
      onRefresh: onRefresh ?? () async {},
    ),
  ),
);

void main() {
  testWidgets(
    '桌面笔记按可用宽度并排，窄窗大字号不溢出',
    (tester) async {
      tester.view
        ..physicalSize = const Size(1280, 800)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final books = [_book('one', '第一本很长书名的笔记'), _book('two', '第二本书的笔记')];
      final counts = {'one': _counts(3, 12), 'two': _counts(1, 4)};
      await tester.pumpWidget(_app(books: books, counts: counts));
      await tester.pumpAndSettle();
      final covers = find.byType(BookCoverImage);
      expect(
        tester.getTopLeft(covers.first).dy,
        tester.getTopLeft(covers.last).dy,
      );
      tester.view.physicalSize = const Size(390, 900);
      await tester.pumpWidget(_app(books: books, counts: counts, scale: 2));
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(covers.last).dy,
        greaterThan(tester.getTopLeft(covers.first).dy),
      );
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.macOS,
      TargetPlatform.windows,
    }),
  );

  testWidgets(
    '桌面单列笔记卡片由内容撑高，不为短书名预留空白',
    (tester) async {
      tester.view
        ..physicalSize = const Size(440, 760)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _app(
          books: [_book('one', '世子很凶'), _book('two', '动漫之王的养成方法')],
          counts: {'one': _counts(0, 1), 'two': _counts(0, 1)},
        ),
      );
      final covers = find.byType(BookCoverImage);
      final rowHeight =
          tester.getTopLeft(covers.last).dy -
          tester.getTopLeft(covers.first).dy;
      expect(rowHeight, lessThan(140));
      expect(rowHeight, greaterThanOrEqualTo(82 + 24 + 12));
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.windows,
      TargetPlatform.macOS,
    }),
  );

  testWidgets('只列出书架上有笔记的书，按最近笔记排序，隐藏零计数', (tester) async {
    await tester.pumpWidget(
      _app(
        books: [
          _book('old', '旧笔记'),
          _book('zero', '两项均为零'),
          _book('new', '新笔记'),
          _book('none', '没有标注'),
        ],
        counts: {
          'old': _counts(0, 1, day: 10),
          'new': _counts(3, 0),
          'zero': _counts(0, 0),
          'removed': _counts(6, 8),
        },
      ),
    );
    final covers = tester.widgetList<BookCoverImage>(
      find.byType(BookCoverImage),
    );
    expect(covers.map((cover) => cover.book.id), ['new', 'old']);
    expect(find.text('想法 3'), findsOneWidget);
    expect(find.text('划线 1'), findsOneWidget);
    expect(find.text('想法 0'), findsNothing);
    expect(find.text('划线 0'), findsNothing);
  });

  testWidgets('打开哪本书才加载哪本，想法正文和引用分开，划线显示其原文', (tester) async {
    final opened = <String>[];
    final pending = Completer<List<ReaderAnnotation>>();
    await tester.pumpWidget(
      _app(
        books: [_book('one', '冬日'), _book('two', '春潮')],
        counts: {'one': _counts(1, 1), 'two': _counts(0, 1)},
        loadNotes: (id) async {
          opened.add(id);
          return id == 'one' ? await pending.future : [_annotation('另一册的原文')];
        },
      ),
    );
    expect(opened, isEmpty);
    await tester.tap(find.text('冬日'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    pending.complete(
      List.unmodifiable([
        _annotation('一行划线原文', day: 12),
        _annotation('写想法时选中的原文', note: '第一段感想。\n第二段感想。'),
      ]),
    );
    await tester.pumpAndSettle();
    expect(opened, ['one']);
    final body = find.text('第一段感想。\n第二段感想。');
    final quote = find.text('写想法时选中的原文');
    final mark = find.text('一行划线原文');
    expect(tester.getTopLeft(body).dy, lessThan(tester.getTopLeft(quote).dy));
    expect(tester.getTopLeft(quote).dy, lessThan(tester.getTopLeft(mark).dy));
    expect(find.byType(EditableText), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('春潮'));
    await tester.pumpAndSettle();
    expect(opened, ['one', 'two']);
    expect(find.text('另一册的原文'), findsOneWidget);
    expect(body, findsNothing);
  });

  testWidgets('详情读取失败可重试，重读后没有记录显示本书空态', (tester) async {
    final attempts = <String>[];
    await tester.pumpWidget(
      _app(
        books: [_book('one', '冬日')],
        counts: {'one': _counts(0, 1)},
        loadNotes: (id) async {
          attempts.add(id);
          if (attempts.length == 1) throw StateError('读取中断');
          return [];
        },
      ),
    );
    await tester.tap(find.text('冬日'));
    await tester.pumpAndSettle();
    expect(find.text('笔记读取失败'), findsOneWidget);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(attempts, ['one', 'one']);
    expect(find.text('这本书还没有笔记'), findsOneWidget);
    expect(find.text('重试'), findsNothing);
  });

  testWidgets('没有笔记时也能下拉刷新列表', (tester) async {
    var refreshes = 0;
    await tester.pumpWidget(
      _app(
        books: [_book('one', '冬日')],
        counts: const {},
        onRefresh: () async => refreshes++,
      ),
    );
    expect(find.text('还没有笔记'), findsOneWidget);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 400));
    await tester.pumpAndSettle();
    expect(refreshes, 1);
  });

  testWidgets('320 宽与双倍字号下计数换行，笔记全文可读', (tester) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const title = '在风景与城市之间的漫长旅途中记下的片段';
    const quote = '这一段长长的原文会随可用宽度换行。\n下一段原文也应当保留。';
    await tester.pumpWidget(
      _app(
        books: [_book('one', title, author: '联合编写这部作品的作者们')],
        counts: {'one': _counts(12, 345)},
        loadNotes: (_) async => [_annotation(quote, note: '记在书页边的想法。')],
        scale: 2,
      ),
    );
    expect(
      tester.getTopLeft(find.text('划线 345')).dy,
      greaterThan(tester.getBottomLeft(find.text('想法 12')).dy),
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.text(title));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.text(quote)).maxLines, isNull);
    expect(tester.takeException(), isNull);
  });
}
