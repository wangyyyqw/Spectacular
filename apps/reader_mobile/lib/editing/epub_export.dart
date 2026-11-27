import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// 导出传文件路径，Android 由系统输出流复制，桌面由原生保存面板选择位置。
class EpubExport {
  static const _channel = MethodChannel(
    'com.spectacular.reader_mobile/epub_export',
  );

  /// 保存、导出和旧稿恢复共用独立暂存目录。
  static Future<Directory> createTemporaryDirectory() async {
    final temporary = await getTemporaryDirectory();
    await temporary.create(recursive: true);
    return temporary.createTemp('epub-edit-');
  }

  /// 将书库当前版本导出到下载目录，包含已保存的图书资料与封面。
  static Future<bool> saveToDownloads(
    File source, {
    required String fileName,
  }) async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return save(
        source,
        fileName: fileName,
        initialDirectory: (await getDownloadsDirectory())?.path,
      );
    }
    if (!await source.exists()) {
      throw FileSystemException('待导出的 EPUB 不存在', source.path);
    }
    final uri = await _channel.invokeMethod<String>('saveToDownloads', {
      'sourcePath': source.absolute.path,
      'fileName': fileName,
    });
    return uri != null;
  }

  static Future<bool> save(
    File source, {
    required String fileName,
    String? initialDirectory,
  }) async {
    if (!await source.exists()) {
      throw FileSystemException('待导出的 EPUB 不存在', source.path);
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      final uri = await _channel.invokeMethod<String>('saveFile', {
        'sourcePath': source.absolute.path,
        'fileName': fileName,
      });
      return uri != null;
    }
    if (!{
      TargetPlatform.macOS,
      TargetPlatform.windows,
      TargetPlatform.linux,
    }.contains(defaultTargetPlatform)) {
      throw UnsupportedError('当前平台暂不支持 EPUB 文件导出');
    }
    final location = await getSaveLocation(
      suggestedName: fileName,
      initialDirectory: initialDirectory,
      acceptedTypeGroups: const [
        XTypeGroup(label: 'EPUB 电子书', extensions: ['epub']),
      ],
    );
    if (location == null) return false;
    if (File(location.path).absolute.path == source.absolute.path) return true;
    await XFile(
      source.path,
      mimeType: 'application/epub+zip',
    ).saveTo(location.path);
    return true;
  }
}
