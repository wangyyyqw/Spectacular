import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/epub/archive_reader.dart';
import 'package:reader_core/epub/epub_document.dart';
import 'package:reader_core/epub/epub_exception.dart';

import '../support/broken_samples.dart';
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

  test('关闭归档后释放全部条目且不可再读取', () {
    final archive = EpubArchive.fromBytes(_twoEntryZip(), verify: false);
    expect(archive.length, 2);
    expect(archive.readString('good.txt'), 'good content payload here');
    expect(archive.names, isNotEmpty);

    archive.close();

    expect(archive.length, 0);
    expect(archive.names, isEmpty);
    expect(archive.contains('good.txt'), isFalse);
    expect(archive.readBytes('good.txt'), isNull);
    archive.close();
  });

  test('全部条目损坏：截断档拒绝（P7-15）', () {
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
          'E_ZIP_ENTRY_TRUNCATED',
        ),
      ),
    );
  });

  test('部分条目损坏：跳过坏条目恢复并记诊断（P7-15）', () {
    final zip = _twoEntryZip();
    // 翻转第二个条目（bad.txt）的内容字节。
    final bad = utf8.encode('bad content payload here');
    final index = _indexOf(zip, bad);
    expect(index, greaterThan(0));
    zip[index] ^= 0xFF;

    final archive = EpubArchive.fromBytes(zip);
    expect(archive.contains('good.txt'), isTrue);
    expect(archive.contains('bad.txt'), isFalse, reason: '坏条目被跳过');
    expect(
      archive.diagnostics.any((d) => d.startsWith('E_ZIP_ENTRY_TRUNCATED')),
      isTrue,
    );
    expect(archive.diagnostics.any((d) => d.contains('bad.txt')), isTrue);
  });

  test('压缩流解压失败只跳过坏条目，未引用资源不阻止 EPUB 打开', () async {
    final files = ZipDecoder().decodeBytes(
      brokenSamples['A-refs-repair.epub']!,
    );
    files.addFile(ArchiveFile.string('unused.bin', 'deflate content ' * 1000));
    final zip = _breakDeflate(Uint8List.fromList(ZipEncoder().encode(files)));

    final result = await openEpub(zip);

    expect(result.ok, isTrue, reason: result.report.message);
    final archive = result.document!.archive;
    addTearDown(archive.close);
    expect(archive.readString('OEBPS/c1.xhtml'), contains('正文内容'));
    expect(archive.contains('unused.bin'), isFalse);
    expect(result.report.warnings, contains(contains('unused.bin')));
    expect(result.report.warnings, contains(contains('E_ZIP_ENTRY_TRUNCATED')));
  });

  test('全部压缩流解压失败仍按条目截断分类拒绝', () {
    final files = Archive()
      ..addFile(ArchiveFile.string('unused.bin', 'deflate content ' * 1000));
    final zip = _breakDeflate(Uint8List.fromList(ZipEncoder().encode(files)));
    expect(
      () => EpubArchive.fromBytes(zip),
      throwsA(
        isA<EpubException>().having(
          (error) => error.code,
          'code',
          'E_ZIP_ENTRY_TRUNCATED',
        ),
      ),
    );
  });

  test('显式关闭 CRC 时保留条目，默认仍过滤损坏内容', () {
    final zip = _twoEntryZip();
    final index = _indexOf(zip, utf8.encode('bad content payload here'));
    zip[index] ^= 0xFF;

    final quick = EpubArchive.fromBytes(zip, verify: false);
    expect(quick.contains('bad.txt'), isTrue);
    expect(quick.readBytes('bad.txt')!.first, zip[index]);
    expect(quick.diagnostics, isEmpty);
    expect(EpubArchive.fromBytes(zip).contains('bad.txt'), isFalse);
  });

  test('局部头修补后仍遵守显式关闭 CRC', () {
    final zip = _twoEntryZip();
    zip[_indexOf(zip, utf8.encode('bad content payload here'))] ^= 0xFF;
    final patched = _shiftCentralOffset(zip, 'bad.txt', 3)!;
    final archive = EpubArchive.fromBytes(patched, verify: false);
    expect(archive.contains('bad.txt'), isTrue);
    expect(archive.diagnostics, contains(startsWith('E_ZIP_LOCAL_HEADER')));
    expect(
      archive.diagnostics,
      isNot(contains(startsWith('E_ZIP_ENTRY_TRUNCATED'))),
    );
  });

  test('含目录条目无需修补，文本读取与字节副本保持隔离', () {
    final zip = Archive()
      ..addFile(ArchiveFile.directory('text/'))
      ..addFile(ArchiveFile.string('text/chapter.xhtml', '正文'));
    final archive = EpubArchive.fromBytes(
      Uint8List.fromList(ZipEncoder().encode(zip)),
      verify: false,
    );
    expect(archive.names, ['text/chapter.xhtml']);
    expect(archive.diagnostics, isEmpty);
    final bytes = archive.readBytes('text/chapter.xhtml')!;
    bytes.fillRange(0, bytes.length, 0);
    expect(archive.readString('text/chapter.xhtml'), '正文');
    expect(archive.readString('missing'), isNull);
  });

  test('非 UTF-8 文件名按中央目录原始字节定位局部头', () {
    final archive = Archive()
      ..addFile(
        ArchiveFile.string('a.txt', 'GBK 文件名内容')
          ..compression = CompressionType.none,
      );
    final zip = Uint8List.fromList(ZipEncoder().encode(archive));
    final localName = _localHeaderNameOffset(zip);
    final centralName = _centralHeaderNameOffset(zip, 'a.txt');
    expect(localName, isNotNull);
    expect(centralName, isNotNull);
    zip[localName!] = 0xB1;
    zip[centralName!] = 0xB1;

    final decoded = EpubArchive.fromBytes(zip, verify: false);
    final name = decoded.names.single;
    expect(name, isNot('a.txt'));
    expect(decoded.readString(name), 'GBK 文件名内容');
  });

  test('局部头偏移错位：扫描修补后恢复（P7-15）', () {
    final zip = _twoEntryZip();
    // 把中心目录里 bad.txt 的局部头偏移改错 3 字节。
    final patched = _shiftCentralOffset(zip, 'bad.txt', 3);
    expect(patched, isNotNull);
    final archive = EpubArchive.fromBytes(patched!);
    expect(archive.contains('good.txt'), isTrue);
    expect(archive.readString('bad.txt'), isNotNull, reason: '修补后条目可读');
    expect(
      archive.diagnostics.any((d) => d.startsWith('E_ZIP_LOCAL_HEADER')),
      isTrue,
    );
  });

  test('EOCD 缺失：不可恢复档拒绝（P7-15）', () {
    final zip = _twoEntryZip();
    final cut = Uint8List.sublistView(zip, 0, zip.length - 24);
    expect(
      () => EpubArchive.fromBytes(cut),
      throwsA(
        isA<EpubException>().having(
          (e) => e.code,
          'code',
          anyOf('E_ZIP_EOCD_MISSING', 'E_ARCHIVE'),
        ),
      ),
    );
  });

  test('非 ZIP 字节按档拒绝', () {
    final garbage = Uint8List.fromList(List<int>.generate(128, (i) => i));
    expect(() => EpubArchive.fromBytes(garbage), throwsA(isA<EpubException>()));
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

  test('文件后端按需读取，关闭后释放句柄', () async {
    final directory = await Directory.systemTemp.createTemp('epub-file-');
    addTearDown(() async {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });
    final file = File('${directory.path}/book.epub');
    await file.writeAsBytes(_twoEntryZip());

    final archive = await EpubArchive.fromFile(file);
    expect(archive.length, 2);
    expect(archive.readString('good.txt'), 'good content payload here');
    final bytes = archive.readBytes('good.txt')!;
    bytes.fillRange(0, bytes.length, 0);
    expect(
      archive.readString('good.txt'),
      'good content payload here',
      reason: '每次读取都返回独立副本',
    );

    archive.close();
    expect(archive.length, 0);
    expect(archive.readString('good.txt'), isNull);
  });

  test('文件后端读取 deflate 章节与目录', () async {
    final corpus = findCorpusRoot();
    if (corpus == null) {
      return;
    }
    final source = readSampleBytes(corpus, 'basic.epub');
    if (source == null) {
      return;
    }
    final directory = await Directory.systemTemp.createTemp('epub-file-');
    addTearDown(() async {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });
    final file = File('${directory.path}/basic.epub');
    await file.writeAsBytes(source);

    final archive = await EpubArchive.fromFile(file);
    expect(archive.validateOcf().ok, isTrue);
    expect(archive.contains('META-INF/container.xml'), isTrue);
    expect(archive.readString('META-INF/container.xml'), contains('rootfile'));
    archive.close();
  });

  test('readHead 只返回 store/deflate 条目前缀且不污染完整读取', () async {
    final payload = Uint8List.fromList(
      List<int>.generate(300000, (index) => index & 0xFF),
    );
    final files = Archive()
      ..addFile(
        ArchiveFile('stored.bin', payload.length, payload)
          ..compression = CompressionType.none,
      )
      ..addFile(
        ArchiveFile('deflated.bin', payload.length, payload)
          ..compression = CompressionType.deflate,
      );
    final archive = EpubArchive.fromBytes(
      Uint8List.fromList(ZipEncoder().encode(files)),
      verify: false,
    );
    addTearDown(archive.close);

    final head = archive.readHead('deflated.bin', 64)!;
    expect(head, payload.sublist(0, 64));
    head.fillRange(0, head.length, 0);
    expect(archive.readHead('deflated.bin', 64), payload.sublist(0, 64));
    expect(archive.readHead('stored.bin', 64), payload.sublist(0, 64));
    expect(archive.readHead('missing.bin', 64), isNull);
    expect(archive.readHead('deflated.bin', 0), isEmpty);
    expect(archive.readBytes('deflated.bin'), payload);
    expect(archive.readBytes('stored.bin'), payload);
  });

  test('文件后端 readHead 按需解压文件头', () async {
    final payload = Uint8List.fromList(
      List<int>.generate(180000, (index) => 255 - (index & 0xFF)),
    );
    final files = Archive()
      ..addFile(
        ArchiveFile('image.jpg', payload.length, payload)
          ..compression = CompressionType.deflate,
      );
    final directory = await Directory.systemTemp.createTemp('epub-head-');
    addTearDown(() async {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });
    final file = File('${directory.path}/book.epub');
    await file.writeAsBytes(ZipEncoder().encode(files));

    final archive = await EpubArchive.fromFile(file);
    addTearDown(archive.close);
    expect(archive.readHead('image.jpg', 32), payload.sublist(0, 32));
    expect(archive.readBytes('image.jpg'), payload);
  });

  test('大 stored 条目导入时仍完整校验 CRC', () {
    final content = Uint8List(2 * 1024 * 1024);
    for (var i = 0; i < content.length; i++) {
      content[i] = i & 0xFF;
    }
    final archive = Archive()
      ..addFile(
        ArchiveFile('large.bin', content.length, content)
          ..compression = CompressionType.none,
      )
      ..addFile(
        ArchiveFile.string('good.txt', 'ok')
          ..compression = CompressionType.none,
      );
    final zip = Uint8List.fromList(ZipEncoder().encode(archive));
    final offset = _indexOf(zip, content);
    expect(offset, greaterThan(0));
    zip[offset + content.length ~/ 2] ^= 0xFF;

    final decoded = EpubArchive.fromBytes(zip);
    expect(decoded.contains('large.bin'), isFalse);
    expect(decoded.contains('good.txt'), isTrue);
    expect(
      decoded.diagnostics,
      contains(contains('large.bin')),
      reason: '大条目不能因跳过解压而漏掉 CRC 校验',
    );
  });

  test('大 deflate 条目导入时按流式解压校验 CRC', () {
    final content = utf8.encode('流式解压校验。' * 180000);
    final archive = Archive()
      ..addFile(
        ArchiveFile('large.xhtml', content.length, content)
          ..compression = CompressionType.deflate,
      )
      ..addFile(
        ArchiveFile.string('good.txt', 'ok')
          ..compression = CompressionType.none,
      );
    final zip = Uint8List.fromList(ZipEncoder().encode(archive));
    final header = _centralHeaderOffset(zip, 'large.xhtml');
    expect(header, isNotNull);
    final data = ByteData.sublistView(zip);
    final wrongCrc = data.getUint32(header! + 16, Endian.little) ^ 1;
    data.setUint32(header + 16, wrongCrc, Endian.little);

    final decoded = EpubArchive.fromBytes(zip);
    expect(decoded.contains('large.xhtml'), isFalse);
    expect(decoded.contains('good.txt'), isTrue);
    expect(decoded.diagnostics, contains(contains('large.xhtml')));
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

/// 把指定 deflate 流的首块设为保留类型，确保失败发生在解压而非 CRC 比较。
Uint8List _breakDeflate(Uint8List zip) {
  final data = ByteData.sublistView(zip);
  for (var offset = 0; offset < zip.length - 30; offset++) {
    if (data.getUint32(offset, Endian.little) != 0x04034b50) {
      continue;
    }
    final nameLength = data.getUint16(offset + 26, Endian.little);
    final name = utf8.decode(
      zip.sublist(offset + 30, offset + 30 + nameLength),
    );
    if (name != 'unused.bin') {
      continue;
    }
    expect(data.getUint16(offset + 8, Endian.little), 8);
    final extraLength = data.getUint16(offset + 28, Endian.little);
    zip[offset + 30 + nameLength + extraLength] = 0x07;
    return zip;
  }
  throw StateError('缺少待损坏的压缩条目');
}

/// 两个 store 条目的最小 ZIP（字节可控，便于故障注入，P7-15）。
Uint8List _twoEntryZip() {
  final good = utf8.encode('good content payload here');
  final bad = utf8.encode('bad content payload here');
  final archive = Archive()
    ..addFile(
      ArchiveFile('good.txt', good.length, good)
        ..compression = CompressionType.none,
    )
    ..addFile(
      ArchiveFile('bad.txt', bad.length, bad)
        ..compression = CompressionType.none,
    );
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

/// 把中心目录中 [name] 条目的局部头偏移偏移 [delta] 字节（P7-15）。
Uint8List? _shiftCentralOffset(Uint8List zip, String name, int delta) {
  final data = ByteData.sublistView(zip);
  var eocd = -1;
  for (var i = zip.length - 22; i >= 0; i--) {
    if (data.getUint32(i, Endian.little) == 0x06054b50) {
      eocd = i;
      break;
    }
  }
  if (eocd < 0) {
    return null;
  }
  var cursor = data.getUint32(eocd + 16, Endian.little);
  for (var i = 0; i < data.getUint16(eocd + 10, Endian.little); i++) {
    final nameLength = data.getUint16(cursor + 28, Endian.little);
    final extraLength = data.getUint16(cursor + 30, Endian.little);
    final commentLength = data.getUint16(cursor + 32, Endian.little);
    final entryName = utf8.decode(
      zip.sublist(cursor + 46, cursor + 46 + nameLength),
    );
    if (entryName == name) {
      final out = Uint8List.fromList(zip);
      ByteData.sublistView(out).setUint32(
        cursor + 42,
        data.getUint32(cursor + 42, Endian.little) + delta,
        Endian.little,
      );
      return out;
    }
    cursor += 46 + nameLength + extraLength + commentLength;
  }
  return null;
}

int? _localHeaderNameOffset(Uint8List zip) {
  final data = ByteData.sublistView(zip);
  for (var offset = 0; offset + 30 <= zip.length; offset++) {
    if (data.getUint32(offset, Endian.little) == 0x04034b50) {
      return offset + 30;
    }
  }
  return null;
}

int? _centralHeaderNameOffset(Uint8List zip, String name) {
  final offset = _centralHeaderOffset(zip, name);
  return offset == null ? null : offset + 46;
}

int? _centralHeaderOffset(Uint8List zip, String name) {
  final data = ByteData.sublistView(zip);
  for (var offset = 0; offset + 46 <= zip.length; offset++) {
    if (data.getUint32(offset, Endian.little) != 0x02014b50) {
      continue;
    }
    final length = data.getUint16(offset + 28, Endian.little);
    final start = offset + 46;
    if (start + length > zip.length) return null;
    if (utf8.decode(zip.sublist(start, start + length)) == name) {
      return offset;
    }
  }
  return null;
}
