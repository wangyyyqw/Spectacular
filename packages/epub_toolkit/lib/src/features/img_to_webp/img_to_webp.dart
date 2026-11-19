import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import 'epub_image_helper.dart';

class ImgToWebpOperation {
  ImgToWebpOperation._();

  static const int webpQuality = 80;

  static Future<String> execute({
    required String epubPath,
    required String outputPath,
  }) async {
    final archive = await EpubImageHelper.readArchive(epubPath);
    final images = EpubImageHelper.findImages(
      archive,
      EpubImageHelper.webpConvertExts,
    );
    if (images.isEmpty) return '未找到可转换的图片（支持 JPG/PNG/BMP）。';
    final cwebp = await _findCwebpExecutable();
    final result = await _convertImages(archive, images, cwebp);
    if (result.renameMap.isEmpty) {
      return '${result.log}\n未转换任何图片，未生成输出文件。';
    }
    await EpubImageHelper.saveArchive(
      archive,
      outputPath,
      renameMap: result.renameMap,
    );
    return '编码组件: $cwebp\n${result.log}输出文件: $outputPath\n';
  }

  static Future<({Map<String, String> renameMap, String log})> _convertImages(
    Archive archive,
    List<ArchiveFile> images,
    String cwebp,
  ) async {
    final log = StringBuffer()
      ..writeln('找到 ${images.length} 张图片，开始转换为 WebP...');
    final renameMap = <String, String>{};
    var skipped = 0;
    var errors = 0;
    for (final file in images) {
      try {
        final newName = await _convertImage(archive, file, cwebp);
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

  static Future<String?> _convertImage(
    Archive archive,
    ArchiveFile file,
    String cwebp,
  ) async {
    final image = img.decodeImage(EpubImageHelper.readBytes(file));
    if (image == null) throw const FormatException('图片解码失败');
    if (image.numFrames > 1) return null;
    final newName = '${p.posix.withoutExtension(file.name)}.webp';
    if (archive.findFile(newName) != null) {
      throw StateError('目标文件已存在: $newName');
    }
    final encoded = await _encodeWebP(image, cwebp);
    EpubImageHelper.replaceFile(archive, file.name, newName, encoded);
    return newName;
  }

  static Future<Uint8List> _encodeWebP(img.Image image, String cwebp) async {
    final temporary = await Directory.systemTemp.createTemp('epub_webp_');
    try {
      final input = File(p.join(temporary.path, 'input.png'));
      final output = File(p.join(temporary.path, 'output.webp'));
      await input.writeAsBytes(img.encodePng(image));
      final result = await Process.run(cwebp, [
        '-quiet',
        '-q',
        '$webpQuality',
        '-alpha_q',
        '100',
        '-exact',
        input.path,
        '-o',
        output.path,
      ]);
      if (result.exitCode != 0 || !await output.exists()) {
        throw StateError('cwebp 编码失败: ${result.stderr}');
      }
      final bytes = await output.readAsBytes();
      final decoded = img.decodeWebP(bytes);
      if (decoded == null ||
          decoded.width != image.width ||
          decoded.height != image.height) {
        throw StateError('cwebp 未输出有效的原尺寸 WebP 图片');
      }
      return bytes;
    } finally {
      await temporary.delete(recursive: true);
    }
  }

  static Future<String> _findCwebpExecutable() async {
    if (!Platform.isMacOS && !Platform.isWindows && !Platform.isLinux) {
      throw UnsupportedError('图片转 WebP 仅支持桌面版的本地 cwebp');
    }
    final executableDirectory = p.dirname(Platform.resolvedExecutable);
    final candidates = [
      if (Platform.environment['CWEBP_PATH'] case final String executable)
        executable,
      if (Platform.isMacOS)
        p.normalize(
          p.join(executableDirectory, '..', 'Resources', 'bin', 'cwebp'),
        ),
      p.join(
        executableDirectory,
        'bin',
        Platform.isWindows ? 'cwebp.exe' : 'cwebp',
      ),
      Platform.isWindows ? 'cwebp.exe' : 'cwebp',
    ];
    for (final candidate in candidates) {
      try {
        final result = await Process.run(candidate, ['-version']);
        if (result.exitCode == 0) return candidate;
      } on ProcessException {
        continue;
      }
    }
    throw StateError(
      '未找到可用的 cwebp。请将本地 cwebp 放入应用的 Resources/bin（macOS）'
      '或 bin（Windows/Linux），或设置 PATH / CWEBP_PATH 后重试。',
    );
  }
}
