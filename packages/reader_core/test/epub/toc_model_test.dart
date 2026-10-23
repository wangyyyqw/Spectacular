import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/api.dart';
import 'package:reader_core/epub/epub_document.dart';

import '../support/corpus.dart';

const _container = '''
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
</container>
''';

String _opf(int chapters) =>
    '''
<package version="3.0" unique-identifier="uid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>目录模型测试</dc:title><dc:language>zh-CN</dc:language>
    <dc:identifier id="uid">urn:uuid:toc-model</dc:identifier>
  </metadata>
  <manifest>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
    ${List.generate(chapters, (i) => '<item id="c$i" href="ch${i + 1}.xhtml" media-type="application/xhtml+xml"/>').join()}
  </manifest>
  <spine>
    ${List.generate(chapters, (i) => '<itemref idref="c$i"/>').join()}
  </spine>
</package>
''';

String _nav(String items) {
  final body = items.trimLeft().startsWith('<ol>') ? items : '<ol>$items</ol>';
  return '''
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
<body><nav epub:type="toc">$body</nav></body></html>
''';
}

Map<String, String> _files(int chapters, String nav) => <String, String>{
  'mimetype': 'application/epub+zip',
  'META-INF/container.xml': _container,
  'OEBPS/content.opf': _opf(chapters),
  'OEBPS/nav.xhtml': nav,
  for (var i = 1; i <= chapters; i++)
    'OEBPS/ch$i.xhtml': '<html><body><p id="p$i">第 $i 章</p></body></html>',
};

List<TocEntry> _flatten(List<TocEntry> entries) {
  final result = <TocEntry>[];
  void walk(List<TocEntry> nodes) {
    for (final node in nodes) {
      result.add(node);
      walk(node.children);
    }
  }

  walk(entries);
  return result;
}

void main() {
  final corpus = findCorpusRoot();
  final skip = corpus == null ? '本地样本库缺失（test_corpus/ 不入库）' : null;

  test('重复目标合并到首次出现项，子项保留', () async {
    const nav = '''
<ol>
  <li><a href="ch1.xhtml#a">A</a>
    <ol><li><a href="ch2.xhtml">B</a></li></ol>
  </li>
  <li><a href="ch1.xhtml#a">A 重复</a>
    <ol><li><a href="ch3.xhtml">C</a></li></ol>
  </li>
  <li><a href="ch1.xhtml#b">AB</a></li>
</ol>
''';
    final result = await openEpub(buildZip(_files(5, _nav(nav))));
    expect(result.ok, isTrue);
    final toc = result.document!.toc;
    expect(toc, hasLength(2));
    expect(toc[0].fragment, 'a');
    expect(toc[0].children.map((e) => e.title), <String>['B', 'C']);
    expect(toc[1].fragment, 'b');
    expect(result.report.warnings.any((w) => w.contains('目录去重')), isTrue);
  });

  test('目标无效的叶子被移除，有效子项保留', () async {
    const nav = '''
<ol>
  <li><a href="missing.xhtml#x">坏项</a>
    <ol><li><a href="ch1.xhtml">好项</a></li></ol>
  </li>
  <li><a href="missing.xhtml#y">另一个坏项</a></li>
</ol>
''';
    final result = await openEpub(buildZip(_files(2, _nav(nav))));
    expect(result.ok, isTrue);
    final toc = result.document!.toc;
    expect(toc, hasLength(1));
    expect(toc.single.spineIndex, -1);
    expect(toc.single.children.single.title, '好项');
    expect(result.report.warnings.any((w) => w.contains('目录移除')), isTrue);
  });

  test('fragment 百分号解码并保留', () async {
    const nav = '<ol><li><a href="ch1.xhtml#p%201">片段</a></li></ol>';
    final result = await openEpub(buildZip(_files(2, _nav(nav))));
    expect(result.document!.toc.single.fragment, 'p 1');
  });

  test('100 章 TOC 与 spine 无错位', () async {
    final items = List.generate(
      100,
      (i) => '<li><a href="ch${i + 1}.xhtml#p${i + 1}">第 ${i + 1} 章</a></li>',
    ).join();
    final result = await openEpub(
      buildZip(_files(100, _nav('<ol>$items</ol>'))),
    );
    expect(result.ok, isTrue);
    final toc = result.document!.toc;
    expect(toc, hasLength(100));
    for (var i = 0; i < 100; i++) {
      expect(toc[i].spineIndex, i, reason: '第 ${i + 1} 项');
      expect(toc[i].fragment, 'p${i + 1}');
      expect(toc[i].title, '第 ${i + 1} 章');
    }
    final keys = _flatten(toc)
        .map((e) => '${e.spineIndex}#${e.fragment}')
        .toSet();
    expect(keys, hasLength(100));
  });

  test('真实样本目录去重后索引有效、无重复目标', () async {
    final manifest = jsonDecode(
      File('${corpus!.path}/manifest.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    for (final sample
        in (manifest['samples'] as List).cast<Map<String, dynamic>>()) {
      final file = sample['file'] as String;
      final bytes = readSampleBytes(corpus, file)!;
      final opened = await openEpub(bytes);
      final document = opened.document;
      expect(document, isNotNull, reason: file);
      final flat = _flatten(document!.toc);
      final keys = <String>{};
      for (final entry in flat) {
        if (entry.spineIndex >= 0) {
          expect(
            entry.spineIndex,
            lessThan(document.spine.length),
            reason: file,
          );
          final key = '${entry.spineIndex}#${entry.fragment ?? ''}';
          expect(keys.add(key), isTrue, reason: '$file 重复目录目标：$key');
        }
      }
      // ignore: avoid_print
      print('P1-08 $file toc=${flat.length} roots=${document.toc.length}');
    }
  }, skip: skip);
}
