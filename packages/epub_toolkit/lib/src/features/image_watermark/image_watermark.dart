import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../../core/epub_image_helper.dart';

class ImageWatermarkOperation {
  ImageWatermarkOperation._();

  static const _magic = [0x45, 0x50, 0x55, 0x42, 0x57, 0x4d, 0x31, 0x00];
  static const _headerLength = 16;
  static const _supportedExts = [
    '.jpg',
    '.jpeg',
    '.png',
    '.bmp',
    '.webp',
    '.gif',
  ];

  static Future<String> embed({
    required String epubPath,
    required String outputPath,
    required String watermarkText,
  }) async {
    final text = watermarkText.trim();
    if (text.isEmpty) {
      throw ArgumentError.value(watermarkText, 'watermarkText', '水印文本不能为空');
    }
    final payload = _buildPayload(text);
    final archive = await EpubImageHelper.readArchive(epubPath);
    final log = StringBuffer();
    final renameMap = <String, String>{};
    final images = EpubImageHelper.findImages(archive, _supportedExts);
    var embedded = 0;
    for (final file in images) {
      try {
        if (!_embedImage(archive, file, payload, log)) continue;
        embedded++;
        final newName = '${p.posix.withoutExtension(file.name)}.png';
        if (newName != file.name) renameMap[file.name] = newName;
      } catch (error) {
        log.writeln('  错误: ${file.name} - $error');
      }
    }
    if (embedded == 0) return '$log\n未能写入任何图片，未生成输出文件。';
    await EpubImageHelper.saveArchive(
      archive,
      outputPath,
      renameMap: renameMap,
    );
    log.writeln('\n写入完成: 写入 $embedded 张');
    log.writeln('输出文件: $outputPath');
    return log.toString();
  }

  static Uint8List _buildPayload(String text) {
    final textBytes = utf8.encode(text);
    final header = ByteData(_headerLength)
      ..setUint32(8, textBytes.length)
      ..setUint32(12, getCrc32(textBytes));
    return Uint8List.fromList([
      ..._magic,
      ...header.buffer.asUint8List(8),
      ...textBytes,
    ]);
  }

  static bool _embedImage(
    Archive archive,
    ArchiveFile file,
    Uint8List payload,
    StringBuffer log,
  ) {
    final decoded = img.decodeImage(EpubImageHelper.readBytes(file));
    if (decoded == null) throw const FormatException('图片解码失败');
    if (decoded.numFrames > 1 || _capacityBytes(decoded) < payload.length) {
      log.writeln('  跳过: ${file.name} (动图或水印容量不足)');
      return false;
    }
    final newName = '${p.posix.withoutExtension(file.name)}.png';
    if (newName != file.name && archive.findFile(newName) != null) {
      throw StateError('目标文件已存在: $newName');
    }
    final image = decoded.convert(numChannels: 4);
    _embedPayload(image, payload);
    EpubImageHelper.replaceFile(
      archive,
      file.name,
      newName,
      img.encodePng(image, level: 1),
    );
    log.writeln('  写入: ${file.name} → $newName');
    return true;
  }

  static void _embedPayload(img.Image image, Uint8List payload) {
    var bitIndex = 0;
    for (final pixel in image) {
      for (
        var channel = 0;
        channel < 3 && bitIndex < payload.length * 8;
        channel++
      ) {
        final bit = (payload[bitIndex ~/ 8] >> (7 - bitIndex % 8)) & 1;
        pixel[channel] = (pixel[channel].toInt() & ~1) | bit;
        bitIndex++;
      }
      if (bitIndex == payload.length * 8) break;
    }
  }

  static Future<String> inspect({required String epubPath}) async {
    final archive = await EpubImageHelper.readArchive(epubPath);
    final images = EpubImageHelper.findImages(archive, _supportedExts);
    final log = StringBuffer()..writeln('找到 ${images.length} 张图片，开始读取隐形水印...');
    var found = 0;
    var errors = 0;
    for (final file in images) {
      try {
        final image = img.decodeImage(EpubImageHelper.readBytes(file));
        if (image == null) throw const FormatException('图片解码失败');
        final text = _extractText(image);
        if (text == null) continue;
        found++;
        log.writeln('  ${file.name}: $text');
      } catch (error) {
        errors++;
        log.writeln('  错误: ${file.name} - $error');
      }
    }
    log.writeln('\n读取完成: 找到 $found 张, 错误 $errors 张');
    if (found == 0) log.writeln('未在 EPUB 图片中发现本工具写入的水印信息。');
    return log.toString();
  }

  static String? _extractText(img.Image image) {
    if (_capacityBytes(image) < _headerLength) return null;
    final reader = _LsbReader(image);
    final header = reader.readBytes(_headerLength);
    if (header == null) return null;
    for (var index = 0; index < _magic.length; index++) {
      if (header[index] != _magic[index]) return null;
    }
    final fields = ByteData.sublistView(header);
    final length = fields.getUint32(8);
    if (length > _capacityBytes(image) - _headerLength) return null;
    final payload = reader.readBytes(length);
    if (payload == null || getCrc32(payload) != fields.getUint32(12)) {
      return null;
    }
    return utf8.decode(payload);
  }

  static int _capacityBytes(img.Image image) =>
      (image.width * image.height * 3) ~/ 8;
}

class _LsbReader {
  _LsbReader(this.image);

  final img.Image image;
  var _bitIndex = 0;

  Uint8List? readBytes(int count) {
    final bytes = Uint8List(count);
    for (var index = 0; index < count; index++) {
      for (var bit = 0; bit < 8; bit++) {
        final pixelIndex = _bitIndex ~/ 3;
        if (pixelIndex >= image.width * image.height) return null;
        final pixel = image.getPixel(
          pixelIndex % image.width,
          pixelIndex ~/ image.width,
        );
        bytes[index] = (bytes[index] << 1) | (pixel[_bitIndex % 3].toInt() & 1);
        _bitIndex++;
      }
    }
    return bytes;
  }
}
