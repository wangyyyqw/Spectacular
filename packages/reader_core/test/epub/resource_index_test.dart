import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/epub/archive_reader.dart';
import 'package:reader_core/epub/container.dart';
import 'package:reader_core/epub/opf.dart';
import 'package:reader_core/epub/resource_index.dart';

import '../support/corpus.dart';

({EpubArchive archive, String opfDir, ResourceIndex index})? _open(
  String name,
) {
  final bytes = readSampleBytes(findCorpusRoot(), name);
  if (bytes == null) {
    return null;
  }
  final archive = EpubArchive.fromBytes(bytes);
  final container = EpubContainer.parse(archive);
  final opf = OpfParser.parse(
    utf8.decode(archive.readBytes(container.rootfilePath)!),
  );
  final opfDir = container.rootfilePath.contains('/')
      ? container.rootfilePath.substring(
          0,
          container.rootfilePath.lastIndexOf('/'),
        )
      : '';
  return (
    archive: archive,
    opfDir: opfDir,
    index: ResourceIndex.build(
      archive: archive,
      manifest: opf.manifest,
      opfPath: container.rootfilePath,
    ),
  );
}

void main() {
  final corpus = findCorpusRoot();
  final skip = corpus == null ? '本地样本库缺失（test_corpus/ 不入库）' : null;

  test('七级查找：精确、大小写、URL 编码、锚点、反斜杠、文件名兜底', () {
    final opened = _open('basic.epub')!;
    final index = opened.index;
    const base = 'OEBPS';

    expect(
      index.resolve('text/chapter1.xhtml', baseDir: base),
      'OEBPS/text/chapter1.xhtml',
    );
    expect(
      index.resolve('TEXT/CHAPTER1.XHTML', baseDir: base),
      'OEBPS/text/chapter1.xhtml',
    );
    expect(
      index.resolve('text/%63hapter1.xhtml', baseDir: base),
      'OEBPS/text/chapter1.xhtml',
    );
    expect(
      index.resolve('text/chapter1.xhtml#frag?x=1', baseDir: base),
      'OEBPS/text/chapter1.xhtml',
    );
    expect(
      index.resolve('text\\chapter1.xhtml', baseDir: base),
      'OEBPS/text/chapter1.xhtml',
    );
    expect(
      index.resolve('wrong-dir/chapter1.xhtml', baseDir: base),
      'OEBPS/text/chapter1.xhtml',
    );
    expect(index.resolve('missing.xhtml', baseDir: base), isNull);
  }, skip: skip);

  test('按 media-type 兜底命中同扩展名资源', () {
    final opened = _open('styles.epub')!;
    final path = opened.index.resolve(
      'nowhere/not-here.css',
      baseDir: opened.opfDir,
      mediaType: 'text/css',
    );
    expect(path, isNotNull);
    expect(path, endsWith('.css'));
  }, skip: skip);

  test('小写冲突时不做模糊匹配', () {
    final archive = Archive()
      ..addFile(ArchiveFile('a/C1.xhtml', 1, utf8.encode('a')))
      ..addFile(ArchiveFile('a/c1.xhtml', 1, utf8.encode('b')));
    final bytes = Uint8List.fromList(ZipEncoder().encode(archive));
    final reader = EpubArchive.fromBytes(bytes);
    final index = ResourceIndex.build(
      archive: reader,
      manifest: const [],
      opfPath: 'x.opf',
    );
    expect(index.conflicts, isNotEmpty);
    expect(index.resolve('A/C1.XHTML'), isNull);
    expect(index.resolve('a/C1.xhtml'), 'a/C1.xhtml');
  });

  test('read 返回命中资源字节', () {
    final opened = _open('basic.epub')!;
    final bytes = opened.index.read(
      opened.archive,
      'text/chapter1.xhtml',
      baseDir: 'OEBPS',
    );
    expect(bytes, isNotNull);
    expect(utf8.decode(bytes!), contains('<html'));
  }, skip: skip);

  test('中文路径与百分号编码混用时正确读取字体，非法百分号保留原名', () {
    const font = 'Fonts/方正东港宋 简 ExtraBold.TTF';
    const literal = 'Fonts/方正%ZZ.ttf';
    final archive = Archive()
      ..addFile(ArchiveFile(font, 1, [1]))
      ..addFile(ArchiveFile(literal, 1, [2]));
    final reader = EpubArchive.fromBytes(
      Uint8List.fromList(ZipEncoder().encode(archive)),
    );
    addTearDown(reader.close);
    final index = ResourceIndex.build(
      archive: reader,
      manifest: const [],
      opfPath: 'OEBPS/content.opf',
    );
    expect(
      index.read(
        reader,
        '../Fonts/方正东港宋%20简%20ExtraBold.TTF',
        baseDir: 'OEBPS',
      ),
      [1],
    );
    expect(
      index.resolve(
        '../Fonts/${Uri.encodeComponent('方正东港宋 简 ExtraBold.TTF')}',
        baseDir: 'OEBPS',
      ),
      font,
    );
    expect(index.resolve('../Fonts/方正%ZZ.ttf', baseDir: 'OEBPS'), literal);
  });
}
