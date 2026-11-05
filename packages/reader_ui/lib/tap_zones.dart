/// 阅读页九宫格点击区域。
enum ReaderTapZone {
  topLeft,
  topCenter,
  topRight,
  middleLeft,
  center,
  middleRight,
  bottomLeft,
  bottomCenter,
  bottomRight,
}

/// 单个点击区域的动作。
enum ReaderTapAction { previousPage, nextPage, openMenu, none }

/// 九宫格动作配置；顺序与 [ReaderTapZone.values] 一致。
class ReaderTapZones {
  /// 创建配置。
  const ReaderTapZones(this.actions);

  /// 默认布局与多看一致：左右翻页，中间打开菜单。
  static const ReaderTapZones defaults = ReaderTapZones(<ReaderTapAction>[
    ReaderTapAction.previousPage,
    ReaderTapAction.previousPage,
    ReaderTapAction.nextPage,
    ReaderTapAction.previousPage,
    ReaderTapAction.openMenu,
    ReaderTapAction.nextPage,
    ReaderTapAction.previousPage,
    ReaderTapAction.nextPage,
    ReaderTapAction.nextPage,
  ]);

  /// 除中央菜单外，点击屏幕任意区域翻到下一页。
  static const ReaderTapZones fullScreenNext = ReaderTapZones(<ReaderTapAction>[
    ReaderTapAction.nextPage,
    ReaderTapAction.nextPage,
    ReaderTapAction.nextPage,
    ReaderTapAction.nextPage,
    ReaderTapAction.openMenu,
    ReaderTapAction.nextPage,
    ReaderTapAction.nextPage,
    ReaderTapAction.nextPage,
    ReaderTapAction.nextPage,
  ]);

  /// 九个区域的动作。
  final List<ReaderTapAction> actions;

  /// 是否处于「全屏点击下一页」布局。
  bool get isFullScreenNext {
    for (final zone in ReaderTapZone.values) {
      final expected = zone == ReaderTapZone.center
          ? ReaderTapAction.openMenu
          : ReaderTapAction.nextPage;
      if (actionAt(zone) != expected) {
        return false;
      }
    }
    return true;
  }

  /// 读取指定区域。
  ReaderTapAction actionAt(ReaderTapZone zone) => actions[zone.index];

  /// 复制并替换一个区域。
  ReaderTapZones withAction(ReaderTapZone zone, ReaderTapAction action) {
    final next = List<ReaderTapAction>.of(actions);
    next[zone.index] = action;
    return ReaderTapZones(List<ReaderTapAction>.unmodifiable(next));
  }

  /// 序列化为以区域名为键的对象。
  Map<String, String> toJson() => <String, String>{
    for (final zone in ReaderTapZone.values) zone.name: actionAt(zone).name,
  };

  /// 从持久化对象恢复；未知字段和非法动作回落到默认值。
  static ReaderTapZones fromJson(Object? raw) {
    if (raw is! Map) {
      return defaults;
    }
    final actions = <ReaderTapAction>[];
    for (final zone in ReaderTapZone.values) {
      final name = raw[zone.name];
      actions.add(
        ReaderTapAction.values.firstWhere(
          (action) => action.name == name,
          orElse: () => defaults.actionAt(zone),
        ),
      );
    }
    return ReaderTapZones(List<ReaderTapAction>.unmodifiable(actions));
  }

  @override
  bool operator ==(Object other) {
    if (other is! ReaderTapZones) {
      return false;
    }
    for (var i = 0; i < actions.length; i++) {
      if (actions[i] != other.actions[i]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(actions);
}

/// 设置面板里显示的动作名。
extension ReaderTapActionLabel on ReaderTapAction {
  /// 中文动作名。
  String get label => switch (this) {
    ReaderTapAction.previousPage => '上一页',
    ReaderTapAction.nextPage => '下一页',
    ReaderTapAction.openMenu => '菜单',
    ReaderTapAction.none => '无动作',
  };
}
