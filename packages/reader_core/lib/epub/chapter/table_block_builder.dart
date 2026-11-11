import 'dart:math' as math;
import 'dart:ui' show Rect;

import 'package:reader_core/api.dart' show EpubNode, TextBlockNode;
import 'package:reader_core/css/cascade.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/css/parser.dart';
import 'package:reader_core/css/selector.dart';
import 'package:reader_core/layout/box_model.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/table_layout.dart';
import 'package:reader_core/parser/block_builder.dart';
import 'package:reader_core/parser/text_aggregator.dart';

import 'chapter_flow.dart';
import 'chapter_layout_job.dart';
import 'chapter_selectors.dart';
import 'chapter_style_resolver.dart';
import 'chapter_styles.dart';
import 'inline_content_builder.dart';

/// 单次表格的构建入口；全部阶段成功后才向章节流追加最终块。
class TableBlockBuilder {
  TableBlockBuilder(this.styles, this.inline, this.flow);

  final ChapterStyleResolver styles;
  final InlineContentBuilder inline;
  final ChapterFlow flow;

  Future<void> build(
    BlockNode tableNode,
    List<SelectorElement> ancestors,
  ) async {
    inline.measure.budget.check();
    final table = _TableDescription.resolve(styles, tableNode, ancestors);
    final blocks = await _TableBuild(styles, inline, table).build();
    inline.measure.budget.check();
    flow.blocks.addAll(blocks);
  }
}

/// 样式副作用在首次级联后立即保存，后续格或标题级联不会覆盖表格属性。
class _TableDescription {
  _TableDescription.resolve(
    this.styles,
    this.node,
    List<SelectorElement> ancestors,
  ) {
    chain = List<SelectorElement>.unmodifiable([
      ...ancestors,
      ChapterNodeView('table', node.attributes, const []),
    ]);
    rawStyle = styles.chainStyle(chain);
    style = styles.styleForChain(chain);
    availableWidth = math.max(
      1.0,
      styles.snapshot.width -
          style.margin.horizontal +
          (rawStyle.marginLeftIsAuto ? rawStyle.margin.left : 0) +
          (rawStyle.marginRightIsAuto ? rawStyle.margin.right : 0),
    );
    spacingHint = _hasAuthorSpacing()
        ? null
        : _htmlCellSpacing(node.attributes['cellspacing']);
    borderedContainer = styles.containerBorderedForLastChain;
    opacity = styles.effectiveOpacityForLastChain;
  }

  final ChapterStyleResolver styles;
  final BlockNode node;
  late final List<SelectorElement> chain;
  late final ComputedStyle rawStyle;
  late final ComputedStyle style;
  late final double availableWidth;
  late final double? spacingHint;
  late final bool borderedContainer;
  late final double opacity;

  bool get collapse => style.borderCollapse == CssBorderCollapse.collapse;
  double get spacingX => collapse ? 0 : spacingHint ?? style.borderSpacing.left;
  double get spacingY => collapse ? 0 : spacingHint ?? style.borderSpacing.top;

  static double? _htmlCellSpacing(String? value) {
    final spacing = double.tryParse(
      value?.trim().replaceFirst(RegExp(r'px$'), '') ?? '',
    );
    return spacing != null && spacing.isFinite && spacing >= 0 ? spacing : null;
  }

  bool _hasAuthorSpacing() {
    bool declaresSpacing(CssDeclaration declaration) =>
        declaration.property == 'border-spacing' &&
        ComputedStyle.isValidDeclaration(
          declaration.property,
          declaration.value,
        );
    if (inlineDeclarationsOf(node.attributes['style']).any(declaresSpacing)) {
      return true;
    }
    final ancestors = chain.sublist(0, chain.length - 1);
    return styles.cascadeRules
        .candidatesFor(chain.last)
        .any(
          (rule) =>
              rule.origin != CascadeOrigin.userAgent &&
              rule.rule.declarations.any(declaresSpacing) &&
              ruleMediaMatches(
                rule.rule.media,
                rule.rule.mediaConditions,
                styles.contentWidth,
              ) &&
              rule.selectors.selectors.any(
                (selector) => selector.matches(chain.last, ancestors),
              ),
        );
  }

  /// 自动表宽只有测量后才确定；此时解算 auto 外边距，再加回祖先投影。
  ComputedStyle styleForWidth(double width) {
    final margins = _autoMargins(width);
    return ComputedStyle(
      {
        ...style.values,
        'width': '${width}px',
        'font-size': '${style.fontSize}px',
        'font-weight': '${style.fontWeight}',
        'line-height':
            style.unitlessLineHeightFactor?.toString() ??
            (style.lineHeightFactor == null
                ? 'normal'
                : '${style.lineHeight}px'),
        'margin-left': '${margins.left}px',
        'margin-right': '${margins.right}px',
        if (spacingHint != null) 'border-spacing': '${spacingHint}px',
      },
      parent: style,
      containingWidth: styles.snapshot.width,
      explicitProperties: {
        ...style.explicitProperties,
        'width',
        'margin-left',
        'margin-right',
      },
      hasExplicitTextColor: style.hasExplicitTextColor,
      declaredTextProperties: style.declaredTextProperties,
    );
  }

  ({double left, double right}) _autoMargins(double width) {
    final leftAuto = rawStyle.marginLeftIsAuto;
    final rightAuto = rawStyle.marginRightIsAuto;
    final remaining = math.max(
      0.0,
      availableWidth -
          width -
          BoxModel.fromStyle(
            style,
            containingWidth: availableWidth,
          ).horizontalInset,
    );
    final share = rawStyle.cssFloat == CssFloat.none && !rawStyle.isOutOfFlow
        ? remaining / (leftAuto && rightAuto ? 2 : 1)
        : 0.0;
    return (
      left: style.margin.left + (leftAuto ? share - rawStyle.margin.left : 0),
      right:
          style.margin.right + (rightAuto ? share - rawStyle.margin.right : 0),
    );
  }
}

class _TableRow {
  const _TableRow(this.node, this.cells, this.header);

  final BlockNode node;
  final List<BlockNode> cells;
  final bool header;
}

typedef _ColumnElement = ({String tag, Map<String, String> attributes});
typedef _CellContent = ({String text, List<InlineMark> marks});
typedef _TableWidth = ({double? pixels, double? fraction});
typedef _CellInput = ({
  BlockNode node,
  List<SelectorElement> chain,
  ComputedStyle style,
  _CellContent content,
});

/// 原文结构解析只属于当前表格，不进入章节或书籍缓存。
class _TableStructure {
  _TableStructure(this.budget);

  final LayoutBudget budget;
  final rows = <_TableRow>[];
  final columns = <_ColumnElement>[];
  BlockNode? caption;

  Future<void> parse(BlockNode node) async {
    for (final child in node.children) {
      await budget.checkpoint();
      if (caption == null && child is BlockNode && child.tag == 'caption') {
        caption = child;
      }
    }
    await _walkRows(node, false);
    if (rows.isNotEmpty) await _walkColumns(node);
  }

  Future<void> _walkRows(EpubNode node, bool inHeader) async {
    await budget.checkpoint();
    if (node is! BlockNode) return;
    if (node.tag == 'tr') {
      final cells = <BlockNode>[];
      for (final child in node.children) {
        await budget.checkpoint();
        if (child is BlockNode && (child.tag == 'td' || child.tag == 'th')) {
          cells.add(child);
        }
      }
      if (cells.isNotEmpty) rows.add(_TableRow(node, cells, inHeader));
      return;
    }
    if (node.tag == 'td' || node.tag == 'th') return;
    for (final child in node.children) {
      await _walkRows(child, inHeader || node.tag == 'thead');
    }
  }

  Future<void> _walkColumns(EpubNode node) async {
    await budget.checkpoint();
    final element = switch (node) {
      BlockNode() => (
        tag: node.tag,
        attributes: node.attributes,
        children: node.children,
      ),
      InlineNode() => (
        tag: node.tag,
        attributes: node.attributes,
        children: node.children,
      ),
      _ => null,
    };
    if (element == null) return;
    if (element.tag == 'col') {
      columns.add((tag: element.tag, attributes: element.attributes));
      return;
    }
    for (final child in element.children) {
      await _walkColumns(child);
    }
  }
}

/// 格内文本拼接保留 trim、空盒空白、嵌套换行和行内标记的原文坐标。
class _CellContentCollector {
  _CellContentCollector(this.budget);

  final LayoutBudget budget;
  final buffer = StringBuffer();
  final marks = <InlineMark>[];

  Future<_CellContent> collect(
    BlockNode cell,
    List<SelectorElement> chain,
  ) async {
    final ancestors = <MarkSubject>[];
    for (final element in chain) {
      await budget.checkpoint();
      ancestors.add(_subject(element.tag, element.attributes));
    }
    await _walk(cell, ancestors);
    return (text: buffer.toString(), marks: marks);
  }

  Future<void> _walk(EpubNode node, List<MarkSubject> ancestors) async {
    await budget.checkpoint();
    if (node is TextContentNode) {
      await _aggregatedText(node);
    } else if (node is TextBlockNode) {
      final trimmed = node.text.trim();
      if (trimmed.isNotEmpty) _appendText(trimmed);
    } else if (node is BlockNode) {
      for (final child in node.children) {
        await _walk(child, ancestors);
      }
    } else if (node is InlineNode) {
      await _inlineNode(node, ancestors);
    }
  }

  Future<void> _aggregatedText(TextContentNode node) async {
    var hasEmptyBox = false;
    for (final mark in node.inlineMarks) {
      await budget.checkpoint();
      hasEmptyBox = hasEmptyBox || mark.start == mark.end;
    }
    final raw = node.text;
    final text = hasEmptyBox ? raw : raw.trim();
    if (text.isEmpty && node.inlineMarks.isEmpty) return;
    final leading = hasEmptyBox ? 0 : raw.length - raw.trimLeft().length;
    final offset = _appendText(text);
    for (final mark in node.inlineMarks) {
      await budget.checkpoint();
      final start = math.max(0, mark.start - leading);
      final end = math.min(text.length, mark.end - leading);
      if (end < start) continue;
      marks.add(
        InlineMark(
          start: offset + start,
          end: offset + end,
          tag: mark.tag,
          classes: mark.classes,
          chain: mark.chain,
        ),
      );
    }
  }

  Future<void> _inlineNode(InlineNode node, List<MarkSubject> ancestors) async {
    final classes = (node.attributes['class'] ?? '')
        .split(RegExp(r'\s+'))
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    final subject = MarkSubject(
      tag: node.tag,
      attributes: node.attributes,
      classes: classes.toSet(),
    );
    final next = <MarkSubject>[...ancestors, subject];
    final start = buffer.length;
    for (final child in node.children) {
      await _walk(child, next);
    }
    final end = buffer.length;
    if (end <= start) return;
    marks.add(
      InlineMark(
        start: start,
        end: end,
        tag: node.tag,
        classes: classes,
        chain: List<MarkSubject>.unmodifiable(next),
      ),
    );
  }

  int _appendText(String text) {
    if (buffer.isNotEmpty) buffer.write('\n');
    final offset = buffer.length;
    buffer.write(text);
    return offset;
  }

  MarkSubject _subject(String tag, Map<String, String> attributes) =>
      MarkSubject(
        tag: tag,
        attributes: attributes,
        classes: (attributes['class'] ?? '')
            .split(RegExp(r'\s+'))
            .where((value) => value.isNotEmpty)
            .toSet(),
      );
}

/// 当前格的只读输入；测量只访问本作业的冻结字体、宽高和预算。
class _TableCell {
  _TableCell(this.inline, this.table, this.input);

  final InlineContentBuilder inline;
  final _TableDescription table;
  final _CellInput input;
  BlockNode get node => input.node;
  List<SelectorElement> get chain => input.chain;
  ComputedStyle get style => input.style;
  _CellContent get content => input.content;

  LayoutBudget get budget => inline.measure.budget;
  bool get hasContent => content.text.isNotEmpty || content.marks.isNotEmpty;
  int get colspan => _span(node, 'colspan');
  int get rowspan => _span(node, 'rowspan');
  TableCellInset get inset =>
      tableCellInsetFor(style, collapse: table.collapse);

  Future<TextLayoutResult> layout(double width) {
    if (hasContent) {
      return inline.layoutCellContent(
        content.text,
        content.marks,
        chain,
        style,
        math.max(8.0, width - inset.horizontal),
      );
    }
    return Future.value(
      TextLayoutResult(
        text: '',
        lines: const [],
        width: 0,
        height: 0,
        maxWidth: width,
      ),
    );
  }

  Future<double> height(double width) async {
    await budget.checkpoint();
    final natural = !hasContent
        ? style.lineHeight * 0.6 + inset.vertical
        : (await layout(width)).height + inset.vertical;
    final declared = style.height?.resolve(inline.measure.snapshot.pageHeight);
    if (declared == null) return natural;
    final boxHeight = style.boxSizing == CssBoxSizing.borderBox
        ? declared
        : declared + inset.vertical;
    return math.max(natural, boxHeight);
  }

  Future<double> naturalWidth() async {
    if (!hasContent) return 0;
    final measured = await layout(table.availableWidth);
    return await _widestLine(measured) + inset.horizontal;
  }

  Future<double> minWidth() async {
    if (!hasContent) return 0;
    var width = await inline.measure.minContentTextWidth(
      text: content.text,
      breakEverywhere:
          style.wordBreak == CssWordBreak.breakAll ||
          style.overflowWrap == CssOverflowWrap.anywhere,
      style: style,
    );
    if (content.marks.isNotEmpty || content.text.contains('\uFFFC')) {
      width = math.max(width, await _widestLine(await layout(8)));
    }
    return width + inset.horizontal;
  }

  Future<double> _widestLine(TextLayoutResult result) async {
    var width = 0.0;
    for (final line in result.lines) {
      await budget.checkpoint();
      width = math.max(width, line.width);
    }
    return width;
  }
}

int _span(BlockNode node, String name) =>
    int.tryParse(node.attributes[name]?.trim() ?? '') ?? 1;

class _DeclaredColumns {
  _DeclaredColumns(int count)
    : widths = List<double?>.filled(count, null),
      percent = List<bool>.filled(count, false);

  final List<double?> widths;
  final List<bool> percent;
}

/// 各阶段输入和中间几何随本次构建释放，不持有可变宿主缓存。
class _TableBuild {
  _TableBuild(this.styles, this.inline, this.table);

  final ChapterStyleResolver styles;
  final InlineContentBuilder inline;
  final _TableDescription table;
  LayoutBudget get budget => inline.measure.budget;

  Future<List<PageBlock>> build() async {
    final structure = _TableStructure(budget);
    await structure.parse(table.node);
    if (structure.rows.isEmpty) return _fallbackBlocks();
    final columns = await _declaredColumns(structure);
    final cells = await _prepareCells(structure.rows);
    final specs = await _cellSpecs(cells);
    await _firstRowColumns(columns, cells.first);
    final measured = await _measureGrid(cells, specs, columns);
    await budget.checkpoint();
    final grid = await TableGridLayout.createAsync(
      rows: specs,
      columnWidths: measured.columnWidths,
      rowHeights: measured.rowHeights,
      borderSpacingX: table.spacingX,
      borderSpacingY: table.spacingY,
      checkpoint: budget.checkpoint,
    );
    final renders = await _renderCells(cells, grid);
    final caption = await _caption(structure.caption, measured.tableWidth);
    final block = await _tableBlock(
      structure.rows,
      measured,
      grid,
      renders,
      caption,
    );
    return [
      if (caption != null && _captionOnTop) caption,
      block,
      if (caption != null && !_captionOnTop) caption,
    ];
  }

  bool get _captionOnTop => table.style.captionSide == CssCaptionSide.top;

  Future<List<PageBlock>> _fallbackBlocks() async {
    final blocks = <PageBlock>[];
    for (final child in table.node.children) {
      await _fallbackText(child, blocks);
    }
    return blocks;
  }

  Future<void> _fallbackText(EpubNode node, List<PageBlock> blocks) async {
    await budget.checkpoint();
    if (node is TextBlockNode) {
      if (node.text.trim().isEmpty) return;
      final style = styles.styleFor('td');
      final result = await inline.measure.layout(
        text: node.text,
        style: style,
        maxWidth: table.availableWidth,
      );
      if (result.lineCount > 0) {
        blocks.add(
          PageBlock.styled(
            layout: result,
            style: style,
            containingWidth: table.availableWidth,
          ),
        );
      }
    } else if (node is BlockNode) {
      for (final child in node.children) {
        await _fallbackText(child, blocks);
      }
    } else if (node is InlineNode) {
      for (final child in node.children) {
        await _fallbackText(child, blocks);
      }
    }
  }

  Future<int> _columnCount(List<_TableRow> rows) async {
    var count = 0;
    for (final row in rows) {
      var width = 0;
      for (final cell in row.cells) {
        await budget.checkpoint();
        width += _span(cell, 'colspan');
      }
      count = math.max(count, width);
    }
    return count;
  }

  Future<_DeclaredColumns> _declaredColumns(_TableStructure structure) async {
    final result = _DeclaredColumns(await _columnCount(structure.rows));
    for (
      var i = 0;
      i < structure.columns.length && i < result.widths.length;
      i++
    ) {
      await budget.checkpoint();
      final column = structure.columns[i];
      final style = styles.styleForChain([
        ...table.chain,
        ChapterNodeView(column.tag, column.attributes, const []),
      ]);
      result.widths[i] = _declaredLength(style, column.attributes);
      result.percent[i] = _declaredIsPercent(style, column.attributes);
    }
    return result;
  }

  double? _declaredLength(ComputedStyle style, Map<String, String> attributes) {
    final css = style.width;
    if (css != null && !css.isAuto) {
      return css.isPercent ? table.availableWidth * css.value / 100 : css.value;
    }
    final raw = attributes['width']?.trim();
    if (raw == null || raw.isEmpty) return null;
    if (raw.endsWith('%')) {
      final percent = double.tryParse(raw.substring(0, raw.length - 1));
      return percent == null ? null : table.availableWidth * percent / 100;
    }
    return double.tryParse(raw.replaceAll(RegExp(r'[^0-9.]'), ''));
  }

  bool _declaredIsPercent(ComputedStyle style, Map<String, String> attributes) {
    final css = style.width;
    return css != null && !css.isAuto
        ? css.isPercent
        : (attributes['width']?.trim() ?? '').endsWith('%');
  }

  _TableWidth _declaredTableWidth() {
    double? pixels;
    double? fraction;
    final raw = table.node.attributes['width']?.trim();
    if (raw != null && raw.isNotEmpty) {
      if (raw.endsWith('%')) {
        fraction =
            (double.tryParse(raw.substring(0, raw.length - 1)) ?? 100) / 100;
      } else {
        pixels = double.tryParse(raw);
      }
    }
    final css = table.style.width;
    if (pixels == null && fraction == null && css != null && !css.isAuto) {
      if (css.isPercent) {
        fraction = css.value / 100;
      } else {
        pixels = css.value;
      }
    }
    return (pixels: pixels, fraction: fraction);
  }

  Future<List<List<_TableCell>>> _prepareCells(List<_TableRow> rows) async {
    final result = <List<_TableCell>>[];
    for (final row in rows) {
      await budget.checkpoint();
      final rowView = ChapterNodeView(
        row.node.tag,
        row.node.attributes,
        const [],
      );
      final cells = <_TableCell>[];
      for (final node in row.cells) {
        await budget.checkpoint();
        final chain = List<SelectorElement>.unmodifiable([
          ...table.chain,
          rowView,
          ChapterNodeView(node.tag, node.attributes, const []),
        ]);
        final style = styles.chainStyle(chain);
        final content = await _CellContentCollector(budget)
            .collect(node, chain);
        cells.add(
          _TableCell(inline, table, (
            node: node,
            chain: chain,
            style: style,
            content: content,
          )),
        );
      }
      result.add(cells);
    }
    return result;
  }

  Future<List<List<TableCellSpec>>> _cellSpecs(
    List<List<_TableCell>> cells,
  ) async {
    final result = <List<TableCellSpec>>[];
    for (final row in cells) {
      final specs = <TableCellSpec>[];
      for (final cell in row) {
        await budget.checkpoint();
        specs.add(
          TableCellSpec(
            naturalWidth: await cell.naturalWidth(),
            minWidth: await cell.minWidth(),
            colspan: cell.colspan,
            rowspan: cell.rowspan,
            measureHeight: cell.height,
          ),
        );
      }
      result.add(specs);
    }
    return result;
  }

  Future<void> _firstRowColumns(
    _DeclaredColumns columns,
    List<_TableCell> cells,
  ) async {
    var column = 0;
    for (final cell in cells) {
      await budget.checkpoint();
      if (column < columns.widths.length && columns.widths[column] == null) {
        columns.widths[column] = _declaredLength(
          cell.style,
          cell.node.attributes,
        );
        columns.percent[column] = _declaredIsPercent(
          cell.style,
          cell.node.attributes,
        );
      }
      column += cell.colspan;
    }
  }

  Future<TableGridMeasureResult> _measureGrid(
    List<List<_TableCell>> cells,
    List<List<TableCellSpec>> specs,
    _DeclaredColumns columns,
  ) async {
    final width = _declaredTableWidth();
    if (table.style.tableLayout == CssTableLayout.fixed) {
      final widths = await _FixedColumns(
        table,
        columns,
        cells.first,
        budget,
      ).measure(width);
      final heights = await _fixedHeights(cells, widths);
      return TableGridMeasureResult(
        columnWidths: widths,
        rowHeights: heights,
        tableWidth:
            await _sumWidths(widths) + table.spacingX * (widths.length + 1),
      );
    }
    return TableGridMeasurer.measureGridAsync(
      rows: specs,
      columnSpecified: columns.widths,
      tableWidthPx: width.pixels,
      tableWidthPercent: width.fraction,
      containerWidth: table.availableWidth,
      borderSpacingX: table.spacingX,
      borderSpacingY: table.spacingY,
      checkpoint: budget.checkpoint,
    );
  }

  Future<double> _sumWidths(List<double> widths) async {
    var sum = 0.0;
    for (final width in widths) {
      await budget.checkpoint();
      sum += width;
    }
    return sum;
  }

  Future<List<List<double>>> _fixedCellWidths(
    List<List<_TableCell>> cells,
    List<double> widths,
  ) async {
    final result = <List<double>>[];
    for (final row in cells) {
      var column = 0;
      final sizes = <double>[];
      for (final cell in row) {
        var width = 0.0;
        for (
          var c = column;
          c < column + cell.colspan && c < widths.length;
          c++
        ) {
          await budget.checkpoint();
          width += widths[c];
        }
        column += cell.colspan;
        sizes.add(width);
      }
      result.add(sizes);
    }
    return result;
  }

  Future<List<double>> _fixedHeights(
    List<List<_TableCell>> cells,
    List<double> widths,
  ) async {
    final cellWidths = await _fixedCellWidths(cells, widths);
    final heights = List<double>.filled(cells.length, 0);
    for (var row = 0; row < cells.length; row++) {
      for (var cell = 0; cell < cells[row].length; cell++) {
        await budget.checkpoint();
        if (cells[row][cell].rowspan > 1) continue;
        heights[row] = math.max(
          heights[row],
          await cells[row][cell].height(cellWidths[row][cell]),
        );
      }
    }
    await _spreadFixedSpans(cells, cellWidths, heights);
    return heights;
  }

  Future<void> _spreadFixedSpans(
    List<List<_TableCell>> cells,
    List<List<double>> widths,
    List<double> heights,
  ) async {
    for (var row = 0; row < cells.length; row++) {
      for (var cell = 0; cell < cells[row].length; cell++) {
        await budget.checkpoint();
        final current = cells[row][cell];
        if (current.rowspan <= 1) continue;
        final height = await current.height(widths[row][cell]);
        await _distributeRowHeight(heights, row, current.rowspan, height);
      }
    }
  }

  Future<void> _distributeRowHeight(
    List<double> heights,
    int first,
    int rowspan,
    double height,
  ) async {
    final count = math.min(rowspan, heights.length - first);
    var current = 0.0;
    for (var row = first; row < first + count; row++) {
      await budget.checkpoint();
      current += heights[row];
    }
    if (height <= current) return;
    final extra = (height - current) / count;
    for (var row = first; row < first + count; row++) {
      await budget.checkpoint();
      heights[row] += extra;
    }
  }

  Future<List<TableCellRender>> _renderCells(
    List<List<_TableCell>> cells,
    TableGridLayout grid,
  ) async {
    final result = <TableCellRender>[];
    for (var row = 0; row < cells.length; row++) {
      for (var column = 0; column < cells[row].length; column++) {
        await budget.checkpoint();
        final rect = grid.cellRectAt(row, column);
        if (rect == null) continue;
        final cell = cells[row][column];
        result.add(
          TableCellRender(
            row: row,
            rect: rect.rect,
            layout: await cell.layout(rect.rect.width),
            style: cell.style,
            startCfi: cell.node.cfi.serialize(),
          ),
        );
      }
    }
    return result;
  }

  Future<PageBlock?> _caption(BlockNode? node, double width) async {
    if (node == null) return null;
    final chain = [
      ...table.chain,
      ChapterNodeView(node.tag, node.attributes, const []),
    ];
    final style = styles.styleForChain(chain);
    final content = await _CellContentCollector(budget).collect(node, chain);
    if (content.text.isEmpty && content.marks.isEmpty) return null;
    final layout = await inline.layoutCellContent(
      content.text,
      content.marks,
      chain,
      style,
      math.max(
        8.0,
        width - tableCellInsetFor(style, collapse: table.collapse).horizontal,
      ),
    );
    return PageBlock.styled(
      layout: layout,
      style: style,
      startCfi: node.cfi.serialize(),
      containingWidth: width,
      spaceBefore:
          style.margin.top + (_captionOnTop ? table.style.margin.top : 0),
      spaceAfter:
          style.margin.bottom +
          (!_captionOnTop ? table.style.margin.bottom : 0),
    );
  }

  Future<double> _tableHeight(List<double> heights) async {
    var height = 0.0;
    for (final row in heights) {
      await budget.checkpoint();
      height += row + table.spacingY;
    }
    return height + table.spacingY;
  }

  Future<int> _headerRows(List<_TableRow> rows) async {
    var count = 0;
    while (count < rows.length && rows[count].header) {
      await budget.checkpoint();
      count += 1;
    }
    return count;
  }

  Future<List<TableCellRender>> _clipWholeTable(
    List<TableCellRender> cells,
    double height,
  ) async {
    final result = <TableCellRender>[];
    for (final cell in cells) {
      await budget.checkpoint();
      if (cell.rect.bottom <= 0.01 || cell.rect.top >= height - 0.01) continue;
      result.add(
        TableCellRender(
          row: cell.row,
          rect: Rect.fromLTRB(
            cell.rect.left,
            math.max(0.0, cell.rect.top),
            cell.rect.right,
            math.min(height, cell.rect.bottom),
          ),
          layout: cell.layout,
          style: cell.style,
          startCfi: cell.startCfi,
        ),
      );
    }
    return result;
  }

  /// 保留完整表格，让 Paginator 按页面真实余高切行并重复表头。
  Future<PageBlock> _tableBlock(
    List<_TableRow> rows,
    TableGridMeasureResult measured,
    TableGridLayout grid,
    List<TableCellRender> cells,
    PageBlock? caption,
  ) async {
    final height = await _tableHeight(measured.rowHeights);
    final headers = await _headerRows(rows);
    final rowYs = await _rowBoundaries(grid.rowYs);
    final spec = TableRenderSpec(
      cells: await _clipWholeTable(cells, height),
      columnXs: grid.columnXs,
      rowYs: rowYs,
      tableWidth: measured.tableWidth,
      headerRowCount: headers,
      headerHeight: headers > 0 ? rowYs[headers] : 0,
    );
    return _finalBlock(measured.tableWidth, height, spec, caption);
  }

  Future<List<double>> _rowBoundaries(List<double> source) async {
    final result = <double>[];
    for (final boundary in source) {
      await budget.checkpoint();
      result.add(boundary);
    }
    return result;
  }

  PageBlock _finalBlock(
    double width,
    double height,
    TableRenderSpec spec,
    PageBlock? caption,
  ) => PageBlock.styled(
    style: table.styleForWidth(width),
    containingWidth: styles.snapshot.width,
    containerSides: table.borderedContainer,
    effectiveOpacity: table.opacity,
    spaceBefore: caption == null || !_captionOnTop ? table.style.margin.top : 0,
    spaceAfter: caption == null || _captionOnTop
        ? table.style.margin.bottom
        : 0,
    layout: _tableLayout(width, height),
    table: spec,
  );

  TextLayoutResult _tableLayout(double width, double height) =>
      TextLayoutResult(
        text: '',
        lines: [
          LineBox(
            start: 0,
            end: 0,
            top: 0,
            height: height,
            baseline: height,
            width: width,
          ),
        ],
        width: width,
        height: height,
        maxWidth: width,
        runs: const [],
      );
}

/// fixed 布局沿用首行内缩与声明宽口径；百分比基于扣除间距后的表宽。
class _FixedColumns {
  _FixedColumns(this.table, this.columns, this.firstRow, this.budget);

  final _TableDescription table;
  final _DeclaredColumns columns;
  final List<_TableCell> firstRow;
  final LayoutBudget budget;

  Future<List<double>> measure(_TableWidth declared) async {
    final target =
        (declared.fraction != null
                ? table.availableWidth * declared.fraction!.clamp(0.0, 1.0)
                : (declared.pixels ?? table.availableWidth))
            .clamp(0.0, table.availableWidth);
    final space = math.max(
      0.0,
      target - table.spacingX * (columns.widths.length + 1),
    );
    final insets = await _columnInsets();
    final widths = List<double>.filled(columns.widths.length, 0);
    final totals = await _specifiedWidths(widths, insets, space);
    await _allocateRemaining(widths, space, totals);
    return widths;
  }

  Future<List<double>> _columnInsets() async {
    final result = List<double>.filled(columns.widths.length, 0);
    var column = 0;
    for (final cell in firstRow) {
      for (
        var c = column;
        c < column + cell.colspan && c < result.length;
        c++
      ) {
        await budget.checkpoint();
        result[c] = cell.inset.horizontal;
      }
      column += cell.colspan;
    }
    return result;
  }

  Future<({double specified, int auto})> _specifiedWidths(
    List<double> widths,
    List<double> insets,
    double space,
  ) async {
    var specified = 0.0;
    var auto = 0;
    for (var column = 0; column < widths.length; column++) {
      await budget.checkpoint();
      final declared = columns.widths[column];
      if (declared == null) {
        auto += 1;
        continue;
      }
      final content = columns.percent[column] && table.availableWidth > 0
          ? declared * space / table.availableWidth
          : declared;
      widths[column] = content + insets[column];
      specified += widths[column];
    }
    return (specified: specified, auto: auto);
  }

  Future<void> _allocateRemaining(
    List<double> widths,
    double space,
    ({double specified, int auto}) totals,
  ) async {
    if (totals.auto > 0) {
      final share = math.max(0.0, space - totals.specified) / totals.auto;
      for (var column = 0; column < widths.length; column++) {
        await budget.checkpoint();
        if (columns.widths[column] == null) widths[column] = share;
      }
    } else if (totals.specified > space && totals.specified > 0) {
      final scale = space / totals.specified;
      for (var column = 0; column < widths.length; column++) {
        await budget.checkpoint();
        widths[column] *= scale;
      }
    }
  }
}
