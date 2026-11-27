import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
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
  String query = '',
  Set<String> searchMatches = const {},
  Future<void> Function(String, ReaderAnnotation)? onDelete,
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
      query: query,
      searchMatches: searchMatches,
      onDelete: onDelete,
    ),
  ),
);

void main() {
  testWidgets('搜索筛选笔记书目，想法可复制并在删除成功后刷新', (tester) async {
    final notes = [_annotation('选中的原文', note: '自己的想法')];
    final copied = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add((call.arguments as Map)['text'] as String);
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await tester.pumpWidget(
      _app(
        books: [_book('one', '匹配书'), _book('two', '其他书')],
        counts: {'one': _counts(1, 0), 'two': _counts(1, 0)},
        query: '想法',
        searchMatches: {'one'},
        loadNotes: (_) async => notes.toList(),
        onDelete: (id, note) async {
          expect(id, 'one');
          notes.remove(note);
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('其他书'), findsNothing);
    final cover = find.byType(BookCoverImage);
    final frame = find
        .ancestor(of: cover, matching: find.byType(Material))
        .first;
    expect(
      tester.getTopLeft(cover) - tester.getTopLeft(frame),
      const Offset(6, 6),
    );
    final card = tester.widget<Material>(frame);
    expect(
      (card.shape! as RoundedRectangleBorder).borderRadius,
      bookCoverRadius,
    );
    await tester.tap(find.text('匹配书'));
    await tester.pumpAndSettle();
    expect(find.text('本地'), findsOneWidget);
    await tester.tap(find.byTooltip('复制'));
    await tester.pump();
    expect(copied.single, '自己的想法\n\n选中的原文');
    await tester.tap(find.byTooltip('删除'));
    await tester.pumpAndSettle();
    expect(find.text('这本书还没有笔记'), findsOneWidget);
  });

  testWidgets('删除失败保留笔记并显示错误', (tester) async {
    await tester.pumpWidget(
      _app(
        books: [_book('one', '笔记书')],
        counts: {'one': _counts(1, 0)},
        loadNotes: (_) async => [_annotation('保留的原文')],
        onDelete: (_, _) async => throw const FormatException('网络断开，请重试'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('笔记书'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('删除'));
    await tester.pumpAndSettle();
    expect(find.text('保留的原文'), findsOneWidget);
    expect(find.text('网络断开，请重试'), findsOneWidget);
  });
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
      expect(rowHeight, greaterThanOrEqualTo(82 + bookCardCoverInset * 2 + 12));
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
    expect(find.byType(SelectionArea), findsNothing);
    await tester.drag(
      find.byKey(const ValueKey('reader-drawer-drag-handle')),
      const Offset(0, 600),
    );
    await tester.pumpAndSettle();
    expect(find.text('冬日'), findsOneWidget);
    expect(body, findsNothing);
    await tester.tap(find.text('春潮'));
    await tester.pumpAndSettle();
    expect(opened, ['one', 'two']);
    expect(find.text('另一册的原文'), findsOneWidget);
    expect(body, findsNothing);
  });

  testWidgets(
    '桌面笔记的想法、引用与划线可用鼠标选择并复制',
    (tester) async {
      tester.view
        ..physicalSize = const Size(1280, 800)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      String? copied;
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );
      await tester.pumpWidget(
        _app(
          books: [_book('one', '桌面笔记')],
          counts: {'one': _counts(1, 1)},
          loadNotes: (_) async => [
            _annotation('选中的引用', note: '写下的想法'),
            _annotation('独立的划线', day: 17),
          ],
        ),
      );
      await tester.tap(find.text('桌面笔记'));
      await tester.pumpAndSettle();
      expect(find.byType(SelectionArea), findsOneWidget);
      final platform = Theme.of(tester.element(find.byType(SelectionArea)))
          .platform;
      final modifier = platform == TargetPlatform.macOS
          ? LogicalKeyboardKey.metaLeft
          : LogicalKeyboardKey.controlLeft;
      for (final text in ['写下的想法', '选中的引用', '独立的划线']) {
        final paragraph = tester.renderObject<RenderParagraph>(
          find.descendant(of: find.text(text), matching: find.byType(RichText)),
        );
        final start = paragraph.localToGlobal(
          Offset(0, paragraph.size.height / 2),
        );
        final end = paragraph.localToGlobal(
          paragraph.getOffsetForCaret(
                TextPosition(offset: text.length),
                Rect.zero,
              ) +
              Offset(1, paragraph.size.height / 2),
        );
        final mouse = await tester.startGesture(
          start,
          kind: PointerDeviceKind.mouse,
        );
        await mouse.moveTo(end);
        await mouse.up();
        await mouse.removePointer();
        await tester.pump();
        await tester.sendKeyDownEvent(modifier);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
        await tester.sendKeyUpEvent(modifier);
        await tester.pump();
        expect(copied, text);
      }
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.macOS,
      TargetPlatform.windows,
    }),
  );

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

  testWidgets('大量笔记按可见区域构建，滚动可读末条并关闭回书目', (tester) async {
    await tester.pumpWidget(
      _app(
        books: [_book('many', '长篇笔记')],
        counts: {'many': _counts(0, 100)},
        loadNotes: (_) async => [
          for (var index = 0; index < 100; index++)
            _annotation('第 $index 条原文', day: 100 - index),
        ],
      ),
    );
    await tester.tap(find.text('长篇笔记'));
    await tester.pumpAndSettle();
    expect(find.text('第 0 条原文'), findsOneWidget);
    expect(find.text('第 99 条原文'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('第 99 条原文'),
      500,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    expect(find.text('第 99 条原文'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.drag(
      find.byKey(const ValueKey('reader-drawer-drag-handle')),
      const Offset(0, 600),
    );
    await tester.pumpAndSettle();
    expect(find.text('长篇笔记'), findsOneWidget);
    expect(find.text('第 99 条原文'), findsNothing);
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
