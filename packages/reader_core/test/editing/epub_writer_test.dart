import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/editing.dart';
import 'package:reader_core/epub/epub_document.dart';
import 'package:xml/xml.dart';

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

  for (final version in ['2.0', '3.0']) {
    test('EPUB $version 多作者、标签与封面导出重开，未改元数据和资源保留', () async {
      final input = await createEditingFixture(
        directory,
        packageText: _metadataPackage(version),
      );
      final originalBytes = await input.readAsBytes();
      final session = await EpubEditSession.open(input);
      final original = {
        for (final path in [
          'OPS/chapter.xhtml',
          'OPS/style.css',
          'OPS/image.png',
          'META-INF/container.xml',
        ])
          path: session.readBytes(path),
      };
      final editor = PackageEditor(session);
      const title = '新书名 & <特别版> 😀';
      const description = '简介第一行 & <正文>\n第二行';
      const creators = ['甲 & 乙', '作者 <丙> 😀'];
      const subjects = ['标签 & 一', '标签 <二>'];
      try {
        editor.setMetadata({'title': title, 'description': description});
        editor.setMetadataValues('creator', creators);
        editor.setMetadataValues('subject', subjects);
        final cover = Uint8List.fromList([
          ...session.readBytes('OPS/image.png')!,
          0,
        ]);
        editor.addResource('OPS/new-cover.png', cover, 'image/png');
        editor.setCover('OPS/new-cover.png');
        final output = File('${directory.path}/metadata-$version.epub');
        await EpubWriter.write(session, output);
        final reopened = await openEpubFile(output, verifyCrc: true);
        expect(reopened.ok, isTrue);
        final document = reopened.document!;
        try {
          expect(document.package.meta.title, title);
          expect(document.package.meta.author, creators.join('、'));
          expect(document.package.meta.identifier, 'edit-fixture');
          expect(document.package.meta.language, 'zh');
          expect(document.coverResourcePath, 'OPS/new-cover.png');
          expect(document.readCoverBytes(), cover);
          final opf = XmlDocument.parse(
            document.archive.readString(document.opfPath)!,
          );
          expect(_dcValues(opf, 'creator'), creators);
          expect(_dcValues(opf, 'subject'), subjects);
          expect(_dcValues(opf, 'description'), [description]);
          expect(_dcValues(opf, 'publisher'), ['保留出版社']);
          expect(_dcValues(opf, 'contributor'), ['保留译者']);
          final metadata = opf.descendants.whereType<XmlElement>().firstWhere(
            (node) => node.name.local == 'metadata',
          );
          expect(
            metadata.childElements
                .where((node) => node.getAttribute('refines') != null)
                .map((node) => node.getAttribute('refines')),
            unorderedEquals(['#title', '#translator']),
          );
          expect(
            metadata.childElements
                .singleWhere((node) => node.namespaceUri == 'urn:publisher')
                .innerText,
            '保留自定义标签',
          );
          final covers = metadata.childElements.where(
            (node) =>
                node.getAttribute('name')?.trim().toLowerCase() == 'cover',
          );
          expect(covers, hasLength(1));
          final coverItem = document.package.manifest.singleWhere(
            (item) => item.href == 'new-cover.png',
          );
          expect(covers.single.getAttribute('content'), coverItem.id);
          expect(
            coverItem.properties.contains('cover-image'),
            version == '3.0',
          );
          expect(
            document.package.manifest
                .singleWhere((item) => item.id == 'img')
                .properties,
            version == '3.0' ? ['scripted'] : isEmpty,
          );
          for (final entry in original.entries) {
            expect(document.archive.readBytes(entry.key), entry.value);
          }
        } finally {
          document.archive.close();
        }
        expect(await input.readAsBytes(), originalBytes);

        final clearing = await EpubEditSession.open(output);
        try {
          final clearedEditor = PackageEditor(clearing);
          clearedEditor.setMetadataValues('creator', const []);
          clearedEditor.setMetadataValues('subject', const []);
          final clearedFile = File('${directory.path}/cleared-$version.epub');
          await EpubWriter.write(clearing, clearedFile);
          final cleared = (await openEpubFile(clearedFile)).document!;
          try {
            final opf = XmlDocument.parse(
              cleared.archive.readString(cleared.opfPath)!,
            );
            expect(cleared.package.meta.author, isEmpty);
            expect(_dcValues(opf, 'creator'), isEmpty);
            expect(_dcValues(opf, 'subject'), isEmpty);
            expect(_dcValues(opf, 'contributor'), ['保留译者']);
            expect(cleared.readCoverBytes(), cover);
          } finally {
            cleared.archive.close();
          }
        } finally {
          clearing.close();
        }
      } finally {
        session.close();
      }
    });
  }

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

  test('未修改压缩资源的 CRC 损坏仍拒绝导出并清理暂存文件', () async {
    final input = await createEditingFixture(directory);
    final files = ZipDecoder().decodeBytes(await input.readAsBytes())
      ..addFile(ArchiveFile.string('unused.bin', '保留压缩资源' * 100));
    final bytes = Uint8List.fromList(ZipEncoder().encode(files));
    final data = ByteData.sublistView(bytes);
    var corrupted = false;
    for (var offset = 0; offset + 46 < bytes.length; offset++) {
      if (data.getUint32(offset, Endian.little) != 0x02014b50) continue;
      final length = data.getUint16(offset + 28, Endian.little);
      final name = String.fromCharCodes(
        bytes.sublist(offset + 46, offset + 46 + length),
      );
      if (name != 'unused.bin') continue;
      expect(data.getUint16(offset + 10, Endian.little), 8);
      final localOffset = data.getUint32(offset + 42, Endian.little);
      final badCrc = data.getUint32(offset + 16, Endian.little) ^ 1;
      data.setUint32(offset + 16, badCrc, Endian.little);
      data.setUint32(localOffset + 14, badCrc, Endian.little);
      corrupted = true;
      break;
    }
    expect(corrupted, isTrue);
    await input.writeAsBytes(bytes);
    final session = await EpubEditSession.open(input);
    try {
      PackageEditor(session).setMetadata({'title': '只改资料'});
      final output = File('${directory.path}/rejected-crc.epub');
      await expectLater(
        EpubWriter.write(session, output),
        throwsA(isA<EpubEditException>()),
      );
      expect(output.existsSync(), isFalse);
      expect(directory.listSync().whereType<Directory>(), isEmpty);
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

String _metadataPackage(String version) =>
    '<opf:package xmlns:opf="http://www.idpf.org/2007/opf" '
    'version="$version" unique-identifier="id">'
    '<opf:metadata xmlns:dc="http://purl.org/dc/elements/1.1/" '
    'xmlns:publisher="urn:publisher">'
    '<dc:identifier id="id">edit-fixture</dc:identifier>'
    '<dc:title id="title">原书名</dc:title><dc:language>zh</dc:language>'
    '<dc:description>原简介</dc:description><dc:publisher>保留出版社</dc:publisher>'
    '<dc:creator id="author-a" opf:role="aut" opf:file-as="旧排序">旧作者甲</dc:creator>'
    '<dc:creator id="author-b">旧作者乙</dc:creator>'
    '<opf:meta refines="#author-role" property="alternate-script">旧附属项</opf:meta>'
    '<opf:meta id="author-role" refines="#author-a" property="role">aut</opf:meta>'
    '<dc:subject id="subject-a">旧标签甲</dc:subject>'
    '<dc:subject id="subject-b">旧标签乙</dc:subject>'
    '<opf:meta refines="#subject-a" property="authority">旧标签细化</opf:meta>'
    '<dc:contributor id="translator">保留译者</dc:contributor>'
    '<opf:meta refines="#translator" property="role">trl</opf:meta>'
    '<opf:meta refines="#title" property="title-type">main</opf:meta>'
    '<publisher:subject>保留自定义标签</publisher:subject>'
    '<opf:meta name=" Cover " content="img"/>'
    '</opf:metadata><opf:manifest>'
    '<opf:item id="c" href="chapter.xhtml" media-type="application/xhtml+xml"/>'
    '<opf:item id="css" href="style.css" media-type="text/css"/>'
    '<opf:item id="img" href="image.png" media-type="image/png"'
    '${version == '3.0' ? ' properties="cover-image scripted"' : ''}/>'
    '</opf:manifest><opf:spine><opf:itemref idref="c"/></opf:spine></opf:package>';

List<String> _dcValues(XmlDocument document, String field) => document
    .descendants
    .whereType<XmlElement>()
    .where(
      (node) =>
          node.name.local == field &&
          node.namespaceUri == 'http://purl.org/dc/elements/1.1/',
    )
    .map((node) => node.innerText)
    .toList();

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
