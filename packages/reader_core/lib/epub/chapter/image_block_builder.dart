import 'dart:math' as math;

import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/css/selector.dart';
import 'package:reader_core/layout/block_flow.dart' show collapseMargins;
import 'package:reader_core/layout/box_model.dart';
import 'package:reader_core/layout/float_occupancy.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/paint/image_size.dart';
import 'package:reader_core/parser/block_builder.dart';

import 'block_style_helpers.dart';
import 'chapter_flow.dart';
import 'chapter_selectors.dart';
import 'chapter_style_resolver.dart';
import 'generated_chapter_content.dart';
import 'image_blocks.dart';
import 'inline_content_builder.dart';

typedef _ImageSize = (double width, double height);
typedef _ImageFloat = ({FloatSide? side, double? width, PageFloatBox? box});
typedef _ImageGeometry = ({
  double width,
  double height,
  double blockWidth,
  double containingWidth,
  FloatSide? side,
  PageFloatBox? floatBox,
  int group,
});

/// 单张块级图片的尺寸与盒载荷；不改变共享遍历游标。
class ImageBlockBuilder {
  ImageBlockBuilder(this.styles, this.inline, this.content);

  final ChapterStyleResolver styles;
  final InlineContentBuilder inline;
  final GeneratedChapterContent content;

  Future<List<PageBlock>> build(
    BlockNode node,
    BlockPosition position, {
    List<PageFootnote> footnotes = const [],
  }) async {
    await inline.measure.budget.checkpoint();
    final src =
        node.attributes['src'] ??
        node.attributes['xlink:href'] ??
        node.attributes['href'] ??
        node.attributes['data'];
    if (src == null || src.isEmpty) return const [];
    final chain = await _foldedChain(node, position.ancestors);
    final intrinsic = await inline.prepareImageIntrinsicSize(
      inline.imageUrl(src),
    );
    final input = _ImageDescription(this, node, position, (
      src,
      chain,
    ), intrinsic);
    final geometry = await _ImageSizing(input).measure();
    final style = _imagePaintStyle(input, geometry);
    final notes = _imageFootnotes(input, footnotes);
    await inline.measure.budget.checkpoint();
    final block = _imageBlock(input, geometry, style, notes);
    if (node.containerChain.isEmpty) return [block];
    final margins = _foldedAncestorMargins(input);
    if (geometry.side != null &&
        !margins.hasFloatAncestor &&
        position.containerFloat == null) {
      return [block.withSpacing(floatParentMargins: margins.parents)];
    }
    return [
      block.withSpacing(
        spaceBefore: collapseMargins(block.spaceBefore, margins.before),
        spaceAfter: collapseMargins(block.spaceAfter, margins.after),
      ),
    ];
  }

  Future<List<SelectorElement>> _foldedChain(
    BlockNode node,
    List<SelectorElement> ancestors,
  ) async {
    if (node.containerChain.isEmpty) return ancestors;
    final original = styles.selectorIndex.chainOf(node);
    if (original != null) {
      return original.take(original.length - 1).toList(growable: false);
    }
    final result = <SelectorElement>[];
    for (final hint in node.containerChain) {
      await inline.measure.budget.checkpoint();
      result.add(
        ChapterNodeView(
          hint.tag,
          hint.classes.isEmpty ? const {} : {'class': hint.classes},
          const [],
        ),
      );
    }
    return result;
  }
}

/// 纯图折叠会移除逐层父块；每层父块都只有这张图，因此把它们的外边距
/// 依次与图片段距折叠，避免 `div > img` 的垂直定位或间距丢失。
({
  double before,
  double after,
  bool hasFloatAncestor,
  FloatParentMargins parents,
})
_foldedAncestorMargins(_ImageDescription input) {
  var before = 0.0;
  var after = 0.0;
  var hasFloatAncestor = false;
  var parents = const FloatParentMargins();
  for (var index = 0; index < input.chain.length; index++) {
    final style = input.styles.chainStyle(input.chain.sublist(0, index + 1));
    // 浮动整盒独立消费自己的外边距，纯图折叠只携带盒内后代的边距。
    if (style.cssFloat != CssFloat.none) {
      before = after = 0.0;
      hasFloatAncestor = true;
      parents = const FloatParentMargins();
      continue;
    }
    // 保留容器由首末子块消费边距；纯图路径只还原已折叠的祖先盒。
    if (input.styles.retainedContainers.containsKey(input.chain[index])) {
      continue;
    }
    before = collapseMargins(before, style.margin.top);
    after = collapseMargins(after, style.margin.bottom);
    parents = parents.include(style.margin.top).include(style.margin.bottom);
  }
  return (
    before: before,
    after: after,
    hasFloatAncestor: hasFloatAncestor,
    parents: parents,
  );
}

/// 首次级联后立即冻结图片属性，后续容器级联不覆盖定位与透明度。
class _ImageDescription {
  _ImageDescription(
    this.builder,
    this.node,
    this.position,
    (String, List<SelectorElement>) source,
    this.intrinsic,
  ) : url = builder.inline.imageUrl(source.$1),
      chain = source.$2 {
    imageChain = [
      ...chain,
      ChapterNodeView(node.tag, node.attributes, const []),
    ];
    final projected = builder.styles.styleForChain(imageChain);
    style = projected.isOutOfFlow
        ? builder.styles.chainStyle(imageChain)
        : projected;
    promotedLeft = builder.styles.promotedLeftForLastChain;
    opacity = builder.styles.effectiveOpacityForLastChain;
  }

  final ImageBlockBuilder builder;
  final BlockNode node;
  final BlockPosition position;
  final String url;
  final List<SelectorElement> chain;
  late final List<SelectorElement> imageChain;
  late final ComputedStyle style;
  late final double promotedLeft;
  late final double opacity;
  final ImageIntrinsicSize? intrinsic;
  ChapterStyleResolver get styles => builder.styles;
  InlineContentBuilder get inline => builder.inline;
}

/// 容器宽、声明尺寸和浮动钳制按原先顺序解算，只持有当前图片输入。
class _ImageSizing {
  _ImageSizing(this.input);

  final _ImageDescription input;

  Future<_ImageGeometry> measure() async {
    final containingWidth = await _containingWidth();
    var size = _constrainMaxWidth(
      _declaredSize(containingWidth),
      containingWidth,
    );
    final chainFloat = await _containerFloat();
    final ownSide = input.styles.floatSideOf(
      input.node.attributes,
      ancestors: input.chain,
    );
    final side = ownSide ?? input.position.containerFloat ?? chainFloat.side;
    final columnWidth = input.position.containerFloat != null
        ? input.position.containerFloatWidth
        : chainFloat.width;
    size = _limitFloatingWidth(size, ownSide, input.styles.snapshot.width);
    var blockWidth = side != null || input.style.isOutOfFlow
        ? size.$1
        : input.styles.snapshot.width;
    if (side != null && columnWidth != null) {
      blockWidth = math.min(blockWidth, columnWidth);
      size = _fitWidth(size, blockWidth);
    }
    if (side == null && !input.style.isOutOfFlow) {
      size = _fitAvailableWidth(size, containingWidth);
    }
    return (
      width: size.$1,
      height: size.$2,
      blockWidth: blockWidth,
      containingWidth: containingWidth,
      side: side,
      floatBox: ownSide == null ? chainFloat.box : null,
      group: _imageGroup(input.position, chainFloat.side),
    );
  }

  _ImageSize _fitAvailableWidth(_ImageSize size, double width) {
    final own = _ownImageStyle(input, width);
    final model = BoxModel.fromStyle(own, containingWidth: width);
    // 图片百分比仍取父宽；排入普通流时，为自身边距、边框和内边距留位。
    return _fitWidth(
      size,
      math.max(0, width - own.margin.horizontal - model.horizontalInset),
    );
  }

  Future<double> _containingWidth() async {
    final bleed = input.style.bleed;
    final snapshot = input.styles.snapshot;
    if (bleed.left || bleed.right) {
      return snapshot.width +
          (bleed.left ? snapshot.sideInsets.left : 0) +
          (bleed.right ? snapshot.sideInsets.right : 0);
    }
    var width = snapshot.width;
    if (input.style.isOutOfFlow &&
        (input.style.position == CssPosition.fixed ||
            !await _hasPositionedAncestor())) {
      return width;
    }
    for (var i = 0; i < input.chain.length; i++) {
      await input.inline.measure.budget.checkpoint();
      final tag = input.chain[i].tag;
      if (tag == 'html') continue;
      final container = input.styles.retainedContainers[input.chain[i]];
      if (container != null) {
        width = container.flowWidth;
        continue;
      }
      final style = input.styles.chainStyle(input.chain.sublist(0, i + 1));
      width = BoxModel.fromStyle(
        style,
        containingWidth: width,
      ).resolveContentWidth(width);
    }
    return width;
  }

  Future<bool> _hasPositionedAncestor() async {
    for (var index = input.chain.length - 1; index >= 0; index--) {
      await input.inline.measure.budget.checkpoint();
      if (input.styles.chainStyle(input.chain.sublist(0, index + 1)).position !=
          CssPosition.static) {
        return true;
      }
    }
    return false;
  }

  _ImageSize _declaredSize(double width) {
    final height = input.styles.snapshot.height;
    // 页面投影可能已按整列冻结百分比尺寸；测量仍须按实际父内容盒解算。
    final style = input.styles.chainStyle(input.imageChain);
    return resolveImageDisplaySize(
      input.node.attributes,
      input.intrinsic,
      width,
      height,
      cssWidth: _duokanFullWidthImage(input)
          ? width
          : style.width?.resolve(width),
      cssHeight: style.height?.resolve(height),
      cssMaxWidth: style.maxWidth?.resolve(width),
      cssMaxHeight: style.maxHeight?.resolve(height),
      aspectRatio: style.aspectRatio,
    );
  }

  _ImageSize _constrainMaxWidth(_ImageSize size, double width) {
    final style = input.styles.chainStyle(input.imageChain);
    if (style.maxWidth == null) return size;
    final constrained = BoxModel.fromStyle(
      style,
      containingWidth: width,
    ).resolveContentWidth(width);
    return _fitWidth(size, constrained);
  }

  Future<_ImageFloat> _containerFloat() async {
    await input.inline.measure.budget.checkpoint();
    final box = input.styles.floatBoxForChain(input.chain);
    return (
      side: box == null ? null : floatSideOfStyle(box.container.style),
      width: box?.container.contentWidth,
      box: box,
    );
  }
}

/// 多看把 `.imgd` 内唯一的图片按正文宽铺满；原书常见的
/// `width="60%"` 只参与多看以外的回退排版。
bool _duokanFullWidthImage(_ImageDescription input) {
  if (input.chain.isEmpty) return false;
  final classes = input.chain.last.attributes['class'];
  return classes != null && classes.split(RegExp(r'\s+')).contains('imgd');
}

_ImageSize _fitWidth(_ImageSize size, double width) =>
    size.$1 > width ? (width, size.$2 * width / size.$1) : size;

_ImageSize _limitFloatingWidth(
  _ImageSize size,
  FloatSide? side,
  double width,
) => side == null ? size : _fitWidth(size, width * 0.45);

int _imageGroup(BlockPosition position, FloatSide? chainFloat) =>
    position.containerFloat != null ||
        (chainFloat != null && position.containerFloatGroup > 0)
    ? position.containerFloatGroup
    : 0;

ComputedStyle _ownImageStyle(_ImageDescription input, double width) {
  final base = input.styles.chainStyle(input.imageChain);
  final own = ComputedStyle(
    {...base.values, 'font-size': '${base.fontSize}px'},
    parent: base,
    explicitProperties: base.explicitProperties,
    containingWidth: width,
    rootFontSize: base.cssRootFontSize,
  );
  final readerSize = input.styles.snapshot.overrides.fontSize;
  if (readerSize == null || input.style.isOutOfFlow) return own;
  final fontSize = own.fontSize * readerSize / input.styles.style.fontSize;
  // 只重算图片自身的字体相对外边距；父盒、图片尺寸和百分比基准保持原值。
  double margin(String side, double fallback) =>
      resolveCssNumericLength(
        own.values['margin-$side'] ?? '',
        fontSize: fontSize,
        rootFontSize: readerSize,
        percentBase: width,
      ) ??
      fallback;
  return own
      .withMargins(
        CssEdges(
          top: margin('top', own.margin.top),
          right: margin('right', own.margin.right),
          bottom: margin('bottom', own.margin.bottom),
          left: margin('left', own.margin.left),
        ),
      )
      .withTypography(fontSize: fontSize);
}

double _usedMarginLeft(_ImageDescription input, _ImageGeometry geometry) {
  final own = _ownImageStyle(input, geometry.containingWidth);
  final inlineLevel =
      own.display == CssDisplay.inline || own.display == CssDisplay.inlineBlock;
  final widthIsAuto = own.width == null || own.width!.isAuto;
  final autoMargins =
      widthIsAuto && (own.marginLeftIsAuto || own.marginRightIsAuto);
  // 出血包含块已改用页面宽，不重复叠加原祖先内容盒的水平偏移。
  final bleed = input.style.bleed;
  final left =
      (bleed.left || bleed.right ? 0 : input.promotedLeft) + own.margin.left;
  if ((geometry.side != null && geometry.floatBox == null) ||
      input.style.isOutOfFlow ||
      !(autoMargins || inlineLevel)) {
    return left;
  }
  final model = BoxModel.fromStyle(
    input.style,
    containingWidth: geometry.containingWidth,
  );
  final slack = math.max(
    0.0,
    geometry.containingWidth -
        (geometry.width + model.horizontalInset + own.margin.horizontal),
  );
  return left + _imageAlignment(own, slack, autoMargins);
}

double _imageAlignment(ComputedStyle own, double slack, bool autoMargins) =>
    autoMargins
    ? switch ((own.marginLeftIsAuto, own.marginRightIsAuto)) {
        (true, true) => slack / 2,
        (true, false) => slack,
        _ => 0,
      }
    : switch (own.resolvedTextAlign) {
        CssTextAlign.center => slack / 2,
        CssTextAlign.end || CssTextAlign.right => slack,
        _ => 0,
      };

ComputedStyle _imagePaintStyle(
  _ImageDescription input,
  _ImageGeometry geometry,
) {
  final fit = input.builder.content.objectFitBackground(
    input.imageChain,
    input.intrinsic,
    boxWidth: geometry.width,
    boxHeight: geometry.height,
  );
  final bleed = input.style.bleed;
  final own = _ownImageStyle(input, geometry.containingWidth);
  return ComputedStyle({
    ...input.style.values,
    'width': '${geometry.width}px',
    // 百分比限宽沿用测量时的包含块，出血图片不能在绘制时再按正文区收窄。
    if (input.style.maxWidth?.resolve(geometry.containingWidth)
        case final limit?)
      'max-width': '${limit}px',
    // 分页盒与背景绘制共用已限制的尺寸，不能重新使用原始声明高度。
    'height': '${geometry.height}px',
    'margin-left':
        '${input.style.isOutOfFlow ? input.style.margin.left : _usedMarginLeft(input, geometry)}px',
    ..._projectedImageMargins(input, own),
    'background-image': 'url("${input.url}")',
    'background-size': fit.size,
    'background-position': bleed.top
        ? 'center top'
        : (bleed.bottom ? 'center bottom' : fit.position),
    'background-repeat': 'no-repeat',
  }).withTypography(fontSize: own.fontSize);
}

Map<String, String> _projectedImageMargins(
  _ImageDescription input,
  ComputedStyle own,
) {
  final projected = input.style.margin;
  final authored = input.styles.chainStyle(input.imageChain).margin;
  return {
    for (final (side, before, original, scaled) in [
      ('top', projected.top, authored.top, own.margin.top),
      ('right', projected.right, authored.right, own.margin.right),
      ('bottom', projected.bottom, authored.bottom, own.margin.bottom),
    ])
      'margin-$side': '${before + scaled - original}px',
  };
}

TextLayoutResult _imageLayout(_ImageGeometry geometry) => TextLayoutResult(
  text: '',
  lines: [
    LineBox(
      start: 0,
      end: 0,
      top: 0,
      height: geometry.height,
      baseline: geometry.height,
      width: geometry.blockWidth,
    ),
  ],
  width: geometry.blockWidth,
  height: geometry.height,
  maxWidth: geometry.blockWidth,
  runs: const [],
);

List<PageFootnote> _imageFootnotes(
  _ImageDescription input,
  List<PageFootnote> incoming,
) {
  final direct = input.inline.footnoteForReference(
    input.node.tag,
    input.node.attributes,
    '',
    start: 0,
    end: 1,
  );
  return incoming.isNotEmpty ? incoming : [?direct];
}

/// 纯图折叠移除了祖先盒，仍须在唯一图片的边界执行祖先强制分页。
/// 只恢复被折叠的盒边界，保留容器的声明不重复施加到内部图片。
({bool before, bool after}) _foldedPageBreaks(_ImageDescription input) {
  var before = false;
  var after = false;
  if (input.node.containerChain.isEmpty) return (before: before, after: after);
  for (var index = 0; index < input.chain.length; index++) {
    if (input.styles.retainedContainers.containsKey(input.chain[index])) {
      continue;
    }
    final style = input.styles.chainStyle(input.chain.sublist(0, index + 1));
    if (style.isOutOfFlow || style.cssFloat != CssFloat.none) continue;
    before |= style.pageBreakBefore;
    after |= style.pageBreakAfter;
  }
  return (before: before, after: after);
}

PageBlock _imageBlock(
  _ImageDescription input,
  _ImageGeometry geometry,
  ComputedStyle style,
  List<PageFootnote> footnotes,
) {
  final model = BoxModel.fromStyle(
    style,
    containingWidth: input.styles.snapshot.width,
  );
  final layout = _imageLayout(geometry);
  final breaks = _foldedPageBreaks(input);
  return PageBlock(
    layout: layout,
    isReplaced: true,
    startCfi: input.styles.selectorIndex.imageCfiOf(input.node),
    style: style,
    pageBreakBefore: style.pageBreakBefore || breaks.before,
    pageBreakAfter: style.pageBreakAfter || breaks.after,
    breakInsideAvoid: style.breakInsideAvoid,
    breakAfterAvoid: style.breakAfterAvoid,
    spaceBefore: style.margin.top,
    spaceAfter: style.margin.bottom,
    topInset: model.borders.top + model.padding.top,
    bottomInset: model.borders.bottom + model.padding.bottom,
    leftInset: model.borders.left + model.padding.left,
    floatSide: geometry.side,
    floatBox: geometry.floatBox,
    bleedLeft: input.style.bleed.left,
    bleedRight: input.style.bleed.right,
    bleedTop: input.style.bleed.top,
    bleedBottom: input.style.bleed.bottom,
    effectiveOpacity: input.opacity,
    absolute: style.isOutOfFlow,
    groupId: geometry.group,
    declaredContentHeight: model.resolveContentHeight(
      layout.height,
      containingHeight: input.styles.snapshot.height,
    ),
    footnotes: footnotes,
  );
}
