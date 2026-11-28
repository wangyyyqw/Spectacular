import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/home/book_detail_page.dart';
import 'package:reader_mobile/home/book_reading_chart.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/storage/book_review_store.dart';
import 'package:reader_mobile/storage/reading_session_store.dart';
import 'package:reader_mobile/theme/app_theme.dart';
import 'package:reader_ui/reader_session.dart';
import 'package:reader_ui/theme/reader_common_widgets.dart';

import '../support/test_epub.dart';

class _Sessions implements ReadingSessionStore {
  final items = <ReadingSession>[];
  bool failLoad = false;

  @override
  Future<List<ReadingSession>> list() async {
    if (failLoad) throw StateError('模拟读取失败');
    return List.of(items);
  }

  @override
  Future<void> add({
    required String bookId,
    required DateTime startedAt,
    required DateTime endedAt,
    int pageTurns = 0,
    int charactersRead = 0,
  }) async {
    items.add(
      ReadingSession(
        bookId: bookId,
        startedAt: startedAt,
        endedAt: endedAt,
        duration: endedAt.difference(startedAt),
        pageTurns: pageTurns,
        charactersRead: charactersRead,
      ),
    );
  }
}

class _Reviews implements BookReviewStore {
  final items = <String, BookReview>{};
  @override
  Future<Map<String, BookReview>> snapshot() async => Map.of(items);
  @override
  Future<void> remove(String bookId) async => items.remove(bookId);
  @override
  Future<void> save(
    String bookId, {
    int? rating,
    required String content,
  }) async {
    items[bookId] = BookReview(
      bookId: bookId,
      rating: rating,
      content: content,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }
}

Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

Future<void> _capture(WidgetTester tester, String name) async {
  if (!const bool.fromEnvironment('CAPTURE_BOOK_DETAIL_UI')) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('book-detail-preview')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final directory = Directory('dist/book-detail-ui')
        ..createSync(recursive: true);
      File('${directory.path}/$name.png')
          .writeAsBytesSync(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

void main() {
  setUpAll(() async {
    if (!const bool.fromEnvironment('CAPTURE_BOOK_DETAIL_UI')) return;
    await (FontLoader(
      AppFonts.defaultFamily,
    )..addFont(rootBundle.load('assets/fonts/MoyuSerif-Regular.otf'))).load();
  });

  for (final brightness in Brightness.values) {
    testWidgets('封面位于书名作者左侧，不展示横幅，保留阅读统计：$brightness', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(393, 900);
      addTearDown(tester.view.reset);
      final library = LibraryStore.memory();
      final book = (await tester.runAsync(() async {
        final entry = await library.importBytes(
          buildTestEpub(title: '山海之间', author: '行舟'),
        );
        return library.updateBookMetadata(
          entry.id,
          title: entry.title,
          author: entry.author,
          description:
              '沿着河流走向群山，在寻常的日子里发现风景。'
              '这是一本关于旅途、故乡与生活的阅读随笔。',
        );
      }))!;
      final sessions = _Sessions();
      final now = DateTime.now();
      for (var day = 0; day < 7; day++) {
        final start = DateTime(now.year, now.month, now.day - day, 8);
        await sessions.add(
          bookId: book.id,
          startedAt: start,
          endedAt: start.add(Duration(minutes: 15 + day * 7)),
        );
      }
      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('book-detail-preview'),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildAppTheme(brightness: brightness),
            home: BookDetailPage(
              entry: book,
              library: library,
              sessionStore: sessions,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final metadata = find.byKey(const ValueKey('book-detail-metadata-card'));
      final cover = find.byKey(const ValueKey('book-detail-page-cover'));
      final storage = find.byKey(const ValueKey('book-detail-storage-card'));
      final tags = find.byKey(const ValueKey('book-detail-tags-card'));
      final description = find.byKey(
        const ValueKey('book-detail-description-card'),
      );
      expect(
        tester.getRect(metadata).bottom,
        lessThan(tester.getRect(storage).top),
      );
      expect(
        tester.getRect(storage).bottom,
        lessThan(tester.getRect(tags).top),
      );
      expect(
        tester.getRect(tags).bottom,
        lessThan(tester.getRect(description).top),
      );
      for (final key in [
        'book-detail-title-field',
        'book-detail-author-field',
      ]) {
        expect(
          tester.getRect(find.byKey(ValueKey(key))).left,
          greaterThan(tester.getRect(cover).right),
        );
      }
      expect(find.text('横幅预览'), findsNothing);
      expect(
        find.byKey(const ValueKey('book-detail-cover-banner')),
        findsNothing,
      );
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey('book-detail-storage-value')),
            )
            .data,
        '暂不可用',
      );
      expect(find.widgetWithText(ReaderOptionTile, 'EPUB 大小'), findsOneWidget);
      expect(find.widgetWithText(ReaderOptionTile, '字数'), findsOneWidget);
      expect(find.text('存储'), findsNothing);
      expect(find.text('设置标签'), findsOneWidget);
      expect(find.text('本书标签'), findsOneWidget);
      expect(find.text('全部标签'), findsOneWidget);
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey('book-detail-character-count')),
            )
            .data,
        '暂无统计',
      );
      final title = tester.widget<TextField>(
        find.byKey(const ValueKey('book-detail-title-field')),
      );
      expect(title.controller!.text, book.title);
      expect(title.decoration!.border, InputBorder.none);
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(
        scaffold.backgroundColor,
        buildAppTheme(brightness: brightness)
            .colorScheme
            .surfaceContainerLowest,
      );
      await _capture(tester, '${brightness.name}-资料');
      await _scrollTo(
        tester,
        find.byKey(const ValueKey('book-detail-new-tag-field')),
      );
      expect(
        find.byKey(const ValueKey('book-detail-new-tag-field')).hitTestable(),
        findsOneWidget,
      );
      await _scrollTo(
        tester,
        find.byKey(const ValueKey('book-detail-edit-description')),
      );
      await tester.tap(
        find.byKey(const ValueKey('book-detail-edit-description')),
      );
      await tester.pump();
      final descriptionField = tester.widget<TextField>(
        find.byKey(const ValueKey('book-detail-description-field')),
      );
      expect(descriptionField.focusNode!.hasFocus, isTrue);
      expect(descriptionField.controller!.text, book.description);
      descriptionField.focusNode!.unfocus();
      await tester.pumpAndSettle();
      await _scrollTo(
        tester,
        find.byKey(const ValueKey('book-detail-reading-summary')),
      );
      await _capture(tester, '${brightness.name}-阅读记录');
      expect(tester.takeException(), isNull);
    });

    testWidgets('标签分区在窄屏大字号与日夜主题下可用：$brightness', (tester) async {
      final library = LibraryStore.memory();
      late BookEntry book;
      await tester.runAsync(() async {
        book = await library.importBytes(buildTestEpub(title: '山海之间'));
        for (final name in ['科幻', '带有很长名称的阅读主题标签与收藏分类']) {
          final tag = await library.createTag(name);
          await library.addBookTag(book.id, tag.id);
        }
        await library.createTag('待读');
      });
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      for (final width in [320.0, 393.0]) {
        tester.view.physicalSize = Size(width, 900);
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('book-detail-preview'),
            child: MaterialApp(
              key: UniqueKey(),
              debugShowCheckedModeBanner: false,
              theme: buildAppTheme(brightness: brightness),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(width == 320 ? 1.6 : 1),
                ),
                child: child!,
              ),
              home: BookDetailPage(entry: book, library: library),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await _scrollTo(tester, find.text('本书标签'));
        expect(
          tester.getRect(find.text('本书标签')).bottom,
          lessThan(tester.getRect(find.text('全部标签')).top),
        );
        expect(find.byType(InputChip), findsNWidgets(2));
        expect(find.byType(FilterChip), findsNWidgets(3));
        expect(
          tester
              .widgetList<FilterChip>(find.byType(FilterChip))
              .every((chip) => chip.onDeleted == null),
          isTrue,
        );
        for (final chip in [find.byType(InputChip), find.byType(FilterChip)]) {
          for (final element in chip.evaluate()) {
            final rect = tester.getRect(find.byWidget(element.widget));
            expect(rect.left, greaterThanOrEqualTo(0));
            expect(rect.right, lessThanOrEqualTo(width));
          }
        }
        await _capture(tester, '${brightness.name}-标签分区-${width.toInt()}');
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('详情复用组件，长资料和已读完在窄屏大字号及宽屏可用：$brightness', (tester) async {
      final library = LibraryStore.memory();
      late BookEntry book;
      await tester.runAsync(() async {
        book = await library.importBytes(
          buildTestEpub(title: '关于城市、河流与漫长旅途的阅读笔记', author: '一位名字较长的作者'),
        );
        for (final name in ['文学', '待读', '带有很长名称的阅读主题标签与收藏分类']) {
          final tag = await library.createTag(name);
          await library.addBookTag(book.id, tag.id);
        }
      });
      final progress = MemoryReaderProgressStore();
      await progress.save(
        book.id,
        const ReaderProgress(spineIndex: 0, pageIndex: 1, finished: true),
      );
      final reviews = _Reviews();
      await reviews.save(book.id, rating: 4, content: '这是已经保存的书评，优化界面后仍然保留。');
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      for (final width in [320.0, 1200.0]) {
        tester.view.physicalSize = Size(width, 720);
        await tester.pumpWidget(
          MaterialApp(
            key: UniqueKey(),
            theme: buildAppTheme(brightness: brightness),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(width == 320 ? 2 : 1)),
              child: child!,
            ),
            home: BookDetailPage(
              entry: book,
              library: library,
              inDrawer: true,
              progressStore: progress,
              reviewStore: reviews,
            ),
          ),
        );
        await tester.pumpAndSettle();
        final pageTitle = find.text('图书详情');
        expect(
          tester.renderObject<RenderParagraph>(pageTitle).didExceedMaxLines,
          isFalse,
        );
        expect(tester.getRect(pageTitle).right, lessThanOrEqualTo(width));
        expect(find.byType(ReaderSectionCard), findsWidgets);
        final content = find.byKey(const ValueKey('book-detail-content'));
        expect(tester.getSize(content).width, lessThanOrEqualTo(720));
        final title = find.byKey(const ValueKey('book-detail-title-field'));
        final cover = find.byKey(const ValueKey('book-detail-page-cover'));
        final metadata = find.byKey(
          const ValueKey('book-detail-metadata-card'),
        );
        expect(tester.getRect(title).right, lessThanOrEqualTo(width));
        expect(
          tester.getRect(title).top,
          greaterThanOrEqualTo(tester.getRect(metadata).top),
        );
        expect(
          tester.getRect(title).left,
          greaterThan(tester.getRect(cover).right),
        );
        expect(
          tester
              .getRect(find.byKey(const ValueKey('book-detail-author-field')))
              .left,
          greaterThan(tester.getRect(cover).right),
        );
        final edit = find.byKey(const ValueKey('book-detail-edit-finished'));
        await _scrollTo(tester, edit);
        final cancel = find.byKey(
          const ValueKey('book-detail-unmark-finished'),
        );
        await tester.ensureVisible(cancel);
        await tester.pumpAndSettle();
        expect(tester.getRect(edit).right, lessThanOrEqualTo(width));
        expect(tester.getRect(cancel).right, lessThanOrEqualTo(width));
        expect(tester.takeException(), isNull);
      }
    });
  }

  testWidgets('详情读取失败可重试，统计复用有效时长而非会话跨度', (tester) async {
    final library = LibraryStore.memory();
    final book = (await tester.runAsync(
      () => library.importBytes(buildTestEpub()),
    ))!;
    final now = DateTime.now();
    final date = DateTime(now.year, now.month, now.day, 8);
    final sessions = _Sessions()..failLoad = true;
    sessions.items.add(
      ReadingSession(
        bookId: book.id,
        startedAt: date,
        endedAt: date.add(const Duration(minutes: 20)),
        duration: const Duration(seconds: 30),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: BookDetailPage(
          entry: book,
          library: library,
          sessionStore: sessions,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ReaderEmptyState), findsOneWidget);
    expect(find.text('图书详情加载失败'), findsOneWidget);
    sessions.failLoad = false;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    final duration = find.byKey(const ValueKey('book-detail-total-duration'));
    await _scrollTo(tester, duration);
    expect(tester.widget<Text>(duration).data, '<1 分钟');
    await _scrollTo(tester, find.byType(BookReadingChart));
    expect(
      tester.widget<BookReadingChart>(find.byType(BookReadingChart)).framed,
      isFalse,
    );
    expect(
      find.ancestor(
        of: find.byType(BookReadingChart),
        matching: find.byKey(const ValueKey('book-detail-reading-summary')),
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<BookReadingChart>(find.byType(BookReadingChart))
          .durations
          .last,
      const Duration(seconds: 30),
    );
    expect(tester.takeException(), isNull);
  });
}
