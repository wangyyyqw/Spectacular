import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/home/book_cover_image.dart';
import 'package:reader_mobile/home/startup_splash.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/main.dart';
import 'package:reader_ui/reader_session.dart';

class _CoverLibrary extends LibraryStore {
  _CoverLibrary(this.books) : super.memory();

  final List<BookEntry> books;
  final metadata = Completer<void>();
  bool delayMetadata = false;

  @override
  Future<List<BookEntry>> list() async {
    if (delayMetadata) await metadata.future;
    return books;
  }
}

class _DeferredCover extends OneFrameImageStreamCompleter {
  _DeferredCover(ui.Image image) : this._(image, Completer<ImageInfo>());

  _DeferredCover._(this.image, this.result) : super(result.future);

  final ui.Image image;
  final Completer<ImageInfo> result;
  int listenersAdded = 0;

  @override
  void addListener(ImageStreamListener listener) {
    listenersAdded += 1;
    super.addListener(listener);
  }

  void complete() => result.complete(ImageInfo(image: image.clone()));
}

List<BookEntry> _books(int count) => [
  for (var index = 0; index < count; index++)
    BookEntry(
      id: 'book-$index',
      title: '书籍 $index',
      author: '',
      filePath: '',
      addedAt: DateTime(2026),
      coverPath: '/封面/cover-$index.png',
    ),
];

Future<List<_DeferredCover>> _deferCovers(
  WidgetTester tester,
  List<BookEntry> books,
  int decodeWidth,
) async {
  final image = (await tester.runAsync(createTestImage))!;
  final covers = <_DeferredCover>[];
  final cache = PaintingBinding.instance.imageCache;
  for (final book in books) {
    final key = await coverImageProvider(
      book.coverPath!,
      decodeWidth,
    ).obtainKey(const ImageConfiguration());
    final cover = _DeferredCover(image);
    covers.add(cover);
    cache.putIfAbsent(key, () => cover);
  }
  addTearDown(() async {
    for (final cover in covers) {
      if (!cover.result.isCompleted) cover.complete();
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    cache.clear();
    cache.clearLiveImages();
    image.dispose();
  });
  return covers;
}

void _expectOpaqueSplash(WidgetTester tester) {
  expect(find.byType(StartupSplash), findsOneWidget);
  final veil = find
      .descendant(
        of: find.byType(StartupSplash),
        matching: find.byType(Opacity),
      )
      .first;
  expect(tester.widget<Opacity>(veil).opacity, 1);
}

void main() {
  for (final grid in [true, false]) {
    testWidgets('开屏期间准备最终排序的前 12 本封面，后续封面不阻塞：网格=$grid', (tester) async {
      tester.view.devicePixelRatio = 3;
      tester.view.physicalSize = const Size(1170, 2532);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final books = _books(14);
      final library = _CoverLibrary(books);
      await library.setSetting('bookshelf.grid', '$grid');
      await library.setSetting('bookshelf.pinned', jsonEncode(['book-13']));
      final width = grid ? (390 - 64) / 3 : 66.0;
      final covers = await _deferCovers(
        tester,
        books,
        coverDecodeWidth(width, 3),
      );
      await tester.pumpWidget(
        ReaderApp(library: library, progressStore: MemoryReaderProgressStore()),
      );
      for (var frame = 0; frame < 5; frame++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      final initial = [13, for (var index = 0; index < 11; index++) index];
      for (final index in initial) {
        expect(
          covers[index].listenersAdded,
          greaterThan(1),
          reason: '前 12 本必须在开屏期间全部开始准备，不能等上一批完成',
        );
      }
      for (var index = 0; index < 11; index++) {
        covers[index].complete();
      }
      await tester.pump(StartupSplash.duration);
      _expectOpaqueSplash(tester);

      covers[13].complete();
      await tester.pumpAndSettle();
      expect(find.byType(StartupSplash), findsNothing);
      expect(covers[11].result.isCompleted, isFalse);
      expect(covers[12].result.isCompleted, isFalse);
      for (final index in initial) {
        expect(
          find.byKey(ValueKey('cover-placeholder-book-$index')),
          findsNothing,
          reason: '开屏消失时已构建的前 12 本不能再显示加载占位',
        );
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('书架元数据较慢时保持开屏，准备完成后才淡出', (tester) async {
    final library = _CoverLibrary([])..delayMetadata = true;
    await tester.pumpWidget(
      ReaderApp(library: library, progressStore: MemoryReaderProgressStore()),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    _expectOpaqueSplash(tester);
    library.metadata.complete();
    await tester.pumpAndSettle();
    expect(find.byType(StartupSplash), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('无封面的书籍也计入前 12 本，不等待第 13 本', (tester) async {
    final tail = _books(13).last;
    final books = [
      for (var index = 0; index < 12; index++)
        BookEntry(
          id: 'book-$index',
          title: '无封面书籍 $index',
          author: '',
          filePath: '',
          addedAt: DateTime(2026),
        ),
      tail,
    ];
    final library = _CoverLibrary(books);
    await library.setSetting('bookshelf.grid', 'false');
    final covers = await _deferCovers(tester, [
      tail,
    ], coverDecodeWidth(66, tester.view.devicePixelRatio));
    await tester.pumpWidget(
      ReaderApp(library: library, progressStore: MemoryReaderProgressStore()),
    );
    await tester.pumpAndSettle();
    expect(find.byType(StartupSplash), findsNothing);
    expect(covers.single.result.isCompleted, isFalse);
    expect(
      find.byKey(const ValueKey('cover-placeholder-book-0')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('少于 12 本且封面损坏时使用占位，不永久阻塞开屏', (tester) async {
    final books = _books(1);
    final library = _CoverLibrary(books);
    await library.setSetting('bookshelf.grid', 'false');
    final covers = await _deferCovers(
      tester,
      books,
      coverDecodeWidth(66, tester.view.devicePixelRatio),
    );
    await tester.pumpWidget(
      ReaderApp(library: library, progressStore: MemoryReaderProgressStore()),
    );
    for (var frame = 0; frame < 5; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    covers.single.result.completeError(StateError('损坏的封面'), StackTrace.current);
    await tester.pumpAndSettle();
    expect(find.byType(StartupSplash), findsNothing);
    expect(
      find.byKey(const ValueKey('cover-placeholder-book-0')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
