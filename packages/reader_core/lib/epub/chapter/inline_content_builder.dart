import 'dart:math' as math;

import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/css/selector.dart';
import 'package:reader_core/epub/footnote.dart';
import 'package:reader_core/layout/box_model.dart';
import 'package:reader_core/layout/float_occupancy.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/parser/block_builder.dart';
import 'package:reader_core/parser/text_aggregator.dart';
import 'package:reader_core/paint/image_size.dart';
import 'package:reader_core/position/text_cfi_map.dart';
import 'package:reader_core/text/text_offsets.dart';

import 'book_resources.dart';
import 'chapter_style_resolver.dart';
import 'chapter_selectors.dart';
import 'chapter_text_measurer.dart';
import 'image_blocks.dart';
import 'generated_chapter_content.dart';
import 'block_style_helpers.dart';

/// 一章的行内原子盒、图片、注释和文字载荷，不持有会话可变状态。
class InlineContentBuilder {
  InlineContentBuilder(
    this.styles,
    this.content,
    this.measure,
    this._resources,
    this.chapterFootnotes,
  );
  final ChapterStyleResolver styles;
  final GeneratedChapterContent content;
  final ChapterTextMeasurer measure;
  final BookResources _resources;
  String imageUrl(String src) =>
      _resources.imageUrl(styles.snapshot.spineIndex, src);
  Future<ImageIntrinsicSize?> prepareImageIntrinsicSize(String url) =>
      _resources.prepareImageIntrinsicSize(url);
  double get contentWidth => styles.snapshot.width;
  double get contentHeight => styles.snapshot.height;
  final Map<String, FootnoteAnchor> chapterFootnotes;
  ImageIntrinsicSize? _intrinsicSizeOfUrl(String url) =>
      _resources.intrinsicSizeOfUrl(url);

  PageFootnote? footnoteForReference(
    String tag,
    Map<String, String> attributes,
    String visibleText, {
    required int start,
    required int end,
  }) {
    final anchor =
        chapterFootnotes[FootnoteParser.referenceKey(
          tag,
          attributes,
          visibleText,
        )];
    if (anchor == null || anchor.kind == NoteKind.link) {
      return null;
    }
    return PageFootnote(
      start: start,
      end: end,
      label: anchor.label,
      kind: anchor.kind,
      text: anchor.noteText,
      imageUrls: anchor.noteImages,
    );
  }

  InlineBoxVerticalAlign inlineBoxAlignOf(CssVerticalAlign align) =>
      switch (align) {
        CssVerticalAlign.top => InlineBoxVerticalAlign.top,
        CssVerticalAlign.bottom => InlineBoxVerticalAlign.bottom,
        CssVerticalAlign.middle => InlineBoxVerticalAlign.middle,
        _ => InlineBoxVerticalAlign.baseline,
      };

  bool inlineDescendantOf(InlineMark child, InlineMark parent) =>
      parent.chain.isNotEmpty &&
      child.chain.length > parent.chain.length &&
      child.start >= parent.start &&
      child.end <= parent.end &&
      identical(
        child.chain[parent.chain.length - 1].attributes,
        parent.chain.last.attributes,
      );

  List<InlineBoxSpec> appendInlineBox(
    List<InlineBoxSpec> existingBoxes,
    InlineFloatExtraction extracted,
  ) => [
    for (final existing in existingBoxes)
      existing.atOffset(extracted.remapOffset(existing.offset)),
    if (extracted.inlineBox != null) extracted.inlineBox!,
  ];

  PageBlock inlineImagePayload(
    ComputedStyle imageStyle,
    List<SelectorElement> chain,
    String url,
    ImageDisplaySize size,
  ) {
    final fit = content.objectFitBackground(
      chain,
      _intrinsicSizeOfUrl(url),
      boxWidth: size.width,
      boxHeight: size.height,
    );
    final payloadStyle = ComputedStyle({
      ...imageStyle.values,
      'background-image': 'url("$url")',
      'background-size':
          content.rawDeclarationsFor(chain).containsKey('object-fit')
          ? fit.size
          : '100% 100%',
      'background-position': fit.position,
      'background-repeat': 'no-repeat',
      'background-origin': 'content-box',
    });
    return PageBlock(
      layout: TextLayoutResult(
        text: '',
        lines: const [],
        width: size.width,
        height: size.height,
        maxWidth: size.width,
      ),
      style: payloadStyle,
      startCfi: chain.isEmpty
          ? null
          : styles.selectorIndex.imageCfiForAttributes(chain.last.attributes),
    );
  }

  InlineBoxSpec inlineImageBox(
    InlineImageSpec image,
    ComputedStyle imageStyle,
    List<SelectorElement> chain,
    double availableWidth,
  ) {
    final size = measure.inlineImageSize(
      imageStyle,
      _intrinsicSizeOfUrl(image.url),
      availableWidth,
    );
    return InlineBoxSpec(
      offset: image.offset,
      replacesPlaceholder: true,
      width: size.width,
      height: size.height,
      verticalAlign: inlineBoxAlignOf(imageStyle.verticalAlign),
      marginLeft: imageStyle.margin.left,
      marginRight: imageStyle.margin.right,
      marginTop: imageStyle.margin.top,
      marginBottom: imageStyle.margin.bottom,
      contentBaseline: size.height,
      payload: inlineImagePayload(imageStyle, chain, image.url, size),
    );
  }

  Future<InlineFloatExtraction?> extractInlineFloat({
    required String text,
    required List<InlineMark> marks,
    required List<InlineImageMark> images,
    required InlineStyleContext context,
    TextCfiMap? textCfis,
  }) async {
    if (marks.isEmpty) return null;
    for (final mark in marks) {
      await measure.budget.checkpoint();
      final candidate = await _atomicCandidate(mark, marks, context);
      if (candidate == null) continue;
      final atom = await _atomicText(
        text,
        marks,
        candidate,
        context,
        textCfis: textCfis,
      );
      if (atom != null) return _extractAtomicText(text, marks, atom, context);
    }
    return _extractImageFloat(text, marks, images, context);
  }

  Future<ComputedStyle> _inlineStyle(
    InlineMark mark,
    InlineStyleContext context,
  ) => styles.inlineMarkStyle(
    mark,
    context,
    checkpoint: measure.budget.checkpoint,
  );

  Future<_AtomicCandidate?> _atomicCandidate(
    InlineMark mark,
    List<InlineMark> marks,
    InlineStyleContext context,
  ) async {
    if (mark.chain.isEmpty || mark.end < mark.start) return null;
    final tag = mark.tag.toLowerCase();
    final objectImage =
        tag == 'object' &&
        (mark.chain.last.attributes['data']?.trim().isNotEmpty ?? false);
    if (tag == 'img' || tag == 'image' || objectImage) return null;
    final style = await _inlineStyle(mark, context);
    final side = floatSideOfStyle(style);
    final inlineBlock = side == null && style.display == CssDisplay.inlineBlock;
    if (side == null && !inlineBlock) return null;
    if (await _hasAtomicAncestor(mark, marks, context)) return null;
    return _AtomicCandidate(mark, style, side, inlineBlock);
  }

  Future<bool> _hasAtomicAncestor(
    InlineMark mark,
    List<InlineMark> marks,
    InlineStyleContext context,
  ) async {
    for (final parent in marks) {
      await measure.budget.checkpoint();
      if (!inlineDescendantOf(mark, parent)) continue;
      if ((await _inlineStyle(parent, context)).display ==
          CssDisplay.inlineBlock) {
        return true;
      }
    }
    return false;
  }

  Future<_AtomicText?> _atomicText(
    String text,
    List<InlineMark> marks,
    _AtomicCandidate candidate,
    InlineStyleContext context, {
    TextCfiMap? textCfis,
  }) async {
    final mark = candidate.mark;
    final raw = text.substring(mark.start, mark.end);
    final children = <InlineMark>[];
    for (final child in marks) {
      await measure.budget.checkpoint();
      if (inlineDescendantOf(child, mark)) children.add(child);
    }
    final leftTrimmed = await _hasBoxAt(children, mark.start, false, context)
        ? raw
        : raw.trimLeft();
    final content = await _hasBoxAt(children, mark.end, true, context)
        ? leftTrimmed
        : leftTrimmed.trimRight();
    if (content.isEmpty && !candidate.inlineBlock) return null;
    final start = mark.start + raw.length - leftTrimmed.length;
    final contentMarks = await _atomicMarks(children, start, content.length);
    return _AtomicText(candidate, raw, content, contentMarks, (
      model: BoxModel.fromStyle(
        candidate.style,
        containingWidth: context.width,
      ),
      textCfis: textCfis?.slice(start, start + content.length),
    ));
  }

  Future<bool> _hasBoxAt(
    List<InlineMark> children,
    int boundary,
    bool end,
    InlineStyleContext context,
  ) async {
    for (final child in children) {
      await measure.budget.checkpoint();
      if ((end ? child.end : child.start) != boundary) continue;
      if ((await _inlineStyle(child, context)).display ==
          CssDisplay.inlineBlock) {
        return true;
      }
    }
    return false;
  }

  Future<List<InlineMark>> _atomicMarks(
    List<InlineMark> children,
    int start,
    int length,
  ) async {
    final marks = <InlineMark>[];
    for (final child in children) {
      await measure.budget.checkpoint();
      marks.add(
        InlineMark(
          start: (child.start - start).clamp(0, length),
          end: (child.end - start).clamp(0, length),
          tag: child.tag,
          classes: child.classes,
          chain: child.chain,
        ),
      );
    }
    return marks;
  }

  Future<InlineFloatExtraction> _extractAtomicText(
    String text,
    List<InlineMark> marks,
    _AtomicText atom,
    InlineStyleContext context,
  ) async {
    final payload = await _atomicPayload(atom, context);
    final removal = _atomicRemoval(text, atom.candidate);
    final remaining = await _remainingAtomicMarks(
      marks,
      atom.candidate.mark,
      removal,
    );
    final mark = atom.candidate.mark;
    final footnote = atom.candidate.inlineBlock
        ? footnoteForReference(
            mark.tag,
            mark.chain.isEmpty ? const {} : mark.chain.last.attributes,
            atom.raw,
            start: removal.start,
            end: removal.start + 1,
          )
        : null;
    return InlineFloatExtraction(
      text: removal.text,
      marks: remaining,
      block: payload.block,
      inlineBox: payload.box?.atOffset(removal.start),
      footnote: footnote,
      remapOffset: removal.remap,
      removeStart: removal.start,
      removeEnd: removal.end,
    );
  }

  Future<_AtomicPayload> _atomicPayload(
    _AtomicText atom,
    InlineStyleContext context,
  ) async {
    final measured = await _measureAtomicContent(atom, context);
    final layout = measured.layout;
    final candidate = atom.candidate;
    if (candidate.inlineBlock) {
      return _AtomicPayload(
        null,
        await _atomicInlineBox(atom, layout, measured.width),
      );
    }
    final block = measure.floatedTextBlock(
      layout: layout,
      style: candidate.style,
      side: candidate.side!,
      spaceBefore: candidate.style.margin.top,
      spaceAfter: candidate.style.margin.bottom,
      containingLeft: _containingLeft(context),
      containingWidth: context.width,
      startCfi: atom.textCfis?.cfiAt(0),
      textCfis: await atom.textCfis?.transformedAsync(
        layout.inputOffsets,
        checkpoint: measure.budget.checkpoint,
      ),
    );
    return _AtomicPayload(block, null);
  }

  Future<({TextLayoutResult layout, double width})> _measureAtomicContent(
    _AtomicText atom,
    InlineStyleContext context,
  ) async {
    var width = math.max(
      atom.text.isEmpty ? 0.0 : 1.0,
      atom.model.resolveContentWidth(context.width),
    );
    var layout = await _layoutAtomicContent(
      atom,
      _atomicContext(atom, context, width),
    );
    if (atom.model.contentWidth == null) {
      width = _atomicPreferredWidth(atom, layout, context.width);
      // 自动宽浮动和行内块都按最终盒宽重排，行内对齐偏移不能沿用宽盒。
      layout = await _layoutAtomicContent(
        atom,
        _atomicContext(atom, context, width),
      );
    }
    return (layout: layout, width: width);
  }

  InlineStyleContext _atomicContext(
    _AtomicText atom,
    InlineStyleContext outer,
    double width,
  ) => (
    ancestors: styles.inlineMarkChain(atom.candidate.mark, outer.ancestors),
    style: atom.candidate.style,
    width: width,
    readerFontFamily: outer.readerFontFamily,
  );

  double _atomicPreferredWidth(
    _AtomicText atom,
    TextLayoutResult layout,
    double availableWidth,
  ) {
    final model = atom.model;
    final preferred =
        layout.width + model.horizontalInset + model.margin.horizontal;
    return math.max(
      atom.text.isEmpty ? 0.0 : 1.0,
      model.resolveContentWidth(
        atom.candidate.style.whiteSpace == CssWhiteSpace.nowrap
            ? preferred
            : math.min(availableWidth, preferred),
      ),
    );
  }

  Future<TextLayoutResult> _layoutAtomicContent(
    _AtomicText atom,
    InlineStyleContext context,
  ) async {
    final flow = await _extractFlowBoxes(
      atom.text,
      atom.marks,
      context,
      textCfis: atom.textCfis,
    );
    final runs = await styles.resolveInlineRuns(
      flow.marks,
      context,
      checkpoint: measure.budget.checkpoint,
    );
    if (flow.boxes.isEmpty && flow.text.isEmpty) {
      return TextLayoutResult(
        text: '',
        lines: const [],
        width: 0,
        height: 0,
        maxWidth: context.width,
        inputOffsets: flow.inputOffsets,
      );
    }
    final layout = await measure.layout(
      text: flow.text,
      style: context.style,
      maxWidth: context.width,
      runs: runs,
      inlineBoxes: flow.boxes,
    );
    return layout.withInputOffsets(
      composeTextOffsets(flow.inputOffsets, layout.inputOffsets),
    );
  }

  Future<_InlineBoxFlow> _extractFlowBoxes(
    String text,
    List<InlineMark> marks,
    InlineStyleContext context, {
    TextCfiMap? textCfis,
  }) async {
    var remainingText = text;
    var remainingMarks = marks;
    var boxes = <InlineBoxSpec>[];
    TextOffsetMap? inputOffsets;
    for (var index = 0; index < marks.length; index++) {
      await measure.budget.checkpoint();
      final extracted = await extractInlineFloat(
        text: remainingText,
        marks: remainingMarks,
        images: const [],
        context: context,
        textCfis: textCfis,
      );
      // 内盒与格内浮动沿用原文字近似，不丢弃脱流内容。
      if (extracted == null || extracted.block != null) break;
      final offsets = TextOffsetMap.removal(
        remainingText.length,
        extracted.removeStart,
        extracted.removeEnd,
      );
      inputOffsets = composeTextOffsets(inputOffsets, offsets);
      textCfis = await textCfis?.transformedAsync(
        offsets,
        checkpoint: measure.budget.checkpoint,
      );
      remainingText = extracted.text;
      remainingMarks = extracted.marks;
      boxes = appendInlineBox(boxes, extracted);
    }
    return _InlineBoxFlow(remainingText, remainingMarks, boxes, inputOffsets);
  }

  Future<InlineBoxSpec> _atomicInlineBox(
    _AtomicText atom,
    TextLayoutResult layout,
    double width,
  ) async {
    final model = atom.model;
    final style = atom.candidate.style;
    final height = model.resolveContentHeight(
      layout.height,
      containingHeight: contentHeight,
    );
    return InlineBoxSpec(
      offset: atom.candidate.mark.start,
      width: model.borderBoxWidth(width),
      height: model.borderBoxHeight(height),
      verticalAlign: inlineBoxAlignOf(style.verticalAlign),
      marginLeft: style.margin.left,
      marginRight: style.margin.right,
      marginTop: style.margin.top,
      marginBottom: style.margin.bottom,
      contentHeight: layout.height,
      contentBaseline: _atomicBaseline(atom, layout, height),
      payload: PageBlock.styled(
        layout: layout,
        style: style,
        containingWidth: contentWidth,
        startCfi: atom.textCfis?.cfiAt(0),
        textCfis: await atom.textCfis?.transformedAsync(
          layout.inputOffsets,
          checkpoint: measure.budget.checkpoint,
        ),
      ),
    );
  }

  double _atomicBaseline(
    _AtomicText atom,
    TextLayoutResult layout,
    double height,
  ) {
    final model = atom.model;
    return layout.lines.isEmpty ||
            atom.candidate.style.overflow != CssOverflow.visible
        ? model.borderBoxHeight(height) + model.margin.bottom
        : model.padding.top + model.borders.top + layout.lines.last.baseline;
  }

  static _TextRemoval _atomicRemoval(String text, _AtomicCandidate candidate) {
    var start = candidate.mark.start;
    var end = candidate.mark.end;
    // 浮动摘掉邻接一个空格；行内块保留边界空白，交给行排版折叠。
    if (candidate.side != null) {
      if (end < text.length && text[end] == ' ') {
        end += 1;
      } else if (start > 0 && text[start - 1] == ' ') {
        start -= 1;
      }
    }
    return _TextRemoval(text, start, end);
  }

  Future<List<InlineMark>> _remainingAtomicMarks(
    List<InlineMark> marks,
    InlineMark extracted,
    _TextRemoval removal,
  ) async {
    final remaining = <InlineMark>[];
    for (final other in marks) {
      await measure.budget.checkpoint();
      if (identical(other, extracted) || inlineDescendantOf(other, extracted)) {
        continue;
      }
      if (other.end <= removal.start ||
          other.start >= removal.end ||
          inlineDescendantOf(extracted, other)) {
        remaining.add(_remappedMark(other, removal));
      }
    }
    return remaining;
  }

  static InlineMark _remappedMark(InlineMark mark, _TextRemoval removal) =>
      InlineMark(
        start: removal.remap(mark.start),
        end: removal.remap(mark.end),
        tag: mark.tag,
        classes: mark.classes,
        chain: mark.chain,
      );

  Future<InlineFloatExtraction?> _extractImageFloat(
    String text,
    List<InlineMark> marks,
    List<InlineImageMark> images,
    InlineStyleContext context,
  ) async {
    for (final image in images) {
      await measure.budget.checkpoint();
      final attributes = image.node.attributes;
      final src =
          attributes['src'] ??
          attributes['xlink:href'] ??
          attributes['href'] ??
          attributes['data'];
      if (src == null || src.isEmpty || image.offset >= text.length) continue;
      final chain = _floatImageChain(image, context);
      final style = styles.chainStyle(chain);
      final side = floatSideOfStyle(style);
      if (side == null) continue;
      await prepareImageIntrinsicSize(imageUrl(src));
      final block = _imageFloatBlock(image, style, context, side);
      final removal = _TextRemoval(text, image.offset, image.offset + 1);
      final remaining = await _remainingImageMarks(marks, removal);
      return InlineFloatExtraction(
        text: removal.text,
        marks: remaining,
        block: block,
        inlineBox: null,
        remapOffset: removal.remap,
        removeStart: removal.start,
        removeEnd: removal.end,
      );
    }
    return null;
  }

  List<SelectorElement> _floatImageChain(
    InlineImageMark image,
    InlineStyleContext context,
  ) => [
    ...context.ancestors,
    ChapterNodeView(image.node.tag, image.node.attributes, const []),
  ];

  PageBlock _imageFloatBlock(
    InlineImageMark image,
    ComputedStyle imageStyle,
    InlineStyleContext context,
    FloatSide side,
  ) {
    final url = imageUrl(
      image.node.attributes['src'] ??
          image.node.attributes['xlink:href'] ??
          image.node.attributes['href'] ??
          image.node.attributes['data']!,
    );
    final size = _floatImageSize(image, imageStyle, url);
    final objectFit = content.objectFitBackground(
      _floatImageChain(image, context),
      _intrinsicSizeOfUrl(url),
      boxWidth: size.$1,
      boxHeight: size.$2,
    );
    final style = ComputedStyle({
      ...imageStyle.values,
      'background-image': 'url("$url")',
      'background-size': objectFit.size,
      'background-position': objectFit.position,
      'background-repeat': 'no-repeat',
    });
    return measure.floatedTextBlock(
      layout: _floatImageLayout(size),
      style: style,
      side: side,
      startCfi: styles.selectorIndex.imageCfiOf(image.node),
      spaceBefore: style.margin.top,
      spaceAfter: style.margin.bottom,
      containingLeft: _containingLeft(context),
      containingWidth: context.width,
    );
  }

  (double, double) _floatImageSize(
    InlineImageMark image,
    ComputedStyle style,
    String url,
  ) => resolveImageDisplaySize(
    image.node.attributes,
    _intrinsicSizeOfUrl(url),
    contentWidth,
    contentHeight,
    cssWidth: style.width?.resolve(contentWidth),
    cssHeight: style.height?.resolve(contentHeight),
    cssMaxWidth: style.maxWidth?.resolve(contentWidth),
    cssMaxHeight: style.maxHeight?.resolve(contentHeight),
    aspectRatio: style.aspectRatio,
  );

  static TextLayoutResult _floatImageLayout((double, double) size) =>
      TextLayoutResult(
        text: '',
        lines: [
          LineBox(
            start: 0,
            end: 0,
            top: 0,
            height: size.$2,
            baseline: size.$2,
            width: size.$1,
          ),
        ],
        width: size.$1,
        height: size.$2,
        maxWidth: size.$1,
        runs: const [],
      );

  static double _containingLeft(InlineStyleContext context) =>
      context.style.margin.left +
      context.style.borders.left.width +
      context.style.padding.left;

  Future<List<InlineMark>> _remainingImageMarks(
    List<InlineMark> marks,
    _TextRemoval removal,
  ) async {
    final remaining = <InlineMark>[];
    for (final mark in marks) {
      await measure.budget.checkpoint();
      if (mark.end <= removal.start || mark.start >= removal.end) {
        remaining.add(_remappedMark(mark, removal));
      }
    }
    return remaining;
  }

  /// 保持原五参数入口兼容，图片作为可选载荷参与同一格的测量。
  Future<TextLayoutResult> layoutCellContent(
    String text,
    List<InlineMark> marks,
    List<SelectorElement> ancestors,
    ComputedStyle cellStyle,
    double width, {
    List<InlineImageMark> images = const [],
    TextCfiMap? textCfis,
  }) => _layoutCellFlow(
    (text: text, marks: marks, images: images, textCfis: textCfis),
    (
      ancestors: ancestors,
      style: cellStyle,
      width: width,
      readerFontFamily: null,
    ),
  );

  Future<TextLayoutResult> _layoutCellFlow(
    _CellInlineContent content,
    InlineStyleContext context,
  ) async {
    final flow = content.images.isEmpty
        ? await _extractFlowBoxes(
            content.text,
            content.marks,
            context,
            textCfis: content.textCfis,
          )
        : await _extractCellImageFlow(content, context);
    final runs = await styles.resolveInlineRuns(
      flow.marks,
      context,
      checkpoint: measure.budget.checkpoint,
    );
    var layout = await measure.layout(
      text: flow.text,
      style: context.style,
      maxWidth: context.width,
      runs: runs,
      inlineBoxes: flow.boxes,
      preserveContentWidth: true,
    );
    layout = layout.withInputOffsets(
      composeTextOffsets(flow.inputOffsets, layout.inputOffsets),
    );
    return flow.boxes.any((box) => box is _CellBlockBox)
        ? _positionCellBlockBoxes(layout)
        : layout;
  }

  /// 独占行的块盒按包含块定位；正文对齐与缩进只影响其内的行内容。
  Future<TextLayoutResult> _positionCellBlockBoxes(
    TextLayoutResult layout,
  ) async {
    final lines = <LineBox>[];
    var changed = false;
    for (final line in layout.lines) {
      await measure.budget.checkpoint();
      if (!line.inlineBoxes.any((box) => box.spec is _CellBlockBox)) {
        lines.add(line);
        continue;
      }
      changed = true;
      lines.add(
        line.copyWith(
          offsetX: 0,
          indent: 0,
          justifyExtra: 0,
          inlineBoxes: [
            for (final box in line.inlineBoxes) _cellBlockPlacement(box),
          ],
        ),
      );
    }
    if (!changed) return layout;
    return _cellLayoutWithLines(layout, lines);
  }

  static TextLayoutResult _cellLayoutWithLines(
    TextLayoutResult layout,
    List<LineBox> lines,
  ) => TextLayoutResult(
    text: layout.text,
    lines: List<LineBox>.unmodifiable(lines),
    width: layout.width,
    height: layout.height,
    maxWidth: layout.maxWidth,
    runs: layout.runs,
    isRtl: layout.isRtl,
    writingMode: layout.writingMode,
    plainTextLayout: layout.plainTextLayout,
    firstLineStyle: layout.firstLineStyle,
    firstLineRuns: layout.firstLineRuns,
    sourceRuns: layout.sourceRuns,
    inputOffsets: layout.inputOffsets,
  );

  static InlineBoxPlacement _cellBlockPlacement(InlineBoxPlacement placement) {
    final spec = placement.spec;
    if (spec is! _CellBlockBox) return placement;
    return InlineBoxPlacement(
      offset: placement.offset,
      left: spec.blockLeft,
      width: placement.width,
      height: placement.height,
      ascent: placement.ascent,
      descent: placement.descent,
      spec: spec,
      vertical: placement.vertical,
    );
  }

  /// 图片跟随原子盒摘除同步重映射，含图块递归保留自身样式与图注。
  Future<_InlineBoxFlow> _extractCellImageFlow(
    _CellInlineContent initial,
    InlineStyleContext context,
  ) async {
    var remaining = initial;
    var boxes = <InlineBoxSpec>[];
    TextOffsetMap? inputOffsets;
    for (var guard = 0; guard < initial.marks.length; guard++) {
      await measure.budget.checkpoint();
      final extracted = await _extractCellAtomic(remaining, context);
      if (extracted == null) break;
      final offsets = TextOffsetMap.removal(
        remaining.text.length,
        extracted.removeStart,
        extracted.removeEnd,
      );
      inputOffsets = composeTextOffsets(inputOffsets, offsets);
      remaining = (
        text: extracted.text,
        marks: extracted.marks,
        images: await _remapCellImages(remaining.images, extracted),
        textCfis: await remaining.textCfis?.transformedAsync(
          offsets,
          checkpoint: measure.budget.checkpoint,
        ),
      );
      boxes = appendInlineBox(boxes, extracted);
    }
    for (final image in remaining.images) {
      await measure.budget.checkpoint();
      final box = await _cellImageBox(image, remaining.marks, context);
      if (box != null) boxes.add(box);
    }
    return _InlineBoxFlow(remaining.text, remaining.marks, boxes, inputOffsets);
  }

  Future<InlineFloatExtraction?> _extractCellAtomic(
    _CellInlineContent content,
    InlineStyleContext context,
  ) async {
    for (final mark in content.marks) {
      await measure.budget.checkpoint();
      if (await _hasCellImageAncestor(mark, content, context)) continue;
      final candidate = await _cellAtomicCandidate(mark, content, context);
      if (candidate == null) continue;
      // 格内浮动保留既有文字近似，不把脱流内容摘掉。
      if (candidate.side != null) return null;
      final atom = await _atomicText(
        content.text,
        content.marks,
        candidate,
        context,
        textCfis: content.textCfis,
      );
      if (atom == null) continue;
      final images = await _cellAtomicImages(content.images, atom);
      if (images.isEmpty) {
        return _extractAtomicText(content.text, content.marks, atom, context);
      }
      return _extractCellImageAtomic(content, atom, images, context);
    }
    return null;
  }

  Future<InlineFloatExtraction> _extractCellImageAtomic(
    _CellInlineContent content,
    _AtomicText atom,
    List<InlineImageMark> images,
    InlineStyleContext context,
  ) async {
    final box = await _cellImageAtomicBox(atom, images, context);
    final removal = _cellImageAtomicRemoval(content.text, atom.candidate);
    final mark = atom.candidate.mark;
    return InlineFloatExtraction(
      text: removal.text,
      marks: await _remainingAtomicMarks(content.marks, mark, removal),
      inlineBox: box.atOffset(removal.start),
      remapOffset: removal.remap,
      removeStart: removal.start,
      removeEnd: removal.end,
      footnote: footnoteForReference(
        mark.tag,
        mark.chain.last.attributes,
        atom.raw,
        start: removal.start,
        end: removal.start + 1,
      ),
    );
  }

  static _TextRemoval _cellImageAtomicRemoval(
    String text,
    _AtomicCandidate candidate,
  ) {
    final start = candidate.mark.start;
    // 块标记包含前置分隔符；摘取载荷时保留它，避免与前文共占一行。
    if (candidate.style.display == CssDisplay.block &&
        start > 0 &&
        text[start] == '\n') {
      return _TextRemoval(text, start + 1, candidate.mark.end);
    }
    return _atomicRemoval(text, candidate);
  }

  Future<_AtomicCandidate?> _cellAtomicCandidate(
    InlineMark mark,
    _CellInlineContent content,
    InlineStyleContext context,
  ) async {
    final candidate = await _atomicCandidate(mark, content.marks, context);
    if (candidate != null) return candidate;
    if (mark.chain.isEmpty) return null;
    final style = await _inlineStyle(mark, context);
    return _cellImageBlock(mark, style, content.images)
        ? _AtomicCandidate(mark, style, null, true)
        : null;
  }

  bool _cellImageBlock(
    InlineMark mark,
    ComputedStyle style,
    List<InlineImageMark> images,
  ) =>
      style.display == CssDisplay.block &&
      !const {'img', 'image', 'object'}.contains(mark.tag) &&
      (BlockBuilder.displayFor(mark.tag) == DisplayMode.block ||
          style.values['display']?.trim() == 'block') &&
      images.any(
        (image) => image.offset >= mark.start && image.offset < mark.end,
      );

  Future<bool> _hasCellImageAncestor(
    InlineMark mark,
    _CellInlineContent content,
    InlineStyleContext context,
  ) async {
    for (final parent in content.marks) {
      await measure.budget.checkpoint();
      if (!inlineDescendantOf(mark, parent)) continue;
      final style = await _inlineStyle(parent, context);
      if (style.display == CssDisplay.inlineBlock ||
          _cellImageBlock(parent, style, content.images)) {
        return true;
      }
    }
    return false;
  }

  Future<InlineBoxSpec> _cellImageAtomicBox(
    _AtomicText atom,
    List<InlineImageMark> images,
    InlineStyleContext context,
  ) async {
    var width = math.max(1.0, atom.model.resolveContentWidth(context.width));
    final content = (
      text: atom.text,
      marks: atom.marks,
      images: images,
      textCfis: atom.textCfis,
    );
    var layout = await _layoutCellFlow(
      content,
      _atomicContext(atom, context, width),
    );
    if (atom.candidate.style.display == CssDisplay.inlineBlock &&
        atom.model.contentWidth == null) {
      width = _atomicPreferredWidth(atom, layout, context.width);
      layout = await _layoutCellFlow(
        content,
        _atomicContext(atom, context, width),
      );
    }
    final box = await _atomicInlineBox(atom, layout, width);
    if (!ChapterTextMeasurer.isOrdinaryHorizontalBlock(atom.candidate.style)) {
      return box;
    }
    // CSS 2.2 §10.3.3：定宽盒约束由包含块方向决定被调整的物理外边距。
    final left = context.style.isRtl
        ? context.width - box.width - box.marginRight
        : box.marginLeft;
    return _CellBlockBox(box, left);
  }

  Future<List<InlineImageMark>> _cellAtomicImages(
    List<InlineImageMark> images,
    _AtomicText atom,
  ) async {
    // 原子文本只裁掉边界空白；内容子串的首位置就是占位重映射基准。
    final start = atom.candidate.mark.start + atom.raw.indexOf(atom.text);
    final result = <InlineImageMark>[];
    for (final image in images) {
      await measure.budget.checkpoint();
      if (image.offset < start || image.offset >= start + atom.text.length) {
        continue;
      }
      result.add(
        InlineImageMark(offset: image.offset - start, node: image.node),
      );
    }
    return result;
  }

  Future<List<InlineImageMark>> _remapCellImages(
    List<InlineImageMark> images,
    InlineFloatExtraction extracted,
  ) async {
    final result = <InlineImageMark>[];
    for (final image in images) {
      await measure.budget.checkpoint();
      if (extracted.removed(image.offset)) continue;
      result.add(
        InlineImageMark(
          offset: extracted.remapOffset(image.offset),
          node: image.node,
        ),
      );
    }
    return result;
  }

  Future<InlineBoxSpec?> _cellImageBox(
    InlineImageMark image,
    List<InlineMark> marks,
    InlineStyleContext context,
  ) async {
    final attributes = image.node.attributes;
    final src =
        attributes['src'] ??
        attributes['xlink:href'] ??
        attributes['href'] ??
        attributes['data'];
    if (src == null || src.isEmpty) return null;
    final source = _cellImageMark(image, marks);
    final chain = styles.inlineMarkChain(source, context.ancestors);
    final imageStyle = await _inlineStyle(source, context);
    await prepareImageIntrinsicSize(imageUrl(src));
    return inlineImageBox(
      InlineImageSpec(offset: image.offset, url: imageUrl(src)),
      imageStyle,
      chain,
      context.width,
    );
  }

  InlineMark _cellImageMark(InlineImageMark image, List<InlineMark> marks) {
    final source = styles.selectorIndex.chainOf(image.node);
    final marked = marks
        .where(
          (mark) => mark.start == image.offset && mark.tag == image.node.tag,
        )
        .firstOrNull;
    return source == null && marked != null
        ? marked
        : InlineMark(
            start: image.offset,
            end: image.offset + 1,
            tag: image.node.tag,
            classes: const [],
            chain: [
              if (source == null)
                MarkSubject(
                  tag: image.node.tag,
                  attributes: image.node.attributes,
                  classes: const {},
                ),
              for (final view in source ?? const <SelectorElement>[])
                MarkSubject(
                  tag: view.tag,
                  attributes: view.attributes,
                  classes: const {},
                ),
            ],
          );
  }
}

typedef _CellInlineContent = ({
  String text,
  List<InlineMark> marks,
  List<InlineImageMark> images,
  TextCfiMap? textCfis,
});

/// 格内块盒沿用真实尺寸与级联解算的 auto 外边距，重映射时保留块标记。
class _CellBlockBox extends InlineBoxSpec {
  _CellBlockBox(InlineBoxSpec box, this.blockLeft)
    : super(
        offset: box.offset,
        width: box.width,
        height: box.height,
        verticalAlign: box.verticalAlign,
        marginTop: box.marginTop,
        marginBottom: box.marginBottom,
        marginLeft: box.marginLeft,
        marginRight: box.marginRight,
        baselineOffset: box.baselineOffset,
        contentHeight: box.contentHeight,
        contentBaseline: box.contentBaseline,
        replacesPlaceholder: box.replacesPlaceholder,
        payload: box.payload,
      );

  final double blockLeft;

  @override
  InlineBoxSpec atOffset(int offset) =>
      _CellBlockBox(super.atOffset(offset), blockLeft);
}

/// 行内浮动提取结果（W17）：摘出的浮动块 + 剩余文本与偏移重映射。
class InlineFloatExtraction {
  const InlineFloatExtraction({
    required this.text,
    required this.marks,
    required this.remapOffset,
    required this.removeStart,
    required this.removeEnd,
    this.block,
    this.inlineBox,
    this.footnote,
  });

  /// 摘掉浮动内容后的段落文本。
  final String text;

  /// 重映射后的行内标记（用于重新生成 runs）。
  final List<InlineMark> marks;

  /// 摘出的浮动块（行内浮动）。
  final PageBlock? block;

  /// 摘出的行内盒子（`display: inline-block`）：交给行排版按行内盒放置。
  final InlineBoxSpec? inlineBox;

  /// 行内盒本身作为注释入口时的弹窗数据。
  final PageFootnote? footnote;

  /// 旧偏移 → 新偏移。
  final int Function(int offset) remapOffset;

  /// 被摘掉的区间（旧坐标，半开）。
  final int removeStart;
  final int removeEnd;

  /// 偏移是否落在被摘掉的区间内。
  bool removed(int offset) => offset >= removeStart && offset < removeEnd;
}

/// 候选标记的级联结果与原子类型；不和其他段落共享。
class _AtomicCandidate {
  const _AtomicCandidate(this.mark, this.style, this.side, this.inlineBlock);
  final InlineMark mark;
  final ComputedStyle style;
  final FloatSide? side;
  final bool inlineBlock;
}

class _AtomicText {
  const _AtomicText(
    this.candidate,
    this.raw,
    this.text,
    this.marks,
    this.coordinates,
  );
  final _AtomicCandidate candidate;
  final String raw;
  final String text;
  final List<InlineMark> marks;
  final ({BoxModel model, TextCfiMap? textCfis}) coordinates;
  BoxModel get model => coordinates.model;
  TextCfiMap? get textCfis => coordinates.textCfis;
}

class _AtomicPayload {
  const _AtomicPayload(this.block, this.box);
  final PageBlock? block;
  final InlineBoxSpec? box;
}

class _InlineBoxFlow {
  const _InlineBoxFlow(this.text, this.marks, this.boxes, this.inputOffsets);
  final String text;
  final List<InlineMark> marks;
  final List<InlineBoxSpec> boxes;
  final TextOffsetMap? inputOffsets;
}

class _TextRemoval {
  _TextRemoval(String original, this.start, this.end)
    : text = original.substring(0, start) + original.substring(end);
  final String text;
  final int start;
  final int end;
  int remap(int offset) => offset <= start
      ? offset
      : offset >= end
      ? offset - (end - start)
      : start;
}
