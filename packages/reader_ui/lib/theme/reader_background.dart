import 'package:flutter/material.dart';

/// 阅读页背景（P4-22）：纯色（跟随主题）或内置纹理图。
///
/// 背景只影响绘制层，不进入排版指纹——换背景不重排（§31.4）。
class ReaderBackground {
  /// 创建背景。
  const ReaderBackground({
    required this.id,
    required this.name,
    this.asset,
    this.tint,
  });

  /// 稳定标识（持久化用）。
  final String id;

  /// 显示名。
  final String name;

  /// 纹理资源路径；null 表示纯色（跟随主题背景色）。
  final String? asset;

  /// 纹理混色；null 表示保留资源原色。
  final Color? tint;

  /// 用户图片标识由宿主保存并读取，UI 包不访问文件系统。
  bool get isImage => id.startsWith('image:') && id.length > 6;

  /// 用户选择的图片；路径由宿主管理。
  static ReaderBackground image(String path) =>
      ReaderBackground(id: 'image:$path', name: '图片');

  /// 无纹理（纯色）。
  static const none = ReaderBackground(id: 'none', name: '纯色');

  /// 米色纸纹。
  static const paper = ReaderBackground(
    id: 'paper',
    name: '纸纹',
    asset: 'assets/textures/paper.png',
  );

  /// 木纹。
  static const wood = ReaderBackground(
    id: 'wood',
    name: '木纹',
    asset: 'assets/textures/wood.png',
  );

  /// 灰纸。
  static const gray = ReaderBackground(
    id: 'gray',
    name: '灰纸',
    asset: 'assets/textures/gray.png',
  );

  /// 羊皮纸。
  static const parchment = ReaderBackground(
    id: 'parchment',
    name: '羊皮纸',
    asset: 'assets/textures/paper.png',
    tint: Color(0xFFE2C38E),
  );

  /// 全部内置背景。
  static const List<ReaderBackground> all = <ReaderBackground>[
    none,
    paper,
    wood,
    gray,
    parchment,
  ];

  /// 按 id 查找；未知 id 回落纯色。
  static ReaderBackground byId(String id) {
    if (id.startsWith('image:') && id.length > 6) {
      return ReaderBackground(id: id, name: '图片');
    }
    for (final background in all) {
      if (background.id == id) {
        return background;
      }
    }
    return none;
  }
}
