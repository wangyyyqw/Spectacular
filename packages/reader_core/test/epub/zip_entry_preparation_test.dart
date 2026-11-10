import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/epub/archive_reader.dart';
import 'package:reader_core/epub/zip_source.dart';

const _path = 'Text/chapter.xhtml';

void main() {
  for (final compression in [CompressionType.none, CompressionType.deflate]) {
    test('$compression 异步文件读取与同步探测交错时不共享游标', () async {
      final data = utf8.encode('图片字节与同步读取保持一致' * 10000);
      final file = await _tempFile(_zip(data, compression));
      final archive = await EpubArchive.fromFile(file);
      addTearDown(archive.close);
      final first = archive.prepareEntryAsync('/Text\\chapter.xhtml');
      final second = archive.prepareEntryAsync(_path);
      expect(archive.readHead(_path, 32), data.take(32));
      expect(archive.readBytes(_path), data);
      for (final pending in [first, second]) {
        final read = (await pending)!;
        final payload = read.payload;
        final result = await Isolate.run(() => decodeEpubEntry(payload));
        expect(result.bytes, data);
        expect(archive.commitEntry(read, result.error), isTrue);
      }
      expect(await archive.prepareEntryAsync('missing'), isNull);
    });

    test('$compression 文件与内存准备结果独立，纯 payload 可跨 isolate', () async {
      final data = utf8.encode('<p>解压结果与原文保持一致。</p>' * 10000);
      final zip = _zip(data, compression);
      final file = await _tempFile(zip);
      final archives = [
        EpubArchive.fromBytes(zip, verify: false),
        await EpubArchive.fromFile(file),
      ];
      for (final archive in archives) {
        addTearDown(archive.close);
        final read = archive.prepareEntry('/Text\\chapter.xhtml')!;
        final payload = read.payload;
        final result = await Isolate.run(() => decodeEpubEntry(payload));
        expect(result.error, isNull);
        expect(result.bytes, data);
        expect(archive.commitEntry(read, result.error), isTrue);
        result.bytes!.fillRange(0, result.bytes!.length, 0);
        expect(archive.readBytes(_path), data);
      }
    });
  }

  test('异步读取未完成时关闭归档，晚到输入不可提交', () async {
    final file = await _tempFile(
      _zip(Uint8List(4 * 1024 * 1024), CompressionType.none),
    );
    final archive = await EpubArchive.fromFile(file);
    final pending = archive.prepareEntryAsync(_path);
    archive.close();
    expect(await pending, isNull);
    expect(await archive.prepareEntryAsync(_path), isNull);
    expect(archive.diagnostics, isEmpty);
  });

  test('异步读取保留坏压缩条目的提交淘汰及内存旧后端兼容', () async {
    final zip = _zip(utf8.encode('损坏图片' * 100), CompressionType.deflate);
    zip[_contentStart(zip)] = 0x07;
    final archive = await EpubArchive.fromFile(await _tempFile(zip));
    addTearDown(archive.close);
    final read = (await archive.prepareEntryAsync(_path))!;
    final result = decodeEpubEntry(read.payload);
    expect(result.bytes, isNull);
    expect(archive.contains(_path), isTrue);
    expect(archive.commitEntry(read, result.error), isTrue);
    expect(archive.contains(_path), isFalse);
    for (final compression in [
      CompressionType.deflate,
      CompressionType.bzip2,
    ]) {
      final memory = EpubArchive.fromBytes(
        _zip(utf8.encode('兼容图片'), compression),
        verify: false,
      );
      addTearDown(memory.close);
      final prepared = (await memory.prepareEntryAsync(_path))!;
      expect(utf8.decode(decodeEpubEntry(prepared.payload).bytes!), '兼容图片');
      expect(memory.commitEntry(prepared, null), isTrue);
    }
  });

  test('关闭和另一归档拒绝提交，关闭后独立 payload 仍可解码', () {
    final zip = _zip(utf8.encode('正文'), CompressionType.deflate);
    final first = EpubArchive.fromBytes(zip, verify: false);
    final second = EpubArchive.fromBytes(zip, verify: false);
    addTearDown(first.close);
    addTearDown(second.close);
    final read = first.prepareEntry(_path)!;
    expect(second.commitEntry(read, null), isFalse);
    first.close();
    final result = decodeEpubEntry(read.payload);
    expect(utf8.decode(result.bytes!), '正文');
    expect(first.commitEntry(read, result.error), isFalse);
    expect(first.prepareEntry(_path), isNull);
    expect(first.length, 0);
    expect(second.contains(_path), isTrue);
  });

  test('坏压缩流仅在宿主提交时剔除，旧凭据不能重复提交', () {
    final zip = _zip(utf8.encode('正文' * 100), CompressionType.deflate);
    zip[_contentStart(zip)] = 0x07;
    final archive = EpubArchive.fromBytes(zip, verify: false);
    addTearDown(archive.close);
    final read = archive.prepareEntry(_path)!;
    final result = decodeEpubEntry(read.payload);
    expect(result.bytes, isNull);
    expect(result.error, contains('解压失败'));
    expect(archive.contains(_path), isTrue);
    expect(archive.commitEntry(read, result.error), isTrue);
    expect(archive.contains(_path), isFalse);
    expect(archive.length, 0);
    expect(archive.commitEntry(read, result.error), isFalse);
  });

  test('同步与纯数据解码保持 CRC 开关、零 CRC 及 deflate 尺寸错误语义', () {
    for (final method in [CompressionType.none, CompressionType.deflate]) {
      for (final verify in [true, false]) {
        final zip = _zip(utf8.encode('CRC 与尺寸' * 100), method);
        final central = _central(zip);
        final bytes = ByteData.sublistView(zip);
        bytes.setUint32(central + 16, 1, Endian.little);
        _expectEquivalent(zip, verify: verify, succeeds: !verify);
        bytes.setUint32(central + 16, 0, Endian.little);
        _expectEquivalent(zip, verify: verify, succeeds: true);
        final size = bytes.getUint32(central + 24, Endian.little);
        for (final delta in [-1, 1]) {
          bytes.setUint32(central + 24, size + delta, Endian.little);
          _expectEquivalent(
            zip,
            verify: verify,
            succeeds: method == CompressionType.none,
          );
        }
      }
    }
  });

  test('文件后端修复局部头后准备条目，损坏头和截断读取不留下可提交输入', () async {
    final zip = _zip(utf8.encode('修复原文'), CompressionType.deflate);
    ByteData.sublistView(zip).setUint32(_central(zip) + 42, 3, Endian.little);
    final file = await _tempFile(zip);
    final archive = await EpubArchive.fromFile(file);
    addTearDown(archive.close);
    final read = archive.prepareEntry(_path)!;
    expect(utf8.decode(decodeEpubEntry(read.payload).bytes!), '修复原文');
    expect(archive.commitEntry(read, null), isTrue);
    expect(archive.readString(_path), '修复原文');
    await file.writeAsBytes(const []);
    expect(archive.prepareEntry(_path), isNull);
    expect(archive.contains(_path), isFalse);
    expect(archive.commitEntry(read, null), isFalse);
  });

  test('局部头修复诊断只记一次，无法修复与截断的同步状态等价', () {
    final shifted = _zip(utf8.encode('修复'), CompressionType.deflate);
    ByteData.sublistView(shifted)
        .setUint32(_central(shifted) + 42, 3, Endian.little);
    final index = _index(shifted);
    addTearDown(index.release);
    expect(index.prepareEntry(_path), isNotNull);
    expect(index.prepareEntry(_path), isNotNull);
    expect(
      index.diagnostics.where((item) => item.startsWith('E_ZIP_LOCAL_HEADER')),
      hasLength(1),
    );
    final invalid = Uint8List.fromList(shifted)..[0] = 0;
    _expectPreparationFailure(invalid);
    final truncated = _zip(utf8.encode('截断'), CompressionType.deflate);
    ByteData.sublistView(
      truncated,
    ).setUint32(_central(truncated) + 20, truncated.length * 2, Endian.little);
    _expectPreparationFailure(truncated);
  });

  test('旧 bzip2 后端保持兼容和关闭凭据语义', () {
    final text = utf8.encode('旧后端正文' * 100);
    final archive = EpubArchive.fromBytes(
      _zip(text, CompressionType.bzip2),
      verify: false,
    );
    addTearDown(archive.close);
    final read = archive.prepareEntry(_path)!;
    expect(decodeEpubEntry(read.payload).bytes, text);
    expect(archive.commitEntry(read, null), isTrue);
    expect(archive.readHead(_path, 10), text.take(10));
    archive.close();
    expect(archive.commitEntry(read, null), isFalse);
  });

  test('同步 deflate 保持 64KiB 分块，前缀读取不受完整解码失败影响', () {
    var state = 7;
    final data = Uint8List.fromList(
      List.generate(300000, (_) {
        state ^= state << 13;
        state ^= state >> 17;
        state ^= state << 5;
        return state & 0xff;
      }),
    );
    final zip = _zip(data, CompressionType.deflate);
    final source = _ObservedSource(zip);
    final index = ZipIndex.tryParse(source, validateHeaders: false)!;
    addTearDown(index.release);
    source.largestRead = 0;
    expect(index.readBytes(_path), data);
    expect(source.largestRead, lessThanOrEqualTo(64 * 1024));
    final central = _central(zip);
    ByteData.sublistView(zip)
        .setUint32(central + 24, data.length + 1, Endian.little);
    final damaged = _index(zip);
    addTearDown(damaged.release);
    expect(damaged.readHead(_path, 16), data.take(16));
    final prepared = damaged.prepareEntry(_path)!;
    expect(decodeEpubEntry(prepared.payload).error, isNotNull);
    expect(damaged.contains(_path), isTrue);
    expect(damaged.readHead(_path, 16), data.take(16));
  });
}

void _expectEquivalent(
  Uint8List zip, {
  required bool verify,
  required bool succeeds,
}) {
  final sync = _index(zip, verify: verify);
  final async = _index(zip, verify: verify);
  addTearDown(sync.release);
  addTearDown(async.release);
  final expected = sync.readBytes(_path);
  final prepared = async.prepareEntry(_path)!;
  final result = decodeEpubEntry(prepared.payload);
  expect(result.bytes, expected);
  expect(result.bytes != null, succeeds);
  expect(async.commitEntry(prepared.entry, result.error), isTrue);
  expect(async.diagnostics, sync.diagnostics);
  expect(async.contains(_path), sync.contains(_path));
}

void _expectPreparationFailure(Uint8List zip) {
  final sync = _index(zip);
  final prepared = _index(zip);
  addTearDown(sync.release);
  addTearDown(prepared.release);
  expect(sync.readBytes(_path), isNull);
  expect(prepared.prepareEntry(_path), isNull);
  expect(prepared.diagnostics, sync.diagnostics);
  expect(prepared.contains(_path), isFalse);
}

ZipIndex _index(Uint8List zip, {bool verify = false}) => ZipIndex.tryParse(
  ZipByteSource.fromBytes(zip),
  validateHeaders: false,
  verifyCrc: verify,
)!;

Uint8List _zip(List<int> data, CompressionType compression) =>
    Uint8List.fromList(
      ZipEncoder().encode(
        Archive()..addFile(
          ArchiveFile(_path, data.length, data)..compression = compression,
        ),
      ),
    );

int _contentStart(Uint8List zip) {
  final bytes = ByteData.sublistView(zip);
  return 30 +
      bytes.getUint16(26, Endian.little) +
      bytes.getUint16(28, Endian.little);
}

int _central(Uint8List zip) {
  final data = ByteData.sublistView(zip);
  for (var offset = zip.length - 22; offset >= 0; offset--) {
    if (data.getUint32(offset, Endian.little) == 0x06054b50) {
      return data.getUint32(offset + 16, Endian.little);
    }
  }
  throw StateError('测试 ZIP 缺少中央目录');
}

Future<File> _tempFile(Uint8List zip) async {
  final directory = await Directory.systemTemp.createTemp('epub-entry-');
  addTearDown(() => directory.delete(recursive: true));
  return File('${directory.path}/book.epub').writeAsBytes(zip);
}

class _ObservedSource implements ZipByteSource {
  _ObservedSource(this.bytes);
  final Uint8List bytes;
  int largestRead = 0;
  @override
  int get length => bytes.length;
  @override
  bool get rangesAreIndependent => false;
  @override
  Uint8List readRange(int offset, int count) {
    if (count > largestRead) largestRead = count;
    return Uint8List.sublistView(
      bytes,
      offset,
      (offset + count).clamp(0, length),
    );
  }

  @override
  Future<void> close() async {}
  @override
  void closeSync() {}
}
