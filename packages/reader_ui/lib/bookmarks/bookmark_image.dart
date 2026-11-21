import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show ChangeNotifier;

/// 一次阅读共用已解码的书签图片，纸面、下拉与翻页捕获不重复加载。
class ReaderBookmarkImage extends ChangeNotifier {
  String? _id;
  Future<Uint8List> Function(String)? _loader;
  Future<void>? _pending;
  ui.Image? _image;
  int _generation = 0;
  bool _failed = false;
  bool _disposed = false;

  ui.Image? get image => _image;
  bool get loading =>
      _id != null && _loader != null && _image == null && !_failed;

  Future<void> load(String? id, Future<Uint8List> Function(String)? loader) {
    if (_id == id && _loader == loader) return _pending ?? Future.value();
    _id = id;
    _loader = loader;
    _image?.dispose();
    _image = null;
    _failed = false;
    final generation = ++_generation;
    return _pending = id == null || loader == null
        ? Future.value()
        : _decode(id, loader, generation);
  }

  Future<void> _decode(
    String id,
    Future<Uint8List> Function(String) loader,
    int generation,
  ) async {
    ui.Codec? codec;
    try {
      codec = await ui.instantiateImageCodec(await loader(id));
      final image = (await codec.getNextFrame()).image;
      if (_disposed || generation != _generation) {
        image.dispose();
        return;
      }
      _image = image;
    } catch (_) {
      if (_disposed || generation != _generation) return;
      _failed = true;
    } finally {
      codec?.dispose();
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _image?.dispose();
    super.dispose();
  }
}
