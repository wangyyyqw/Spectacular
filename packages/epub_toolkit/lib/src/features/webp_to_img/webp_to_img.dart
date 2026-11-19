import 'package:archive/archive.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import 'epub_image_helper.dart';

class WebpToImgOperation {
  WebpToImgOperation._();

  static Future<String> execute({
    required String epubPath,
    required String outputPath,
  }) async {
    final archive = await EpubImageHelper.readArchive(epubPath);
    final images = EpubImageHelper.findImages(archive, const ['.webp']);
    if (images.isEmpty) return '未找到 WebP 图片，无需转换。';
    final result = _convertImages(archive, images);
    if (result.renameMap.isEmpty) {
      return '${result.log}\n未转换任何 WebP 图片，未生成输出文件。';
    }
    await EpubImageHelper.saveArchive(
      archive,
      outputPath,
      renameMap: result.renameMap,
    );
    return '${result.log}输出文件: $outputPath\n';
  }

  static ({Map<String, String> renameMap, String log}) _convertImages(
    Archive archive,
    List<ArchiveFile> images,
  ) {
    final log = StringBuffer()
      ..writeln('找到 ${images.length} 张 WebP 图片，开始转换...');
    final renameMap = <String, String>{};
    var skipped = 0;
    var errors = 0;
    for (final file in images) {
      try {
        final newName = _convertImage(archive, file);
        if (newName == null) {
          skipped++;
          log.writeln('  跳过: ${file.name} (保留动图)');
          continue;
        }
        renameMap[file.name] = newName;
        log.writeln('  ${file.name} → $newName');
      } catch (error) {
        errors++;
        log.writeln('  错误: ${file.name} - $error');
      }
    }
    if (renameMap.isNotEmpty) {
      log.writeln(
        '\n转换完成: 转换 ${renameMap.length} 张, 跳过 $skipped 张, 错误 $errors 张',
      );
    }
    return (renameMap: renameMap, log: log.toString());
  }

  static String? _convertImage(Archive archive, ArchiveFile file) {
    final image = img.decodeWebP(EpubImageHelper.readBytes(file));
    if (image == null) throw const FormatException('WebP 解码失败');
    if (image.numFrames > 1) return null;
    final transparent = image.any((pixel) => pixel.aNormalized < 1);
    final extension = transparent ? '.png' : '.jpg';
    final newName = '${p.posix.withoutExtension(file.name)}$extension';
    if (archive.findFile(newName) != null) {
      throw StateError('目标文件已存在: $newName');
    }
    final encoded = transparent
        ? img.encodePng(image, level: 9)
        : img.encodeJpg(image, quality: 90);
    EpubImageHelper.replaceFile(archive, file.name, newName, encoded);
    return newName;
  }
}
