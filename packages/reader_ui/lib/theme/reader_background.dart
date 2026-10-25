/// 阅读页背景（P4-22）：纯色（跟随主题）或内置纹理图。
///
/// 背景只影响绘制层，不进入排版指纹——换背景不重排（§31.4）。
class ReaderBackground {
  /// 创建背景。
  const ReaderBackground({required this.id, required this.name, this.asset});

  /// 稳定标识（持久化用）。
  final String id;

  /// 显示名。
  final String name;

  /// 纹理资源路径；null 表示纯色（跟随主题背景色）。
  final String? asset;

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

  /// 全部内置背景。
  static const List<ReaderBackground> all = <ReaderBackground>[
    none,
    paper,
    wood,
    gray,
  ];

  /// 按 id 查找；未知 id 回落纯色。
  static ReaderBackground byId(String id) {
    for (final background in all) {
      if (background.id == id) {
        return background;
      }
    }
    return none;
  }
}
