import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/css/selector.dart';
import 'package:reader_core/layout/float_occupancy.dart';
import 'package:reader_core/layout/paginator.dart';

import 'generated_content.dart';

/// 单章遍历的输出和流游标，既不保存会话设置，也不持有资源句柄。
class ChapterFlow {
  List<PageBlock> blocks = [];
  final List<PageBlock> fixedBlocks = [];
  int figureSeq = 0;
  int containerFloatSeq = 0;
  double pendingRelativeTop = 0;
}

/// 递归位置收敛为不可变数据；显式字段保留各类容器的原有布局语义。
class BlockPosition {
  const BlockPosition({
    this.blockTag = 'body',
    this.attributes,
    this.groupId = 0,
    this.list,
    this.quoteDepth = 0,
    this.ancestors = const [],
    this.firstInContainer = false,
    this.lastInContainer = false,
    this.listFirst = false,
    this.listLast = false,
    this.containerFloat,
    this.containerFloatWidth,
    this.containerFloatGroup = 0,
  });
  final String blockTag;
  final Map<String, String>? attributes;
  final int groupId;
  final ListContext? list;
  final int quoteDepth;
  final List<SelectorElement> ancestors;
  final bool firstInContainer;
  final bool lastInContainer;
  final bool listFirst;
  final bool listLast;
  final FloatSide? containerFloat;
  final double? containerFloatWidth;
  final int containerFloatGroup;
}

/// 列表上下文（P3-23）：类型 + 嵌套深度 + ol 序号计数。
class ListContext {
  ListContext(
    this.type,
    this.depth, {
    this.spaceBefore = 0,
    this.spaceAfter = 0,
    this.inside = false,
  });

  /// 'ul' 或 'ol'。
  final String type;

  /// 嵌套深度（0 起）。
  final int depth;

  /// 列表容器在首项之前占的高度（容器外边距 + 上边框 + 上内边距）。
  ///
  /// flat 管线不产出容器块，容器的上下外边距必须由首/末项承担，否则
  /// 列表整体上移（用例 11/30 的首项 y 差 6px）。
  final double spaceBefore;

  /// 列表容器在末项之后占的高度（下边框 + 下内边距 + 下外边距）。
  final double spaceAfter;

  /// 列表容器的 `list-style-position: inside`（CSS 里该属性继承，但
  /// ComputedStyle 目前按不继承实现，所以由容器把值带给 li）。
  final bool inside;

  /// 当前 li 还没挂标记（进入新 li 时置位，首个文本块消费后清除）。
  bool markerPending = false;

  int _olCounter = 0;

  /// 当前项的标记文本（P9-12）：优先按 `list-style-type` 选择
  ///（decimal/roman/alpha 等），`none` 不画标记；未声明时 ol 递增序号、
  /// ul 按深度取 disc→circle→square（Reeden 630 §0-#4 嵌套类型轮换）。
  String nextMarker(CssListStyleType style) {
    if (type == 'ol') {
      _olCounter += 1;
      return switch (style) {
        CssListStyleType.none => '',
        CssListStyleType.lowerRoman =>
          '${romanCounter(_olCounter).toLowerCase()}.',
        CssListStyleType.upperRoman => '${romanCounter(_olCounter)}.',
        CssListStyleType.lowerAlpha =>
          '${alphaCounter(_olCounter).toLowerCase()}.',
        CssListStyleType.upperAlpha =>
          '${alphaCounter(_olCounter).toUpperCase()}.',
        CssListStyleType.circle => '○$_olCounter.',
        CssListStyleType.square => '▪$_olCounter.',
        _ => '$_olCounter.',
      };
    }
    return switch (style) {
      CssListStyleType.none => '',
      CssListStyleType.circle => '○',
      CssListStyleType.square => '▪',
      CssListStyleType.decimal => '${_olCounter += 1}.',
      CssListStyleType.lowerRoman =>
        '${romanCounter(++_olCounter).toLowerCase()}.',
      CssListStyleType.upperRoman => '${romanCounter(++_olCounter)}.',
      CssListStyleType.lowerAlpha =>
        '${alphaCounter(++_olCounter).toLowerCase()}.',
      CssListStyleType.upperAlpha =>
        '${alphaCounter(++_olCounter).toUpperCase()}.',
      CssListStyleType.disc => const <String>['•', '○', '▪'][depth.clamp(0, 2)],
    };
  }
}
