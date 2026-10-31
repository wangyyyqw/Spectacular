import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/table_layout.dart';

/// 章节纯文本与块偏移表（P4-24/25 共用，保证索引与定位同一套偏移）。
///
/// 规则（§66.1）：块按页序去重，块间插一个 `\n`；块的起始偏移就是它在
/// 纯文本里的下标。
class ChapterText {
  ChapterText._(this.text, this.blocks);

  /// 由分页结果构建。
  factory ChapterText.fromPages(List<PageContent> pages) {
    final blocks = <ChapterBlock>[];
    final seen = <Object>{};
    final buffer = StringBuffer();
    void append(PageBlock block, {TableCellRender? cell}) {
      final key = cell == null ? block : cell.startCfi ?? cell.layout;
      final content = cell == null ? block.layout.text : _cellText(cell.layout);
      if (!seen.add(key) || content.isEmpty) return;
      if (buffer.isNotEmpty) buffer.write('\n');
      blocks.add(
        ChapterBlock(
          start: buffer.length,
          block: block,
          cell: cell,
          content: content,
        ),
      );
      buffer.write(content);
    }

    for (final page in pages) {
      for (final slice in page.slices) {
        final block = slice.block;
        final table = block.table;
        if (table == null) {
          append(block);
        } else {
          // 表格/Flex 的外层仅负责几何；跨页复制的 rowspan 格只计一次。
          for (final cell in table.cells) {
            append(block, cell: cell);
          }
        }
      }
    }
    return ChapterText._(buffer.toString(), blocks);
  }

  /// 纯文本。
  final String text;

  /// 块偏移表（按起始偏移升序）。
  final List<ChapterBlock> blocks;

  /// 包含该字符偏移的块；越界返回 null。
  ChapterBlock? blockAt(int charOffset) {
    for (final item in blocks) {
      final end = item.start + item.text.length;
      if (charOffset >= item.start && charOffset < end) {
        return item;
      }
    }
    return null;
  }

  /// 字符偏移 → (块, 块内偏移)。
  ({ChapterBlock block, int localOffset})? locate(int charOffset) {
    final block = blockAt(charOffset);
    if (block == null) {
      return null;
    }
    return (block: block, localOffset: charOffset - block.start);
  }
}

// 行内盒文字已从外层字符串摘除，按插入偏移还原可见顺序；不能只读占位串。
String _cellText(TextLayoutResult layout) {
  final boxes = [
    for (final line in layout.lines)
      for (final box in line.inlineBoxes) box.spec,
  ];
  final ordered = boxes.indexed.toList()
    ..sort((a, b) {
      final order = a.$2.offset.compareTo(b.$2.offset);
      return order == 0 ? a.$1.compareTo(b.$1) : order;
    });
  final buffer = StringBuffer();
  var from = 0;
  for (final (_, box) in ordered) {
    final payload = box.payload;
    if (payload is! PageBlock) continue;
    final at = box.offset.clamp(from, layout.text.length);
    buffer.write(layout.text.substring(from, at));
    buffer.write(_cellText(payload.layout));
    from = at;
  }
  buffer.write(layout.text.substring(from));
  return buffer.toString();
}

/// 一个块在章节纯文本中的位置。
class ChapterBlock {
  /// 创建块偏移。
  const ChapterBlock({
    required this.start,
    required this.block,
    this.cell,
    this.content,
  });

  /// 块在纯文本中的起始偏移。
  final int start;

  /// 块本身。
  final PageBlock block;

  /// 表格/Flex 的实际文本载荷；普通块为空。
  final TableCellRender? cell;

  /// 单元格内还原原子行内盒后的实际显示文字。
  final String? content;

  /// 实际显示文字，不使用表格外层的空占位。
  String get text => content ?? cell?.layout.text ?? block.layout.text;

  /// 与实际文字对应的来源锚点。
  String? get startCfi => cell?.startCfi ?? block.startCfi;

  /// 与实际文字对应的计算样式。
  ComputedStyle? get style => cell?.style ?? block.style;
}
