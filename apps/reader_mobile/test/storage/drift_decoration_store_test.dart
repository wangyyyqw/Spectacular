import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/library/revision_anchor_index.dart';
import 'package:reader_mobile/reader/reader_decoration_image_store.dart';
import 'package:reader_mobile/storage/db.dart';
import 'package:reader_ui/decorations/decoration.dart';
import 'package:reader_ui/annotations/annotation.dart';
import 'package:reader_ui/decorations/decoration_rules.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../library/fixtures/revision_epub.dart';

Future<Uint8List> _pictureBytes() async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawColor(const ui.Color(0xffaabbcc), ui.BlendMode.src);
  final picture = recorder.endRecording();
  final image = await picture.toImage(2000, 1000);
  final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
  image.dispose();
  picture.dispose();
  return bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late AppDatabase db;
  late LibraryStore library;
  late BookEntry book;
  late String first;
  late String last;

  setUp(() async {
    directory = Directory.systemTemp.createTempSync('decoration-store-');
    db = AppDatabase(NativeDatabase.memory());
    library = LibraryStore(
      database: db,
      directoryProvider: () async => directory,
    );
    final bytes = buildRevisionTestEpub();
    book = await library.importBytes(bytes);
    final chapter = (await buildRevisionAnchorBook(bytes)).chapter(0)!;
    final offset = chapter.text.indexOf(revisionQuote);
    first = chapter.cfiAt(offset)!;
    last = chapter.cfiAt(offset + revisionQuote.length, end: true)!;
  });

  tearDown(() async {
    await db.close();
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });

  test('装饰CRUD、同区间更新和唯一索引', () async {
    final images = ReaderDecorationImages(
      directoryProvider: () async => directory,
    );
    final store = library.decorationStore(book.id, images: images)!;
    final initial = (await store.add(
      startCfi: first,
      endCfi: last,
      quote: revisionQuote,
      style: ReaderDecorationPreset.emphasis.style,
    ))!;
    final changed = (await store.add(
      startCfi: first,
      endCfi: last,
      quote: revisionQuote,
      style: ReaderDecorationPreset.sticky.style,
    ))!;
    expect(changed.id, initial.id);
    expect(changed.createdAt, initial.createdAt);
    expect(await store.list(), hasLength(1));
    expect(changed.style.backgroundColor, 0xfffff3c4);
    final row = (await db.select(db.decorations).get()).single;
    expect((jsonDecode(row.styleJson) as Map<String, dynamic>)['v'], 1);
    await expectLater(
      db
          .into(db.decorations)
          .insert(
            DecorationsCompanion.insert(
              id: 'duplicate',
              bookId: row.bookId,
              startCfi: first,
              endCfi: last,
              quote: revisionQuote,
              styleJson: '{}',
              createdAt: 1,
              updatedAt: 1,
            ),
          ),
      throwsA(isA<sqlite.SqliteException>()),
    );
    await store.update(
      initial.id,
      style: const ReaderDecorationStyle(fontSizeScale: 1.5),
    );
    expect((await store.list()).single.style.fontSizeScale, 1.5);
    await store.remove(initial.id);
    expect(await store.list(), isEmpty);
  });

  test('手工高亮连块样式落库重读，更新样式保留内容位置与身份', () async {
    final store = library.decorationStore(
      book.id,
      images: ReaderDecorationImages(directoryProvider: () async => directory),
    )!;
    const style = ReaderDecorationStyle(
      highlight: ReaderDecorationHighlight(
        color: 0xFF123456,
        opacity: 0.4,
        joinLines: true,
      ),
    );
    final saved = (await store.add(
      startCfi: first,
      endCfi: last,
      quote: revisionQuote,
      style: style,
    ))!;
    var reloaded = (await store.list()).single;
    expect(reloaded.style.toJson(), style.toJson());
    final next = style.withValues({
      'highlight': const ReaderDecorationHighlight(
        style: ReaderAnnotationStyle.dottedUnderline,
      ).toJson(),
    });
    await store.update(saved.id, style: next);
    reloaded = (await store.list()).single;
    expect(reloaded.style.toJson(), next.toJson());
    expect(reloaded.id, saved.id);
    expect(reloaded.createdAt, saved.createdAt);
    expect(reloaded.quote, saved.quote);
    expect(reloaded.startCfi, saved.startCfi);
    expect(reloaded.endCfi, saved.endCfi);
    expect(await db.select(db.annotations).get(), isEmpty);
  });

  test('未知JSON字段忽略，非法值与损坏JSON回默认', () async {
    final store = library.decorationStore(
      book.id,
      images: ReaderDecorationImages(directoryProvider: () async => directory),
    )!;
    final decoration = (await store.add(
      startCfi: first,
      endCfi: last,
      quote: revisionQuote,
      style: const ReaderDecorationStyle(),
    ))!;
    await (db.update(
      db.decorations,
    )..where((table) => table.id.equals(decoration.id))).write(
      const DecorationsCompanion(
        styleJson: Value(
          '{"v":1,"fontSizeScale":"bad","color":-1,"borderStyle":"bad","future":42}',
        ),
      ),
    );
    final style = (await store.list()).single.style;
    expect(style.fontSizeScale, 1);
    expect(style.color, isNull);
    expect(style.borderStyle, ReaderDecorationBorderStyle.solid);
    await (db.update(db.decorations)
          ..where((table) => table.id.equals(decoration.id)))
        .write(const DecorationsCompanion(styleJson: Value('{bad')));
    expect((await store.list()).single.style.fontSizeScale, 1);
  });

  test('装饰图片缩小为PNG、独立目录、全库无引用才删除', () async {
    final images = ReaderDecorationImages(
      directoryProvider: () async => directory,
    );
    final path = await images.import(await _pictureBytes());
    expect(path, contains('/decoration_images/'));
    final bytes = await images.loadImage(path);
    expect(bytes.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    expect(frame.image.width, 1600);
    expect(frame.image.height, 800);
    frame.image.dispose();
    codec.dispose();
    await expectLater(images.loadImage('/outside.png'), throwsFormatException);
    await expectLater(
      images.import(Uint8List(21 * 1024 * 1024)),
      throwsFormatException,
    );
    final other = await library.importBytes(
      buildRevisionTestEpub(title: '另一本书'),
    );
    final firstStore = library.decorationStore(book.id, images: images)!;
    final otherStore = library.decorationStore(other.id, images: images)!;
    final style = ReaderDecorationStyle(backgroundImagePath: path);
    final firstRecord = (await firstStore.add(
      startCfi: first,
      endCfi: last,
      quote: revisionQuote,
      style: style,
    ))!;
    final otherRecord = (await otherStore.add(
      startCfi: first,
      endCfi: last,
      quote: revisionQuote,
      style: style,
    ))!;
    final ruleStore = library.decorationRuleStore(book.id, images: images)!;
    final group = (await ruleStore.listGroups()).first;
    await ruleStore.saveRule(
      ReaderDecorationRule(
        id: 'image-rule',
        groupId: group.id,
        pattern: r'原文|摘录',
        isRegex: true,
        style: ReaderDecorationRuleStyle(
          backgroundImagePath: path,
          backgroundImageFit: ReaderDecorationImageFit.tile,
        ),
      ),
    );
    await firstStore.remove(firstRecord.id);
    expect(File(path).existsSync(), isTrue);
    await otherStore.remove(otherRecord.id);
    expect(File(path).existsSync(), isTrue, reason: '正则规则仍引用图片时，删除手工装饰不能清理图片');
    final restoredRule = (await ruleStore.listRules()).single;
    expect(restoredRule.isRegex, isTrue);
    expect(
      restoredRule.style.backgroundImageFit,
      ReaderDecorationImageFit.tile,
    );
    await ruleStore.removeRule('image-rule');
    expect(File(path).existsSync(), isFalse);
  });

  test('删书级联清理装饰，软删除不损失装饰', () async {
    final store = library.decorationStore(
      book.id,
      images: ReaderDecorationImages(directoryProvider: () async => directory),
    )!;
    await store.add(
      startCfi: first,
      endCfi: last,
      quote: revisionQuote,
      style: const ReaderDecorationStyle(),
    );
    await library.remove(book.id);
    expect(await db.select(db.decorations).get(), hasLength(1));
    await (db.delete(
      db.books,
    )..where((table) => table.uuid.equals(book.id))).go();
    expect(await db.select(db.decorations).get(), isEmpty);
  });
}
