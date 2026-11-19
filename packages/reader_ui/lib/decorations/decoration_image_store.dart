import 'dart:typed_data';

/// 宿主负责装饰图片的选择、压缩、读取和引用清理。
abstract interface class ReaderDecorationImageStore {
  /// 选择本地图片并存入独立目录；取消时返回空值。
  Future<String?> pickImage();

  /// 读取已保存图片；路径失效时抛出异常，由视图回退到背景色。
  Future<Uint8List> loadImage(String path);

  /// 仅删除独立目录内、没有任何装饰引用的图片。
  Future<void> removeUnused(Set<String> referencedPaths);
}

abstract interface class ReaderDecorationNinePatchImageStore
    implements ReaderDecorationImageStore {
  Future<String> saveNinePatch(Uint8List bytes);
}
