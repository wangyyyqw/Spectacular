import 'dart:math' as math;

import 'package:reader_core/paint/image_size.dart';

typedef _Dimensions = (double? width, double? height);
typedef _Limits = (double width, double height);

/// 图片显示尺寸：CSS 优先于表现属性，缺边按比例补齐，再限制页高。
///
/// 公开入口保留原有命名参数，内部按声明解析与缺边补齐分段。
(double, double) resolveImageDisplaySize(
  Map<String, String> attributes,
  ImageIntrinsicSize? intrinsic,
  double maxWidth,
  double maxHeight, {
  double? cssWidth,
  double? cssHeight,
  double? cssMaxWidth,
  double? cssMaxHeight,
  double? aspectRatio,
}) {
  final limits = (
    cssMaxWidth == null ? maxWidth : math.min(maxWidth, cssMaxWidth),
    cssMaxHeight == null ? maxHeight : math.min(maxHeight, cssMaxHeight),
  );
  final declared = _declaredDimensions(
    attributes,
    (cssWidth, cssHeight),
    (maxWidth, maxHeight),
    limits,
  );
  return _completeDimensions(declared, intrinsic, limits, aspectRatio);
}

_Dimensions _declaredDimensions(
  Map<String, String> attributes,
  _Dimensions css,
  _Limits base,
  _Limits limits,
) {
  var width = css.$1 ?? _attributeLength(attributes['width'], base.$1);
  var height = css.$2 ?? _attributeLength(attributes['height'], base.$2);
  if (width != null && width > limits.$1) width = limits.$1;
  if (height != null && height > limits.$2) height = limits.$2;
  return (width, height);
}

double? _attributeLength(String? raw, double percentBase) {
  if (raw == null) return null;
  final value = raw.trim();
  if (value.isEmpty) return null;
  if (!value.endsWith('%')) {
    return double.tryParse(value.replaceAll('px', '').trim());
  }
  final percent = double.tryParse(value.substring(0, value.length - 1));
  return percent == null ? null : percentBase * percent / 100;
}

(double, double) _completeDimensions(
  _Dimensions declared,
  ImageIntrinsicSize? intrinsic,
  _Limits limits,
  double? aspectRatio,
) {
  var (width, height) = declared;
  if (width == null && height == null) {
    if (intrinsic == null && aspectRatio == null) {
      return (limits.$1, limits.$2 * 0.6);
    }
    width = limits.$1;
  }
  if (width != null && height == null) {
    height = aspectRatio != null
        ? width / aspectRatio
        : intrinsic == null
        ? null
        : width * intrinsic.height / intrinsic.width;
  } else if (height != null && width == null) {
    width = aspectRatio != null
        ? height * aspectRatio
        : intrinsic == null
        ? null
        : height * intrinsic.width / intrinsic.height;
  }
  width ??= limits.$1;
  height ??= aspectRatio == null ? width * 0.75 : width / aspectRatio;
  if (height > limits.$2) height = limits.$2;
  return (width, height);
}
