import 'dart:math' as math;

import 'package:reader_core/api.dart' show PageGallery, PageGalleryFrame;
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/box_model.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/parser/block_builder.dart';

import 'chapter_style_resolver.dart';
import 'container_blocks.dart';

typedef GalleryFrameBlocks = ({
  String cfi,
  List<PageBlock> blocks,
  List<PageBlock> fixed,
});

/// 只识别规范的直接分帧容器；其他内容仍走普通排版，避免丢正文。
bool isDuokanGallery(BlockNode node) =>
    _hasClass(node, 'duokan-image-gallery') &&
    node.children.isNotEmpty &&
    node.children.every(
      (child) =>
          child is BlockNode && _hasClass(child, 'duokan-image-gallery-cell'),
    );

bool _hasClass(BlockNode node, String name) =>
    (node.attributes['class'] ?? '').split(RegExp(r'\s+')).contains(name);

/// 各帧保留作者排版，统一按最高帧占位；分页器只消费外层原子块。
class GalleryBlockBuilder {
  GalleryBlockBuilder(this.styles, this.checkpoint);

  final ChapterStyleResolver styles;
  final Future<void> Function() checkpoint;

  Future<PageBlock?> build(
    BlockNode node,
    PageContainer container,
    List<GalleryFrameBlocks> source, {
    int groupId = 0,
    double ancestorExtent = 0,
  }) async {
    final frames = await _frames(source);
    if (frames.isEmpty) return null;
    final gallery = _gallery(node, container, frames, ancestorExtent);
    final paintStyle = _paintStyle(container);
    return PageBlock.styled(
      layout: _layout(gallery),
      style: paintStyle,
      containingWidth: styles.snapshot.width,
      startCfi: node.cfi.serialize(),
      endCfi:
          frames.last.content.slices.last.block.endCfi ??
          frames.last.content.slices.last.block.startCfi,
      groupId: groupId,
      gallery: gallery,
      textRuleEligible: false,
      effectiveOpacity: container.style.effectiveOpacity,
      declaredContentHeight: gallery.height,
    );
  }

  Future<List<PageGalleryFrame>> _frames(
    List<GalleryFrameBlocks> source,
  ) async {
    final frames = <PageGalleryFrame>[];
    for (final input in source) {
      await checkpoint();
      final decorated = await configureContainerDecorationAsync(
        input.blocks,
        checkpoint: checkpoint,
      );
      final blocks = await collapseMarginsIgnoringFloatsAsync(
        decorated,
        checkpoint: checkpoint,
      );
      final page = await _framePage(blocks, input.fixed, frames.length);
      if (page.slices.isEmpty) continue;
      frames.add(
        PageGalleryFrame(
          cfi: input.cfi,
          content: page,
          imageUrl: await _imageUrl(blocks),
        ),
      );
    }
    return frames;
  }

  Future<PageContent> _framePage(
    List<PageBlock> blocks,
    List<PageBlock> fixed,
    int index,
  ) async {
    final slices = <PageBlockSlice>[];
    var y = 0.0;
    var bottom = 0.0;
    for (final block in [...blocks, ...fixed]) {
      await checkpoint();
      final slice = _slice(block);
      slices.add(slice);
      if (slice.overlay) {
        bottom = math.max(bottom, (slice.absoluteTop ?? 0) + slice.height);
      } else {
        y += slice.height;
        bottom = math.max(bottom, y);
      }
    }
    return PageContent(
      spineIndex: styles.snapshot.spineIndex,
      pageIndex: index,
      slices: List<PageBlockSlice>.unmodifiable(slices),
      usedHeight: bottom,
      pageHeight: bottom,
      topPadding: 0,
    );
  }

  PageBlockSlice _slice(PageBlock block) => PageBlockSlice(
    block: block,
    startLine: 0,
    endLine: block.layout.lineCount,
    height: block.absolute
        ? block.height
        : block.leadingExtent + block.height + block.trailingExtent,
    leadingExtent: block.absolute ? 0 : block.leadingExtent,
    trailingExtent: block.absolute ? 0 : block.trailingExtent,
    leftInset: block.absolute ? (block.absoluteLeft ?? 0) : block.leftInset,
    overlay: block.absolute,
    absoluteTop: block.absolute ? (block.absoluteTop ?? 0) : null,
  );

  Future<String?> _imageUrl(List<PageBlock> blocks) async {
    for (final block in blocks) {
      await checkpoint();
      if (block.layout.text.isEmpty && block.style?.backgroundImage != null) {
        return block.style!.backgroundImage;
      }
      if (block.inlineImages.isNotEmpty) return block.inlineImages.first.url;
    }
    return null;
  }

  PageGallery _gallery(
    BlockNode node,
    PageContainer container,
    List<PageGalleryFrame> frames,
    double ancestorExtent,
  ) {
    final natural = frames.fold(
      0.0,
      (h, frame) => math.max(h, frame.content.usedHeight),
    );
    final indicator = frames.length > 1 ? PageGallery.indicatorHeight : 0.0;
    final height = _height(container, natural + indicator, ancestorExtent);
    final footer = math.min(indicator, height);
    return PageGallery(
      cfi: node.cfi.serialize(),
      frames: frames,
      left: container.contentLeft,
      width: container.contentWidth,
      height: height,
      scale: natural > 0 ? math.min(1.0, (height - footer) / natural) : 1,
      indicatorExtent: footer,
    );
  }

  double _height(
    PageContainer container,
    double natural,
    double ancestorExtent,
  ) {
    final model = BoxModel.fromStyle(
      container.style,
      containingWidth: styles.snapshot.width,
    );
    final available = math.max(
      0.0,
      styles.snapshot.height -
          ancestorExtent -
          model.verticalInset -
          container.style.margin.vertical,
    );
    return model
        .resolveContentHeight(natural, containingHeight: styles.snapshot.height)
        .clamp(0.0, available);
  }

  ComputedStyle _paintStyle(PageContainer container) {
    final style = container.style;
    final borderBox = style.boxSizing == CssBoxSizing.borderBox;
    final resolved = {
      'width': '${borderBox ? container.width : container.contentWidth}px',
      'margin-left': '${container.left}px',
      'margin-right': '${style.margin.right}px',
      'padding-top': '${style.padding.top}px',
      'padding-right': '${style.padding.right}px',
      'padding-bottom': '${style.padding.bottom}px',
      'padding-left': '${style.padding.left}px',
      'font-size': '${style.fontSize}px',
      // 父样式已携带累计透明度，重建绘制样式时不再次乘作者 opacity。
      'opacity': '1',
      'break-inside': 'avoid',
    };
    return ComputedStyle(
      {...style.values, ...resolved},
      parent: style,
      explicitProperties: {...style.explicitProperties, ...resolved.keys},
      hasExplicitTextColor: style.hasExplicitTextColor,
      containingWidth: styles.snapshot.width,
    );
  }

  TextLayoutResult _layout(PageGallery gallery) => TextLayoutResult(
    text: '',
    lines: [
      LineBox(
        start: 0,
        end: 0,
        top: 0,
        height: gallery.height,
        baseline: gallery.height,
        width: gallery.width,
      ),
    ],
    width: gallery.width,
    height: gallery.height,
    maxWidth: gallery.width,
    runs: const [],
  );
}
