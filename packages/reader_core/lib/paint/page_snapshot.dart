/// 页序列快照哈希。
///
/// 固定视口、字体、字号、DPR 等排版参数后，对页文本序列生成 SHA-256，
/// 用于回归对比。P2-25 会把真实 [PageSlice] 的可见内容接入这里。
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

/// 快照的排版配置。
class SnapshotConfig {
  /// 创建快照配置。
  const SnapshotConfig({
    required this.pageWidth,
    required this.pageHeight,
    required this.devicePixelRatio,
    required this.fontFamily,
    required this.fontSize,
    required this.lineHeight,
    required this.language,
    this.letterSpacing = 0,
    this.theme = 'light',
    this.writingMode = 'horizontal-tb',
  });

  /// 页面逻辑宽。
  final double pageWidth;

  /// 页面逻辑高。
  final double pageHeight;

  /// 设备像素比。
  final double devicePixelRatio;

  /// 字族。
  final String fontFamily;

  /// 字号。
  final double fontSize;

  /// 行高倍数。
  final double lineHeight;

  /// 语言标签。
  final String language;

  /// 字距。
  final double letterSpacing;

  /// 主题标识。
  final String theme;

  /// 书写模式。
  final String writingMode;

  /// 稳定的 JSON 表示（字段顺序固定）。
  Map<String, Object?> toJson() => <String, Object?>{
    'pageWidth': pageWidth,
    'pageHeight': pageHeight,
    'devicePixelRatio': devicePixelRatio,
    'fontFamily': fontFamily,
    'fontSize': fontSize,
    'lineHeight': lineHeight,
    'language': language,
    'letterSpacing': letterSpacing,
    'theme': theme,
    'writingMode': writingMode,
  };
}

/// 一页的快照输入。
class SnapshotPage {
  /// 创建页快照输入。
  const SnapshotPage({required this.text, this.annotations = const <String>[]});

  /// 该页可见文本（按阅读顺序拼接）。
  final String text;

  /// 该页上的标注摘要（按创建顺序）。
  final List<String> annotations;

  /// 稳定的 JSON 表示。
  Map<String, Object?> toJson() => <String, Object?>{
    'text': text,
    'annotations': annotations,
  };
}

/// 页序列哈希器。
abstract final class PageSnapshot {
  /// 计算页序列的 SHA-256。
  ///
  /// 输入相同则输出相同；配置、页内容或页顺序变化都会改变结果。
  static String hash(List<SnapshotPage> pages, SnapshotConfig config) {
    final payload = jsonEncode(<String, Object?>{
      'config': config.toJson(),
      'pages': pages.map((page) => page.toJson()).toList(growable: false),
    });
    return sha256.convert(utf8.encode(payload)).toString();
  }
}
