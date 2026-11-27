import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

void main() {
  for (final brightness in Brightness.values) {
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
        if (width == 320) {
          expect(
            tester.getRect(title).top,
            greaterThan(tester.getRect(cover).bottom),
          );
        }
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
      tester
          .widget<BookReadingChart>(find.byType(BookReadingChart))
          .durations
          .last,
      const Duration(seconds: 30),
    );
    expect(tester.takeException(), isNull);
  });
}
