import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:reader_ui/decorations/decoration_image_store.dart';
import 'package:reader_ui/theme/reader_background.dart';

import 'reader_background_store.dart';

/// 装饰图片使用独立目录，复用阅读背景的尺寸与 PNG 压缩策略。
class ReaderDecorationImages implements ReaderDecorationImageStore {
  /// 可注入目录以验证隔离存储与引用清理。
  ReaderDecorationImages({Future<Directory> Function()? directoryProvider})
    : _directoryProvider = directoryProvider ?? getApplicationSupportDirectory,
      _store = ReaderBackgroundStore(
        directoryProvider: directoryProvider,
        directoryName: 'decoration_images',
        filePrefix: 'decoration',
      );

  final Future<Directory> Function() _directoryProvider;
  final ReaderBackgroundStore _store;

  @override
  Future<String?> pickImage() async {
    final id = await _store.pick();
    return id?.substring(6);
  }

  /// 导入本地字节，返回稳定的应用目录图片路径。
  Future<String> import(Uint8List bytes) async =>
      (await _store.import(bytes)).substring(6);

  @override
  Future<Uint8List> loadImage(String path) =>
      _store.load(ReaderBackground.image(path).id);

  @override
  Future<void> removeUnused(Set<String> referencedPaths) async {
    final directory = Directory(
      p.join((await _directoryProvider()).path, 'decoration_images'),
    );
    if (!await directory.exists()) return;
    final normalized = {for (final path in referencedPaths) p.normalize(path)};
    await for (final entry in directory.list(followLinks: false)) {
      if (entry is! File ||
          !p.basename(entry.path).startsWith('decoration-') ||
          p.extension(entry.path) != '.png' ||
          normalized.contains(p.normalize(entry.path))) {
        continue;
      }
      await entry.delete();
    }
  }
}
