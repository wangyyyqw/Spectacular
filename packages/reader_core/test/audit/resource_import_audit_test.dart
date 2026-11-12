import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/epub/archive_reader.dart';
import 'package:reader_core/epub/epub_document.dart';
import 'package:reader_core/epub/importer.dart';
import 'package:reader_core/epub/resource_index.dart';

import 'audit_epub_fixture.dart';

void main() {
  test('文件名兜底命中同目录或全库唯一资源时记录修复次数', () {
    const path = 'OEBPS/images/pic.png';
    final reader = EpubArchive.fromBytes(auditZip({path: Uint8List(1)}));
    addTearDown(reader.close);
    final index = ResourceIndex.build(
      archive: reader,
      manifest: const [],
      opfPath: 'OEBPS/content.opf',
    );
    expect(index.resolve(path), path);
    expect(index.fallbackHits, 0, reason: '精确引用不算修复');
    expect(index.resolve('wrong/pic.png', baseDir: 'OEBPS/images'), path);
    expect(index.fallbackHits, 1, reason: '同目录文件名兜底必须计数');
    expect(index.resolve('wrong/pic.png', baseDir: 'OEBPS'), path);
    expect(index.fallbackHits, 2, reason: '全库唯一文件名兜底必须计数');
  });

  test('图片目录错误但文件名唯一，导入报告 L1 并标明一处修复', () async {
    final result = await openEpub(auditEpub(imageHref: 'wrong/pic.png'));
    addTearDown(() => result.document?.archive.close());
    expect(result.ok, isTrue);
    expect(result.report.readabilityLevel, EpubReadability.l1);
    expect(
      result.report.warnings,
      contains('E_RESOURCE_REPAIRED: 已自动修复 1 处引用'),
    );
    expect(
      result.document!.resources.resolve('wrong/pic.png', baseDir: 'OEBPS'),
      'OEBPS/images/pic.png',
    );
  });

  test('大条目声明尺寸过大时，文件导入报告缺章且保留其余正文', () async {
    const chapterPath = 'OEBPS/text/c1.xhtml';
    final bytes = auditEpub();
    _setDeclaredSize(bytes, chapterPath, 2 * 1024 * 1024);
    final directory = await Directory.systemTemp.createTemp('epub-size-');
    addTearDown(() => directory.delete(recursive: true));
    final file = await File('${directory.path}/book.epub').writeAsBytes(bytes);

    final result = await openEpubFile(file, verifyCrc: true);
    addTearDown(() => result.document?.archive.close());

    expect(result.ok, isTrue);
    expect(result.report.readabilityLevel, EpubReadability.l2);
    expect(result.report.warnings, contains('E_SPINE_MISSING: 1 个章节文件不存在'));
    expect(
      result.report.warnings,
      contains(
        allOf(startsWith('E_ZIP_ENTRY_TRUNCATED:'), contains(chapterPath)),
      ),
    );
    final document = result.document!;
    expect(document.isChapterMissing(0), isTrue);
    expect(document.chapterXhtml(1), contains(auditSecondText));
  });
}

void _setDeclaredSize(Uint8List bytes, String path, int size) {
  final data = ByteData.sublistView(bytes);
  for (var offset = 0; offset < bytes.length - 46; offset++) {
    if (data.getUint32(offset, Endian.little) != 0x02014b50) continue;
    final nameLength = data.getUint16(offset + 28, Endian.little);
    final name = utf8.decode(
      bytes.sublist(offset + 46, offset + 46 + nameLength),
    );
    if (name != path) continue;
    data.setUint32(offset + 24, size, Endian.little);
    return;
  }
  throw StateError('测试 ZIP 缺少条目：$path');
}
