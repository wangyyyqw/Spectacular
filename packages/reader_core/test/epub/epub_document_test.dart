import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/epub/epub_document.dart';

import '../support/corpus.dart';

void main() {
  final corpus = findCorpusRoot();
  final skip = corpus == null ? '本地样本库缺失（test_corpus/ 不入库）' : null;

  test('样本库全部可打开：meta/spine/toc/report 完整', () async {
    final manifest = jsonDecode(
      File('${corpus!.path}/manifest.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final samples = (manifest['samples'] as List).cast<Map<String, dynamic>>();
    for (final sample in samples) {
      final file = sample['file'] as String;
      final bytes = readSampleBytes(corpus, file)!;
      final stopwatch = Stopwatch()..start();
      final result = await openEpub(bytes);
      stopwatch.stop();
      // ignore: avoid_print
      print(
        'P1-05 ${sample['id']} ok=${result.ok} '
        'spine=${result.document?.spine.length} '
        'ms=${stopwatch.elapsedMilliseconds}',
      );

      expect(result.ok, isTrue, reason: '$file: ${result.report.message}');
      final document = result.document!;
      expect(document.meta.title, isNotEmpty, reason: file);
      expect(document.spine, isNotEmpty, reason: file);
      expect(document.toc, isNotEmpty, reason: file);
      expect(document.report.ok, isTrue, reason: file);
    }
  }, skip: skip);

  test('破损结构样本可打开（缺资源不在打开阶段报错）', () async {
    final result = await openEpub(
      readSampleBytes(corpus, 'broken-resource.epub')!,
    );
    expect(result.ok, isTrue);
    expect(result.document!.report.ok, isTrue);
  }, skip: skip);

  test('真实大书打开并记录耗时', () async {
    final bytes = readSampleBytes(corpus, 'real/zhushen-yuxi.epub')!;
    final stopwatch = Stopwatch()..start();
    final result = await openEpub(bytes);
    stopwatch.stop();
    // ignore: avoid_print
    print(
      'P1-05 zhushen-yuxi spine=${result.document?.spine.length} ms=${stopwatch.elapsedMilliseconds}',
    );
    expect(result.ok, isTrue);
    expect(result.document!.report.warnings, isNotEmpty);
  }, skip: skip);

  test('非 ZIP 字节返回 E_ARCHIVE，不抛异常', () async {
    final result = await openEpub(buildGarbage());
    expect(result.ok, isFalse);
    expect(result.report.errorCode, 'E_ARCHIVE');
  });

  test('缺 container.xml 返回 E_CONTAINER_MISSING', () async {
    final result = await openEpub(
      buildZip(<String, String>{'mimetype': 'application/epub+zip'}),
    );
    expect(result.ok, isFalse);
    expect(result.report.errorCode, 'E_CONTAINER_MISSING');
  });

  test('mimetype 内容错误返回 E_OCF', () async {
    final result = await openEpub(
      buildZip(<String, String>{'mimetype': 'text/plain'}),
    );
    expect(result.ok, isFalse);
    expect(result.report.errorCode, 'E_OCF');
  });

  test('OPF 非法 XML 返回 E_OPF_XML', () async {
    const xml = '''
<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles><rootfile full-path="content.opf" media-type="application/oebps-package+xml"/></rootfiles>
</container>
''';
    final result = await openEpub(
      buildZip(<String, String>{
        'mimetype': 'application/epub+zip',
        'META-INF/container.xml': xml,
        'content.opf': '<package><manifest></package>',
      }),
    );
    expect(result.ok, isFalse);
    expect(result.report.errorCode, 'E_OPF_XML');
  });
}
