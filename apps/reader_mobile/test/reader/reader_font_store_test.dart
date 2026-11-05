import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/text/font_coverage.dart';
import 'package:reader_core/text/font_metrics.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/reader/reader_font_store.dart';
import 'package:reader_mobile/storage/db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;
  late AppDatabase db;
  late LibraryStore library;
  late ReaderFontStore store;
  final bytes = File('../../test_fonts/SourceHanSerifSC-Regular.otf')
      .readAsBytesSync();

  setUp(() {
    directory = Directory.systemTemp.createTempSync('reader_font_test');
    db = AppDatabase(NativeDatabase.memory());
    library = LibraryStore(
      database: db,
      directoryProvider: () async => directory,
    );
    store = ReaderFontStore(library, directoryProvider: () async => directory);
  });

  tearDown(() async {
    await db.close();
    await directory.delete(recursive: true);
  });

  test('字体复制并持久化，新实例可恢复并注册度量', () async {
    final font = await store.import(bytes, displayName: '/下载/中文宋体.otf');
    expect(font.family, matches(r'^user_[0-9a-f]{64}$'));
    expect(font.displayName, '中文宋体');
    expect(await File(font.filePath).readAsBytes(), bytes);
    expect(
      FontMetricsRegistry.xHeightRatio(font.family),
      closeTo(0.514, 0.0001),
    );
    expect(FontCoverageRegistry.covers(font.family, '中'.runes.single), isTrue);
    final restored = ReaderFontStore(
      LibraryStore(database: db, directoryProvider: () async => directory),
      directoryProvider: () async => directory,
    );
    expect((await restored.list()).single.displayName, '中文宋体');
    expect((await restored.load(font.family)).filePath, font.filePath);
  });

  test('同一字体重复导入只保留一项，保留初次名称', () async {
    final first = await store.import(bytes, displayName: '首次名称.otf');
    final second = await store.import(bytes, displayName: '改名.otf');
    expect(second.family, first.family);
    expect(second.displayName, '首次名称');
    expect(await store.list(), hasLength(1));
    expect(await Directory('${directory.path}/reader_fonts').list().length, 1);
  });

  test('重新导入修复过期存储路径，保留字体名称和条目', () async {
    final first = await store.import(bytes, displayName: '原始名称.otf');
    await (db.update(db.userFonts)
          ..where((row) => row.family.equals(first.family)))
        .write(const UserFontsCompanion(filePath: Value('/旧设备/失效字体.otf')));
    await expectLater(store.load(first.family), throwsFormatException);
    final repaired = await store.import(bytes, displayName: '重新导入.otf');
    expect(repaired.displayName, '原始名称');
    expect((await store.load(first.family)).filePath, first.filePath);
    expect(await store.list(), hasLength(1));
  });

  test('取消选择不产生目录、记录或设置', () async {
    final cancel = ReaderFontStore(
      library,
      directoryProvider: () async => directory,
      picker: () async => null,
    );
    expect(await cancel.pick(), isNull);
    expect(await cancel.list(), isEmpty);
    expect(await Directory('${directory.path}/reader_fonts').exists(), isFalse);
  });

  test('损坏、TTC、截断表与超限字体被拒绝，不保存记录', () async {
    final truncated = Uint8List.fromList(bytes.sublist(0, bytes.length - 512));
    final collection = Uint8List.fromList(bytes);
    ByteData.sublistView(collection).setUint32(0, 0x74746366);
    for (final invalid in [
      Uint8List(0),
      Uint8List.fromList([1, 2, 3]),
      truncated,
      collection,
      Uint8List(ReaderFontStore.maxBytes + 1),
    ]) {
      await expectLater(
        store.import(invalid, displayName: '无效.otf'),
        throwsA(isA<FormatException>()),
      );
    }
    expect(await store.list(), isEmpty);
    expect(await Directory('${directory.path}/reader_fonts').exists(), isFalse);
  });

  test('恢复缺失文件时失败，重新导入可修复同一条目', () async {
    final font = await store.import(bytes, displayName: '可恢复.otf');
    await File(font.filePath).delete();
    await expectLater(store.load(font.family), throwsA(isA<FormatException>()));
    final repaired = await store.import(bytes, displayName: '再次导入.otf');
    expect(repaired.family, font.family);
    expect(await store.list(), hasLength(1));
    expect((await store.load(font.family)).displayName, '可恢复');
  });

  test('内容被替换时不会命中已注册字体缓存', () async {
    final font = await store.import(bytes, displayName: '原字体.otf');
    final replacement = File('../../test_fonts/SourceHanSerifSC-Bold.otf')
        .readAsBytesSync();
    await File(font.filePath).writeAsBytes(replacement);
    await expectLater(
      store.load(font.family),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          '错误提示',
          contains('已改变'),
        ),
      ),
    );
  });

  test('非法族名与应用目录外路径不能被恢复', () async {
    await expectLater(store.load('../字体'), throwsA(isA<FormatException>()));
    const family =
        'user_0000000000000000000000000000000000000000000000000000000000000000';
    await library.saveUserFont(
      const ReaderFontEntry(
        family: family,
        filePath: '/tmp/外部字体.otf',
        displayName: '外部字体',
      ),
    );
    await expectLater(store.load(family), throwsA(isA<FormatException>()));
  });

  test('内存书库也能保存和去重字体清单', () async {
    final memory = LibraryStore.memory();
    const font = ReaderFontEntry(
      family: '测试族',
      filePath: '/测试字体.otf',
      displayName: '测试字体',
    );
    await memory.saveUserFont(font);
    await memory.saveUserFont(font);
    expect((await memory.listUserFonts()).single.displayName, '测试字体');
  });
}
