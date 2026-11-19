import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import 'epub_image_helper.dart';

class ImgCompressOperation {
  ImgCompressOperation._();

  static Future<String> execute({
    required String epubPath,
    required String outputPath,
    int jpegQuality = 85,
    bool pngToJpg = true,
  }) async {
    RangeError.checkValueInInterval(jpegQuality, 1, 100, 'jpegQuality');
    final archive = await EpubImageHelper.readArchive(epubPath);
    final result = _compressImages(archive, jpegQuality, pngToJpg);
    await EpubImageHelper.saveArchive(
      archive,
      outputPath,
      renameMap: result.renameMap,
    );
    return '${result.log}输出文件: $outputPath\n';
  }

  static ({Map<String, String> renameMap, String log}) _compressImages(
    Archive archive,
    int jpegQuality,
    bool pngToJpg,
  ) {
    final images = EpubImageHelper.findImages(
      archive,
      EpubImageHelper.compressExts,
    );
    final log = StringBuffer()..writeln('找到 ${images.length} 张图片，开始压缩...');
    final renameMap = <String, String>{};
    var processed = 0;
    var skipped = 0;
    var errors = 0;
    var saved = 0;
    for (final file in images) {
      try {
        final result = _compressImage(archive, file, jpegQuality, pngToJpg);
        log.writeln('  ${result.message}');
        if (result.saved == 0) {
          skipped++;
          continue;
        }
        processed++;
        saved += result.saved;
        if (result.newName != file.name) renameMap[file.name] = result.newName;
      } catch (error) {
        errors++;
        log.writeln('  错误: ${file.name} - $error');
      }
    }
    log.writeln('\n压缩完成: 处理 $processed 张, 跳过 $skipped 张, 错误 $errors 张');
    log.writeln('总计节省: ${EpubImageHelper.sizeStr(saved)}');
    return (renameMap: renameMap, log: log.toString());
  }

  static ({String newName, int saved, String message}) _compressImage(
    Archive archive,
    ArchiveFile file,
    int quality,
    bool pngToJpg,
  ) {
    final original = EpubImageHelper.readBytes(file);
    final extension = p.posix.extension(file.name).toLowerCase();
    if (extension == '.gif' || extension == '.webp') {
      return (newName: file.name, saved: 0, message: '跳过: ${file.name} (保留原图)');
    }
    final image = img.decodeImage(original);
    if (image == null) throw const FormatException('图片解码失败');
    if (image.numFrames > 1) {
      return (newName: file.name, saved: 0, message: '跳过: ${file.name} (保留动图)');
    }
    final result = _encodeImage(image, extension, quality, pngToJpg);
    final saved = original.length - result.data.length;
    final newName = '${p.posix.withoutExtension(file.name)}${result.extension}';
    if (saved <= 0 ||
        (newName != file.name && archive.findFile(newName) != null)) {
      return (
        newName: file.name,
        saved: 0,
        message: '跳过: ${file.name} (体积未减小或目标文件已存在)',
      );
    }
    EpubImageHelper.replaceFile(archive, file.name, newName, result.data);
    return (
      newName: newName,
      saved: saved,
      message:
          '${file.name}: ${EpubImageHelper.sizeStr(original.length)} → '
          '${EpubImageHelper.sizeStr(result.data.length)}',
    );
  }

  static ({Uint8List data, String extension}) _encodeImage(
    img.Image image,
    String extension,
    int quality,
    bool pngToJpg,
  ) {
    final hasTransparency = image.any((pixel) => pixel.aNormalized < 1);
    final useJpeg =
        extension == '.jpg' ||
        extension == '.jpeg' ||
        (!hasTransparency &&
            (extension == '.bmp' || (extension == '.png' && pngToJpg)));
    return useJpeg
        ? (data: img.encodeJpg(image, quality: quality), extension: '.jpg')
        : (data: img.encodePng(image, level: 9), extension: '.png');
  }
}
