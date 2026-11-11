import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/epub/importer.dart';
import 'package:drift/native.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/storage/db.dart';

import '../support/test_epub.dart';

Uint8List _buildL2Epub() {
  const opf = '''
<?xml version="1.0"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="uid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="uid">urn:uuid:l2</dc:identifier>
    <dc:title>L2书</dc:title><dc:language>zh</dc:language>
  </metadata>
  <manifest>
    <item id="c1" href="c1.xhtml" media-type="application/xhtml+xml"/>
    <item id="c2" href="c2-missing.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine><itemref idref="c1"/><itemref idref="c2"/></spine>
</package>''';
  const container = '''
<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
</container>''';
  final archive = Archive();
  void add(String name, String content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }

  add('mimetype', 'application/epub+zip');
  add('META-INF/container.xml', container);
  add('OEBPS/content.opf', opf);
  add('OEBPS/c1.xhtml', '<html><body><p>x</p></body></html>');
  return Uint8List.fromList(ZipEncoder().encodeBytes(archive));
}

void main() {
  group('拒绝文案映射（P3-27，§55.3）', () {
    test('四类拒绝码给出准确文案与建议', () {
      final archive = EpubRejectionMessages.forCode('E_ARCHIVE', null);
      expect(archive.title, contains('不是 EPUB'));
      expect(archive.suggestion, isNotEmpty);

      final ocf = EpubRejectionMessages.forCode('E_OCF', null);
      expect(ocf.title, contains('标准 EPUB'));

      final spine = EpubRejectionMessages.forCode('E_SPINE_EMPTY', null);
      expect(spine.title, contains('阅读顺序'));

      final internal = EpubRejectionMessages.forCode('E_INTERNAL', null);
      expect(internal.title, contains('无法解析'));
    });

    test('文案无技术术语与堆栈泄漏', () {
      for (final code in <String?>[
        'E_ARCHIVE',
        'E_OCF',
        'E_CONTAINER_MISSING',
        'E_OPF_MISSING',
        'E_SPINE_EMPTY',
        'E_INTERNAL',
        'E_UNKNOWN_NEW_CODE',
        null,
      ]) {
        final message = EpubRejectionMessages.forCode(code, null);
        expect(message.title.contains('Exception'), isFalse, reason: '$code');
        expect(message.title.contains('at #'), isFalse, reason: '$code');
        expect(message.title.contains('null'), isFalse, reason: '$code');
        expect(message.suggestion.isNotEmpty, isTrue, reason: '$code');
      }
    });

    test('未知码回退通用文案', () {
      final message = EpubRejectionMessages.forCode('E_NEVER_SEEN', null);
      expect(message.title, contains('无法解析'));
    });

    test('重复书籍提示直接阅读，不误报格式错误', () {
      final duplicate = EpubRejectionMessages.forCode('E_DUPLICATE', null);
      expect(duplicate.title, '这本书已在书架中');
      expect(duplicate.suggestion, '请直接从书架打开阅读');
    });
  });

  group('分级落库与角标（P3-27，§55.2）', () {
    test('导入分级写入 BookEntry 并持久化', () async {
      final tempDir = await Directory.systemTemp.createTemp('library_p327');
      addTearDown(() => tempDir.delete(recursive: true));
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final store = LibraryStore(
        database: db,
        directoryProvider: () async => tempDir,
      );
      final entry = await store.importBytes(
        buildTestEpub(title: '分级书', author: '作者'),
      );
      expect(entry.readabilityLevel, 0, reason: '完整书 L0');
      final restored = (await store.list()).single;
      expect(restored.id, entry.id);
      expect(restored.readabilityLevel, 0);
    });

    test('L2 书（spine 缺失）导入后 level=2', () async {
      final tempDir = await Directory.systemTemp.createTemp('library_p327b');
      addTearDown(() => tempDir.delete(recursive: true));
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final store = LibraryStore(
        database: db,
        directoryProvider: () async => tempDir,
      );
      // 手工构造 spine 缺失书：manifest 两个章节只有一份文件。
      final bytes = _buildL2Epub();
      final entry = await store.importBytes(bytes);
      expect(entry.readabilityLevel, 2);
    });
  });
}
