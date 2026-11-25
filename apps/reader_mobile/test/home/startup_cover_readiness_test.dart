import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/home/book_cover_image.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/main.dart';
import 'package:reader_ui/reader_session.dart';

import '../support/reader_pump.dart';

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
  int decodeHeight,
) async {
  final image = (await tester.runAsync(createTestImage))!;
  final covers = <_DeferredCover>[];
  final cache = PaintingBinding.instance.imageCache;
  for (final book in books) {
    final key = await coverImageProvider(
      book.coverPath!,
      decodeWidth,
      decodeHeight: decodeHeight,
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

void main() {
  for (final grid in [true, false]) {
    testWidgets('首帧释放前准备最终排序的前 12 本封面，后续封面不阻塞：网格=$grid', (tester) async {
      tester.view.devicePixelRatio = 3;
      tester.view.physicalSize = const Size(1170, 2532);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final books = _books(14);
      final library = _CoverLibrary(books);
      await library.setSetting('bookshelf.grid', '$grid');
      await library.setSetting('bookshelf.pinned', jsonEncode(['book-13']));
      final width = grid ? (390 - 64) / 3 : 66.0;
      final height = grid ? width / (3 / 4) : 88.0;
      final covers = await _deferCovers(
        tester,
        books,
        coverDecodeWidth(width, 3),
        coverDecodeHeight(height, 3),
      );
      var ready = 0;
      await tester.pumpWidget(
        ReaderApp(
          library: library,
          progressStore: MemoryReaderProgressStore(),
          onStartupReady: () => ready++,
        ),
      );
      for (var frame = 0; frame < 5; frame++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await pumpReaderUntilComplete(
        tester,
        () => covers[13].listenersAdded > 1,
      );
      final initial = [13, for (var index = 0; index < 11; index++) index];
      for (final index in initial) {
        expect(
          covers[index].listenersAdded,
          greaterThan(1),
          reason: '前 12 本必须在首帧释放前全部开始准备，不能等上一批完成',
        );
      }
      for (var index = 0; index < 11; index++) {
        covers[index].complete();
      }
      await tester.pump(const Duration(seconds: 1));
      expect(ready, 0);

      covers[13].complete();
      await pumpReaderUntilComplete(tester, () => ready == 1);
      await tester.pumpAndSettle();
      expect(ready, 1);
      expect(covers[11].result.isCompleted, isFalse);
      expect(covers[12].result.isCompleted, isFalse);
      for (final index in initial) {
        expect(
          find.byKey(ValueKey('cover-placeholder-book-$index')),
          findsNothing,
          reason: '首帧消失时已构建的前 12 本不能再显示加载占位',
        );
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('书架元数据较慢时保持首帧，准备完成后才释放', (tester) async {
    final library = _CoverLibrary([])..delayMetadata = true;
    var ready = 0;
    await tester.pumpWidget(
      ReaderApp(
        library: library,
        progressStore: MemoryReaderProgressStore(),
        onStartupReady: () => ready++,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(ready, 0);
    library.metadata.complete();
    await pumpReaderUntilComplete(tester, () => ready == 1);
    await tester.pumpAndSettle();
    expect(ready, 1);
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
    final covers = await _deferCovers(
      tester,
      [tail],
      coverDecodeWidth(66, tester.view.devicePixelRatio),
      coverDecodeHeight(88, tester.view.devicePixelRatio),
    );
    var ready = 0;
    await tester.pumpWidget(
      ReaderApp(
        library: library,
        progressStore: MemoryReaderProgressStore(),
        onStartupReady: () => ready++,
      ),
    );
    await pumpReaderUntilComplete(tester, () => ready == 1);
    await tester.pumpAndSettle();
    expect(ready, 1);
    expect(covers.single.result.isCompleted, isFalse);
    expect(
      find.byKey(const ValueKey('cover-placeholder-book-0')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('少于 12 本且封面损坏时使用占位，不永久阻塞首帧', (tester) async {
    final books = _books(1);
    final library = _CoverLibrary(books);
    await library.setSetting('bookshelf.grid', 'false');
    final covers = await _deferCovers(
      tester,
      books,
      coverDecodeWidth(66, tester.view.devicePixelRatio),
      coverDecodeHeight(88, tester.view.devicePixelRatio),
    );
    var ready = 0;
    await tester.pumpWidget(
      ReaderApp(
        library: library,
        progressStore: MemoryReaderProgressStore(),
        onStartupReady: () => ready++,
      ),
    );
    for (var frame = 0; frame < 5; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await pumpReaderUntilComplete(
      tester,
      () => covers.single.listenersAdded > 1,
    );
    covers.single.result.completeError(StateError('损坏的封面'), StackTrace.current);
    await pumpReaderUntilComplete(tester, () => ready == 1);
    await tester.pumpAndSettle();
    expect(ready, 1);
    expect(
      find.byKey(const ValueKey('cover-placeholder-book-0')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
