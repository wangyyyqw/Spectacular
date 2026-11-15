import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/editing.dart';
import 'package:reader_core/epub/epub_document.dart';

import 'edit_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  setUp(
    () async =>
        directory = await Directory.systemTemp.createTemp('epub-write-test-'),
  );
  tearDown(() async => directory.delete(recursive: true));

  test('流式导出可从正式 EPUB 入口重开，未改图片字节保持一致', () async {
    final input = await createEditingFixture(directory);
    final session = await EpubEditSession.open(input);
    final image = session.readBytes('OPS/image.png');
    session.transaction(
      '改正文',
      (tx) => tx.writeText(
        'OPS/chapter.xhtml',
        editingXhtml.replaceFirst('另一段', '保存后的正文'),
      ),
    );
    final output = File('${directory.path}/saved.epub');
    try {
      await EpubWriter.write(session, output);
      final reopened = await openEpubFile(output, verifyCrc: true);
      expect(reopened.ok, isTrue);
      final document = reopened.document!;
      expect(document.chapterXhtml(0), contains('保存后的正文'));
      expect(document.archive.readBytes('OPS/image.png'), image);
      expect(document.archive.names.first, 'mimetype');
      expect(document.archive.validateOcf().warnings, isEmpty);
      document.archive.close();
      final original = await openEpubFile(input);
      expect(original.document!.chapterXhtml(0), contains('另一段'));
      original.document!.archive.close();
      await expectLater(
        EpubWriter.write(session, input),
        throwsA(isA<EpubEditException>()),
      );
    } finally {
      session.close();
    }
  });

  test('UTF-16 原章节写回保留字节序与 BOM', () async {
    final text = editingXhtml.replaceFirst('UTF-8', 'UTF-16');
    final data = ByteData((text.length + 1) * 2)
      ..setUint16(0, 0xfeff, Endian.little);
    for (var i = 0; i < text.length; i++) {
      data.setUint16((i + 1) * 2, text.codeUnitAt(i), Endian.little);
    }
    final input = await createEditingFixture(
      directory,
      chapterBytes: data.buffer.asUint8List(),
    );
    final session = await EpubEditSession.open(input);
    try {
      session.transaction(
        '改UTF16正文',
        (tx) => tx.writeText(
          'OPS/chapter.xhtml',
          session.readText('OPS/chapter.xhtml').replaceFirst('另一段', '新段落'),
        ),
      );
      final bytes = session.readBytes('OPS/chapter.xhtml')!;
      expect(bytes.take(2), [255, 254]);
      final output = File('${directory.path}/utf16.epub');
      await EpubWriter.write(session, output);
      final reopened = await openEpubFile(output);
      expect(reopened.document!.chapterXhtml(0), contains('新段落'));
      reopened.document!.archive.close();
    } finally {
      session.close();
    }
  });

  test('基线文件被外部修改时拒绝导出，不留下目标', () async {
    final input = await createEditingFixture(directory);
    final session = await EpubEditSession.open(input);
    try {
      await input.writeAsBytes([1], mode: FileMode.append);
      final output = File('${directory.path}/rejected.epub');
      await expectLater(
        EpubWriter.write(session, output),
        throwsA(isA<EpubEditException>()),
      );
      expect(output.existsSync(), isFalse);
    } finally {
      session.close();
    }
  });

  test('原归档含超限资源时拒绝导出，避免静默漏掉资源', () async {
    final input = await createEditingFixture(directory);
    final files = ZipDecoder().decodeBytes(await input.readAsBytes())
      ..addFile(ArchiveFile.string('unused.bin', '很小的压缩输入'));
    final bytes = Uint8List.fromList(ZipEncoder().encode(files));
    _oversizeUnusedEntry(bytes);
    await input.writeAsBytes(bytes);
    final session = await EpubEditSession.open(input);
    try {
      final output = File('${directory.path}/rejected-limit.epub');
      await expectLater(
        EpubWriter.write(session, output),
        throwsA(
          isA<EpubEditException>().having(
            (error) => error.message,
            '原因',
            contains('单条目预算'),
          ),
        ),
      );
      expect(output.existsSync(), isFalse);
      expect(await input.readAsBytes(), bytes);
    } finally {
      session.close();
    }
  });

  test('写出期间关闭会话会丢弃输出，原书保持可读且没有残留暂存目录', () async {
    final input = await createEditingFixture(directory);
    final before = await input.readAsBytes();
    final session = await EpubEditSession.open(input);
    final output = File('${directory.path}/cancelled.epub');
    final writing = EpubWriter.write(session, output);
    session.close();
    await expectLater(writing, throwsA(isA<EpubEditException>()));
    expect(output.existsSync(), isFalse);
    expect(await input.readAsBytes(), before);
    expect(directory.listSync().whereType<Directory>(), isEmpty);
  });

  test('目标目录写入失败不改变原书或既有文件', () async {
    final input = await createEditingFixture(directory);
    final before = await input.readAsBytes();
    final session = await EpubEditSession.open(input);
    final blocked = File('${directory.path}/blocked')..writeAsStringSync('保留');
    try {
      await expectLater(
        EpubWriter.write(session, File('${blocked.path}/book.epub')),
        throwsA(isA<FileSystemException>()),
      );
      expect(await input.readAsBytes(), before);
      expect(blocked.readAsStringSync(), '保留');
    } finally {
      session.close();
    }
  });

  test('首次管理类样式不迁移正文，导出重开仍可继续管理', () async {
    final input = await createEditingFixture(directory);
    final session = await EpubEditSession.open(input);
    try {
      ClassStyleEditor(session).apply('note', {'color': '#123456'});
      expect(session.summary.cssOnly, isTrue);
      final sheet = session.metadata['classStylesheet'];
      final output = File('${directory.path}/styles.epub');
      await EpubWriter.write(session, output);
      final reopened = await EpubEditSession.open(output);
      try {
        expect(reopened.metadata['classStylesheet'], sheet);
        ClassStyleEditor(reopened).apply('note', {'color': '#654321'});
        expect(reopened.metadata['classStylesheet'], sheet);
        expect(reopened.summary.cssOnly, isTrue);
        expect(reopened.readText(sheet as String), contains('#654321'));
        reopened.transaction('清除归属', (tx) => tx.metadata.clear());
        final restored = await EpubEditSession.open(
          output,
          draft: reopened.toDraft(),
        );
        expect(restored.metadata, isEmpty);
        restored.close();
        reopened.undo();
        final node = reopened
            .editableDocument('OPS/chapter.xhtml')
            .elements
            .firstWhere((element) => element.attributes['id'] == 'p');
        reopened.replaceText(node, '${node.text} ');
        expect(reopened.summary.cssOnly, isFalse);
      } finally {
        reopened.close();
      }
    } finally {
      session.close();
    }
  });
}

void _oversizeUnusedEntry(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  for (var offset = 0; offset + 46 < bytes.length; offset++) {
    if (data.getUint32(offset, Endian.little) != 0x02014b50) continue;
    final length = data.getUint16(offset + 28, Endian.little);
    final name = String.fromCharCodes(
      bytes.sublist(offset + 46, offset + 46 + length),
    );
    if (name != 'unused.bin') continue;
    data.setUint32(offset + 24, 64 * 1024 * 1024 + 1, Endian.little);
    return;
  }
  throw StateError('测试归档缺少待修改的资源');
}
