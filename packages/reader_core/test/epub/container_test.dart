import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/epub/archive_reader.dart';
import 'package:reader_core/epub/container.dart';
import 'package:reader_core/epub/epub_exception.dart';

import '../support/corpus.dart';

void main() {
  final corpus = findCorpusRoot();
  final skip = corpus == null ? '本地样本库缺失（test_corpus/ 不入库）' : null;

  for (final name in <String>['basic.epub', 'styles.epub', 'toc-ncx.epub']) {
    test('container.xml 正确定位 OPF：$name', () {
      final bytes = readSampleBytes(corpus, name)!;
      final archive = EpubArchive.fromBytes(bytes);
      final info = EpubContainer.parse(archive);
      expect(info.rootfilePath, endsWith('.opf'));
      expect(archive.contains(info.rootfilePath), isTrue);
    }, skip: skip);
  }

  test('缺少 container.xml 返回结构化错误', () {
    final bytes = buildZip(<String, String>{
      'mimetype': 'application/epub+zip',
    });
    final archive = EpubArchive.fromBytes(bytes);
    expect(
      () => EpubContainer.parse(archive),
      throwsA(
        isA<EpubException>().having(
          (e) => e.code,
          'code',
          'E_CONTAINER_MISSING',
        ),
      ),
    );
  });

  test('多个 rootfile 时取第一个', () {
    const xml = '''
<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/first.opf" media-type="application/oebps-package+xml"/>
    <rootfile full-path="alt/second.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>
''';
    final bytes = buildZip(<String, String>{
      'mimetype': 'application/epub+zip',
      EpubContainer.containerPath: xml,
      'OEBPS/first.opf': '<package/>',
      'alt/second.opf': '<package/>',
    });
    final info = EpubContainer.parse(EpubArchive.fromBytes(bytes));
    expect(info.rootfilePath, 'OEBPS/first.opf');
  });

  test('rootfile 缺少 full-path 时报错', () {
    const xml = '''
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles><rootfile media-type="application/oebps-package+xml"/></rootfiles>
</container>
''';
    final bytes = buildZip(<String, String>{EpubContainer.containerPath: xml});
    expect(
      () => EpubContainer.parse(EpubArchive.fromBytes(bytes)),
      throwsA(
        isA<EpubException>().having(
          (e) => e.code,
          'code',
          'E_CONTAINER_ROOTFILE',
        ),
      ),
    );
  });
}
