import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/epub/archive_reader.dart';
import 'package:reader_core/epub/container.dart';
import 'package:reader_core/epub/epub_exception.dart';
import 'package:reader_core/epub/opf.dart';

import '../support/corpus.dart';

OpfPackage? _parseSample(String name) {
  final corpus = findCorpusRoot();
  final bytes = readSampleBytes(corpus, name);
  if (bytes == null) {
    return null;
  }
  final archive = EpubArchive.fromBytes(bytes);
  final container = EpubContainer.parse(archive);
  final opfBytes = archive.readBytes(container.rootfilePath);
  return OpfParser.parse(utf8.decode(opfBytes!));
}

void main() {
  final corpus = findCorpusRoot();
  final skip = corpus == null ? '本地样本库缺失（test_corpus/ 不入库）' : null;

  const cases = <String, String>{
    'basic.epub': '山海小记',
    'styles.epub': '样式练习册',
    'toc-ncx.epub': '旧式目录',
    'real/zhushen-yuxi.epub': '诸神愚戏',
    'real/shiji-yuewei.epub': '史记',
  };

  cases.forEach((file, expectedTitle) {
    test('解析 OPF metadata/manifest/spine：$file', () {
      final package = _parseSample(file)!;
      expect(package.meta.title, contains(expectedTitle));
      expect(package.meta.language, isNotEmpty);
      expect(package.manifest, isNotEmpty);
      expect(package.spine, isNotEmpty);
      for (var i = 0; i < package.spine.length; i++) {
        expect(package.spine[i].index, i);
        expect(package.spine[i].href, isNotEmpty);
      }
    }, skip: skip);
  });

  test('EPUB2 与 EPUB3 的版本号保留', () {
    expect(_parseSample('basic.epub')!.version, startsWith('3'));
    expect(_parseSample('toc-ncx.epub')!.version, startsWith('2'));
  }, skip: skip);

  test('linear="no" 标记保留', () {
    const xml = '''
<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="uid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>测试书</dc:title>
    <dc:language>zh-CN</dc:language>
    <dc:identifier id="uid">urn:uuid:test</dc:identifier>
    <dc:creator>作者</dc:creator>
  </metadata>
  <manifest>
    <item id="c1" href="c1.xhtml" media-type="application/xhtml+xml"/>
    <item id="c2" href="c2.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine>
    <itemref idref="c1"/>
    <itemref idref="c2" linear="no"/>
  </spine>
</package>
''';
    final package = OpfParser.parse(xml);
    expect(package.spine, hasLength(2));
    expect(package.spine[0].linear, isTrue);
    expect(package.spine[1].linear, isFalse);
    expect(package.meta.title, '测试书');
    expect(package.meta.identifier, 'urn:uuid:test');
  });

  test('spine 引用缺失的 manifest id 时记录 warning 并跳过', () {
    const xml = '''
<package version="3.0">
  <metadata><title>书</title><language>zh</language><identifier>x</identifier></metadata>
  <manifest><item id="c1" href="c1.xhtml" media-type="application/xhtml+xml"/></manifest>
  <spine><itemref idref="c1"/><itemref idref="missing"/></spine>
</package>
''';
    final package = OpfParser.parse(xml);
    expect(package.spine, hasLength(1));
    expect(package.warnings.single, contains('missing'));
  });

  test('OPF 非法 XML 返回结构化错误', () {
    expect(
      () => OpfParser.parse('<package><manifest></package>'),
      throwsA(isA<EpubException>().having((e) => e.code, 'code', 'E_OPF_XML')),
    );
  });
}
