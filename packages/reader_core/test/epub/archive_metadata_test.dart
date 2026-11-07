import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/epub/archive_reader.dart';

void main() {
  test('大小查询使用未压缩字节，路径规范化与关闭语义一致', () {
    final text = '<p>章节原文。</p>' * 1000;
    final archive = EpubArchive.fromBytes(_zip(text), verify: false);
    addTearDown(archive.close);
    final expected = utf8.encode(text).length;
    expect(archive.uncompressedSizeOf('OEBPS/chapter.xhtml'), expected);
    expect(archive.uncompressedSizeOf('/OEBPS\\chapter.xhtml'), expected);
    expect(archive.uncompressedSizeOf('missing.xhtml'), isNull);
    archive.close();
    expect(archive.uncompressedSizeOf('OEBPS/chapter.xhtml'), isNull);
  });

  test('压缩流损坏仍可查询大小，查询不解压或移除条目', () {
    final text = '<p>元数据查询不得读取正文。</p>' * 1000;
    final zip = _zip(text);
    final data = ByteData.sublistView(zip);
    final contentStart =
        30 +
        data.getUint16(26, Endian.little) +
        data.getUint16(28, Endian.little);
    zip[contentStart] = 0x07; // 保留的 deflate 块类型，只在解压时失败。
    final archive = EpubArchive.fromBytes(zip, verify: false);
    addTearDown(archive.close);

    expect(
      archive.uncompressedSizeOf('OEBPS/chapter.xhtml'),
      utf8.encode(text).length,
    );
    expect(archive.contains('OEBPS/chapter.xhtml'), isTrue);
    expect(archive.length, 1);
    expect(archive.readBytes('OEBPS/chapter.xhtml'), isNull);
    expect(archive.contains('OEBPS/chapter.xhtml'), isFalse);
  });

  test('文件后端打开后大小查询不再次读取归档数据', () async {
    final directory = await Directory.systemTemp.createTemp('epub-size-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/book.epub');
    final text = '<p>读取目录后不再访问文件内容。</p>' * 1000;
    await file.writeAsBytes(_zip(text));
    final archive = await EpubArchive.fromFile(file);
    addTearDown(archive.close);
    // 打开时已保存中央目录。将数据截断后，元数据仍应可独立使用。
    final handle = await file.open(mode: FileMode.write);
    await handle.close();

    expect(
      archive.uncompressedSizeOf('OEBPS/chapter.xhtml'),
      utf8.encode(text).length,
    );
    expect(archive.contains('OEBPS/chapter.xhtml'), isTrue);
    expect(archive.readBytes('OEBPS/chapter.xhtml'), isNull);
  });

  test('旧归档后端复用条目已有大小，不将压缩大小作为权重', () {
    final text = '<p>旧后端字节权重。</p>' * 1000;
    final archive = EpubArchive.fromBytes(
      _zip(text, compression: CompressionType.bzip2),
      verify: false,
    );
    addTearDown(archive.close);
    expect(archive.compressionOf('OEBPS/chapter.xhtml'), CompressionType.bzip2);
    expect(
      archive.uncompressedSizeOf('OEBPS/chapter.xhtml'),
      utf8.encode(text).length,
    );
    expect(archive.readString('OEBPS/chapter.xhtml'), text);
  });
}

Uint8List _zip(
  String text, {
  CompressionType compression = CompressionType.deflate,
}) {
  final files = Archive()
    ..addFile(
      ArchiveFile.string('OEBPS/chapter.xhtml', text)
        ..compression = compression,
    );
  return Uint8List.fromList(ZipEncoder().encode(files));
}
