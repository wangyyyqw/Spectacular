import 'package:reader_core/layout/paginator.dart';

/// 职责迁移的结构化护栏，记录正文、CFI、行几何及绘制载荷。
///
/// 只在明确登记的分页语义变更后更新基线；不以截图或页数替代原文比较。
List<Object?> snapshotPages(List<PageContent> pages) => [
  for (final page in pages)
    {
      'page': page.pageIndex,
      'height': _number(page.pageHeight),
      'used': _number(page.usedHeight),
      'top': _number(page.topPadding),
      'background': page.background?.imageUrl,
      'slices': [for (final slice in page.slices) _snapshotSlice(slice)],
    },
];

Map<String, Object?> _snapshotSlice(PageBlockSlice slice) {
  final block = slice.block;
  return {
    'cfi': [block.startCfi, block.endCfi],
    'text': block.layout.text,
    'range': [slice.startLine, slice.endLine],
    'geometry': [
      _number(slice.height),
      _number(slice.leadingExtent),
      _number(slice.trailingExtent),
      _number(slice.leftInset),
      slice.absoluteTop == null ? null : _number(slice.absoluteTop!),
      _number(slice.textTopTrim),
      _number(slice.textBottomTrim),
    ],
    'overlay': slice.overlay,
    'group': block.groupId,
    'marker': block.listMarker,
    'style': block.style?.layoutFingerprint,
    'lines': [
      for (final line in slice.lines)
        [
          line.start,
          line.end,
          _number(line.top),
          _number(line.height),
          _number(line.baseline),
          _number(line.width),
        ],
    ],
    'runs': [
      for (final run in block.layout.runs)
        [run.start, run.end, run.style.layoutFingerprint, run.baselineShift],
    ],
    'images': [
      for (final image in block.inlineImages)
        [image.offset, image.url, image.width, image.height],
    ],
    'footnotes': [
      for (final note in block.footnotes)
        [note.start, note.end, note.label, note.text, note.imageUrls],
    ],
    'containers': [
      for (final fragment in block.containers)
        [
          fragment.startsHere,
          fragment.endsHere,
          _number(fragment.container.left),
          _number(fragment.container.width),
          fragment.container.style.layoutFingerprint,
        ],
    ],
  };
}

double _number(double value) => double.parse(value.toStringAsFixed(4));
