import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:reader_ui/theme/reader_background.dart';

/// 图片复制到应用目录并限制解码尺寸，原文件移动后仍可使用。
class ReaderBackgroundStore {
  /// 可注入目录以验证导入与恢复。
  ReaderBackgroundStore({
    Future<Directory> Function()? directoryProvider,
    this.directoryName = 'reader_backgrounds',
    this.filePrefix = 'background',
  }) : _directoryProvider = directoryProvider ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _directoryProvider;

  /// 图片目录名，用于隔离阅读背景与手工装饰。
  final String directoryName;

  /// 本存储负责的文件前缀。
  final String filePrefix;

  Future<Directory> _directory() async =>
      Directory(p.join((await _directoryProvider()).path, directoryName));

  /// 使用已有文件选择器，无需访问整个相册。
  Future<String?> pick({bool preserveNinePatch = false}) async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
    );
    if (file == null) return null;
    return import(
      await file.readAsBytes(),
      preserveSize:
          preserveNinePatch && file.name.toLowerCase().endsWith('.9.png'),
    );
  }

  /// 普通图片只保存首帧，最长边限制为 1600px；点九保留原始尺寸。
  Future<String> import(Uint8List bytes, {bool preserveSize = false}) async {
    if (bytes.isEmpty || bytes.length > 20 * 1024 * 1024) {
      throw const FormatException('请选择小于 20MB 的图片');
    }
    final data = await _resize(bytes, preserveSize);
    final directory = await _directory();
    await directory.create(recursive: true);
    final file = File(
      p.join(
        directory.path,
        '$filePrefix-${DateTime.now().microsecondsSinceEpoch}${preserveSize ? '.9' : ''}.png',
      ),
    );
    await file.writeAsBytes(data, flush: true);
    return ReaderBackground.image(file.path).id;
  }

  Future<Uint8List> _resize(Uint8List bytes, bool preserveSize) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    try {
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      try {
        final longest = descriptor.width > descriptor.height
            ? descriptor.width
            : descriptor.height;
        final scale = !preserveSize && longest > 1600 ? 1600 / longest : 1.0;
        final codec = await descriptor.instantiateCodec(
          targetWidth: (descriptor.width * scale).round().clamp(
            1,
            descriptor.width,
          ),
          targetHeight: (descriptor.height * scale).round().clamp(
            1,
            descriptor.height,
          ),
        );
        try {
          return await _encodeFrame(codec);
        } finally {
          codec.dispose();
        }
      } finally {
        descriptor.dispose();
      }
    } finally {
      buffer.dispose();
    }
  }

  Future<Uint8List> _encodeFrame(ui.Codec codec) async {
    final frame = await codec.getNextFrame();
    try {
      final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw const FormatException('图片无法保存');
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } finally {
      frame.image.dispose();
    }
  }

  /// 只读取本应用保存的背景，损坏或缺失交给 UI 回退主题底色。
  Future<Uint8List> load(String id) async {
    if (!ReaderBackground.byId(id).isImage) {
      throw const FormatException('背景图片路径无效');
    }
    final directory = await _directory();
    final path = id.substring(6);
    if (!p.isWithin(directory.path, path)) {
      throw const FormatException('背景图片路径无效');
    }
    return File(path).readAsBytes();
  }

  /// 清理一天前的废弃文件，避开正在导入或尚未保存的图片。
  Future<void> cleanUnused(String id, {String? pendingId}) async {
    final directory = await _directory();
    if (!await directory.exists()) return;
    final cutoff = DateTime.now().subtract(const Duration(days: 1));
    await for (final file in directory.list()) {
      if (file is! File ||
          !p.basename(file.path).startsWith('$filePrefix-') ||
          ReaderBackground.image(file.path).id == id ||
          ReaderBackground.image(file.path).id == pendingId) {
        continue;
      }
      if ((await file.stat()).modified.isBefore(cutoff)) await file.delete();
    }
  }
}
