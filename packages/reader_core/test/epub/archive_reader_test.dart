import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/epub/archive_reader.dart';
import 'package:reader_core/epub/epub_exception.dart';

import '../support/corpus.dart';

void main() {
  final corpus = findCorpusRoot();
  final skip = corpus == null ? '本地样本库缺失（test_corpus/ 不入库）' : null;

  test('合规样本通过 OCF 校验（含真实 EPUB2 诸神愚戏）', () {
    for (final name in <String>[
      'basic.epub',
      'styles.epub',
      'toc-ncx.epub',
      'broken-resource.epub',
    ]) {
      final archive = EpubArchive.fromBytes(readSampleBytes(corpus, name)!);
      final report = archive.validateOcf();
      expect(report.errors, isEmpty, reason: '$name: ${report.errors}');
    }
    final real = EpubArchive.fromBytes(
      readSampleBytes(corpus, 'real/zhushen-yuxi.epub')!,
    );
    final realReport = real.validateOcf();
    expect(realReport.errors, isEmpty);
    expect(realReport.warnings, contains(contains('mimetype 被压缩')));
  }, skip: skip);

  test('按路径取字节；不存在的路径返回 null', () {
    final archive = EpubArchive.fromBytes(
      readSampleBytes(corpus, 'basic.epub')!,
    );
    expect(archive.readBytes('META-INF/container.xml'), isNotNull);
    expect(archive.readBytes('not/found.txt'), isNull);
    expect(archive.contains('META-INF/container.xml'), isTrue);
  }, skip: skip);

  test('CRC 错误在打开时报告为 E_ARCHIVE', () {
    final content = utf8.encode('hello epub content with crc check');
    final file = ArchiveFile('x.txt', content.length, content)
      ..compression = CompressionType.none;
    final archive = Archive()..addFile(file);
    final zip = Uint8List.fromList(ZipEncoder().encode(archive));

    // 找到内容字节并翻转一位，制造 CRC 不匹配。
    final index = _indexOf(zip, content);
    expect(index, greaterThan(0));
    zip[index] = zip[index] ^ 0xFF;

    expect(
      () => EpubArchive.fromBytes(zip),
      throwsA(
        isA<EpubException>().having(
          (e) => e.code,
          'code',
          anyOf('E_ARCHIVE', 'E_CRC'),
        ),
      ),
    );
  });

  test('非 ZIP 字节报告为 E_ARCHIVE', () {
    final garbage = Uint8List.fromList(List<int>.generate(128, (i) => i));
    expect(
      () => EpubArchive.fromBytes(garbage),
      throwsA(isA<EpubException>().having((e) => e.code, 'code', 'E_ARCHIVE')),
    );
  });

  test('mimetype 内容错误时校验失败', () {
    final archive = Archive()
      ..addFile(
        ArchiveFile('mimetype', 20, utf8.encode('text/plain'))
          ..compression = CompressionType.none,
      );
    final report = EpubArchive.fromBytes(
      Uint8List.fromList(ZipEncoder().encode(archive)),
    ).validateOcf();
    expect(report.ok, isFalse);
    expect(report.errors.first, contains('内容错误'));
  });

  test('mimetype 不在首位时报错', () {
    final archive = Archive()
      ..addFile(ArchiveFile('a.txt', 1, <int>[65]))
      ..addFile(
        ArchiveFile('mimetype', 20, utf8.encode('application/epub+zip'))
          ..compression = CompressionType.none,
      );
    final report = EpubArchive.fromBytes(
      Uint8List.fromList(ZipEncoder().encode(archive)),
    ).validateOcf();
    expect(report.ok, isFalse);
    expect(report.errors.first, contains('不是第一个条目'));
  });
}

int _indexOf(List<int> haystack, List<int> needle) {
  outer:
  for (var i = 0; i <= haystack.length - needle.length; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) {
        continue outer;
      }
    }
    return i;
  }
  return -1;
}
