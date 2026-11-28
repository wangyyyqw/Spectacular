import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../library/library_store.dart';
import 'book_cover_image.dart';
import 'book_cover_title_focus.dart';
import 'book_cover_title_focus_store.dart';

const bookStackPreviewCount = 4;
const _coverRotation = -35 * math.pi / 180;

typedef _CoverRegion = ({Path path, Offset center, double rotation});
typedef _CoverLayout = ({
  Size coverSize,
  List<_CoverRegion> regions,
  List<Path> seams,
});

/// 首屏预解码与拼接使用相同的单张封面尺寸。
Size bookStackCoverSize(Size size, int count) {
  final width = math.min(size.width, size.height * 3 / 4);
  return _collageLayout(
    Size(width, width * 4 / 3),
    count.clamp(1, bookStackPreviewCount),
  ).coverSize;
}

/// 最多四本等比封面按可见面积均衡斜拼，整组语义由外层提供。
class BookCoverStack extends StatelessWidget {
  const BookCoverStack({
    super.key,
    required this.books,
    this.width,
    this.height,
    this.focusStore,
  });

  final List<BookEntry> books;
  final double? width;
  final double? height;
  final BookCoverTitleFocusStore? focusStore;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox(
      width: width,
      height: height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final availableWidth = constraints.hasBoundedWidth
              ? constraints.maxWidth
              : constraints.hasBoundedHeight
              ? constraints.maxHeight * 3 / 4
              : 160.0;
          final coverWidth = math.min(
            availableWidth,
            constraints.maxHeight * 3 / 4,
          );
          final coverHeight = coverWidth * 4 / 3;
          return Align(
            alignment: Alignment.bottomCenter,
            widthFactor: 1,
            heightFactor: 1,
            child: SizedBox(
              width: coverWidth,
              height: coverHeight,
              child: _collage(Size(coverWidth, coverHeight)),
            ),
          );
        },
      ),
    ),
  );

  Widget _collage(Size size) {
    final count = math.min(books.length, bookStackPreviewCount);
    if (count == 0) return const SizedBox.expand();
    if (count == 1) {
      return BookCoverImage(
        key: const ValueKey('book-cover-stack-0'),
        book: books.first,
      );
    }
    final layout = _collageLayout(size, count);
    return ClipRRect(
      key: const ValueKey('book-cover-stack-frame'),
      borderRadius: BorderRadius.circular(4),
      child: Stack(
        children: [
          for (final (index, region) in layout.regions.indexed)
            Positioned.fill(
              child: ClipPath(
                key: ValueKey('book-cover-stack-region-$index'),
                clipper: _CoverCollageClipper(region.path),
                clipBehavior: Clip.antiAlias,
                child: _CollageCover(
                  book: books[index],
                  index: index,
                  count: count,
                  coverSize: layout.coverSize,
                  region: region,
                  focusStore: focusStore ?? coverTitleFocusStore,
                ),
              ),
            ),
          Positioned.fill(
            child: CustomPaint(
              key: const ValueKey('book-cover-stack-seams'),
              painter: _CoverSeamPainter(layout.seams),
            ),
          ),
        ],
      ),
    );
  }
}

class _CollageCover extends StatefulWidget {
  const _CollageCover({
    required this.book,
    required this.index,
    required this.count,
    required this.coverSize,
    required this.region,
    required this.focusStore,
  });

  final BookEntry book;
  final int index;
  final int count;
  final Size coverSize;
  final _CoverRegion region;
  final BookCoverTitleFocusStore focusStore;

  @override
  State<_CollageCover> createState() => _CollageCoverState();
}

class _CollageCoverState extends State<_CollageCover> {
  CoverTitleFocus? _focus;
  Offset _translation = Offset.zero;
  Size? _imageSize;
  var _generation = 0;

  @override
  void initState() {
    super.initState();
    _restoreFocus();
    unawaited(_loadFocus());
  }

  @override
  void didUpdateWidget(covariant _CollageCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.book.id != widget.book.id ||
        oldWidget.book.title != widget.book.title ||
        oldWidget.book.coverPath != widget.book.coverPath ||
        oldWidget.book.contentRevision != widget.book.contentRevision ||
        oldWidget.focusStore != widget.focusStore) {
      _restoreFocus();
      unawaited(_loadFocus());
    } else if (oldWidget.count != widget.count ||
        oldWidget.coverSize != widget.coverSize ||
        oldWidget.region.center != widget.region.center ||
        oldWidget.region.rotation != widget.region.rotation) {
      _placeFocus();
    }
  }

  void _restoreFocus() {
    _focus = widget.focusStore.peek(
      widget.book.coverPath,
      widget.book.title,
      revision: widget.book.contentRevision,
    );
    _placeFocus();
  }

  void _placeFocus() {
    final focus = _focus;
    if (focus == null) {
      _translation = Offset.zero;
      _imageSize = null;
      return;
    }
    final placement = coverTitleFocusPlacement(
      focus: focus,
      coverSize: widget.coverSize,
      clipPath: widget.region.path,
      regionCenter: widget.region.center,
      rotation: widget.region.rotation,
    );
    _translation = placement.translation;
    _imageSize = placement.imageSize;
  }

  Future<void> _loadFocus() async {
    final generation = ++_generation;
    try {
      final focus = await widget.focusStore.resolve(
        widget.book.coverPath,
        widget.book.title,
        revision: widget.book.contentRevision,
      );
      if (!mounted || generation != _generation || identical(focus, _focus)) {
        return;
      }
      setState(() {
        _focus = focus;
        _placeFocus();
      });
    } on Object {
      // OCR、平台运行时或缓存不可用时保留原有居中裁切。
    }
  }

  @override
  Widget build(BuildContext context) => _buildStackCover(
    book: widget.book,
    index: widget.index,
    coverSize: _imageSize ?? widget.coverSize,
    region: widget.region,
    localTranslation: _translation,
  );
}

Widget _buildStackCover({
  required BookEntry book,
  required int index,
  required Size coverSize,
  required _CoverRegion region,
  required Offset localTranslation,
}) {
  final cosine = math.cos(region.rotation);
  final sine = math.sin(region.rotation);
  final translation = Offset(
    localTranslation.dx * cosine - localTranslation.dy * sine,
    localTranslation.dx * sine + localTranslation.dy * cosine,
  );
  return Stack(
    clipBehavior: Clip.none,
    children: [
      Positioned.fromRect(
        rect: Rect.fromCenter(
          center: region.center + translation,
          width: coverSize.width,
          height: coverSize.height,
        ),
        child: Transform.rotate(
          angle: region.rotation,
          child: BookCoverImage(
            key: ValueKey('book-cover-stack-$index'),
            book: book,
            showFrame: false,
          ),
        ),
      ),
    ],
  );
}

_CoverLayout _collageLayout(Size size, int count) {
  if (count <= 1) return (coverSize: size, regions: [], seams: []);
  final frame =
      (Path()..addRect(
            Rect.fromCenter(
              center: Offset.zero,
              width: size.width,
              height: size.height,
            ),
          ))
          .transform(Matrix4.rotationZ(-_coverRotation).storage);
  final transform = Matrix4.translationValues(
    size.width / 2,
    size.height / 2,
    0,
  )..rotateZ(_coverRotation);
  final regions = <_CoverRegion>[];
  var coverWidth = 0.0;
  final cells = _collageCells(frame.getBounds(), size.width, count);
  final seams = _collageSeams(cells, transform);
  for (final (index, cell) in cells.indexed) {
    final path = Path.combine(
      PathOperation.intersect,
      frame,
      Path()..addRect(cell),
    );
    final bounds = path.getBounds();
    final horizontal = count == 3 && index == 2;
    coverWidth = math.max(
      coverWidth,
      horizontal
          ? math.max(bounds.height, bounds.width * 3 / 4)
          : math.max(bounds.width, bounds.height * 3 / 4),
    );
    regions.add((
      path: path.transform(transform.storage),
      center: MatrixUtils.transformPoint(transform, bounds.center),
      rotation: _coverRotation + (horizontal ? math.pi / 2 : 0),
    ));
  }
  // 每张使用同一尺寸；半像素余量覆盖旋转采样边缘，不让接缝露底。
  return (
    coverSize: Size(coverWidth + .5, (coverWidth + .5) * 4 / 3),
    regions: regions,
    seams: seams,
  );
}

List<Path> _collageSeams(List<Rect> cells, Matrix4 transform) {
  final seams = <Path>[];
  for (var firstIndex = 0; firstIndex < cells.length; firstIndex++) {
    final first = cells[firstIndex];
    for (
      var secondIndex = firstIndex + 1;
      secondIndex < cells.length;
      secondIndex++
    ) {
      final second = cells[secondIndex];
      final seam = Path();
      final verticalX = (first.right - second.left).abs() < .001
          ? first.right
          : (second.right - first.left).abs() < .001
          ? second.right
          : null;
      if (verticalX != null) {
        final top = math.max(first.top, second.top);
        final bottom = math.min(first.bottom, second.bottom);
        if (bottom > top) {
          seam
            ..moveTo(verticalX, top)
            ..lineTo(verticalX, bottom);
        }
      }
      final horizontalY = (first.bottom - second.top).abs() < .001
          ? first.bottom
          : (second.bottom - first.top).abs() < .001
          ? second.bottom
          : null;
      if (horizontalY != null) {
        final left = math.max(first.left, second.left);
        final right = math.min(first.right, second.right);
        if (right > left) {
          seam
            ..moveTo(left, horizontalY)
            ..lineTo(right, horizontalY);
        }
      }
      if (seam.computeMetrics().isNotEmpty) {
        seams.add(seam.transform(transform.storage));
      }
    }
  }
  return seams;
}

class _CoverSeamPainter extends CustomPainter {
  const _CoverSeamPainter(this.seams);

  final List<Path> seams;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: .9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final seam in seams) {
      canvas.drawPath(seam, paint);
    }
  }

  @override
  bool shouldRepaint(_CoverSeamPainter oldDelegate) =>
      oldDelegate.seams != seams;
}

List<Rect> _collageCells(Rect bounds, double width, int count) {
  final Rect(:left, :top, :right, :bottom) = bounds;
  if (count == 2) {
    return [
      Rect.fromLTRB(0, top, right, bottom),
      Rect.fromLTRB(left, top, 0, bottom),
    ];
  }
  // 分割点按 3∶4 画布、35° 旋转后的可见面积校准，而非均分旋转前的矩形。
  if (count == 3) {
    final splitX = width * .0593;
    final splitY = width * .17475;
    return [
      Rect.fromLTRB(splitX, top, right, splitY),
      Rect.fromLTRB(left, top, splitX, splitY),
      Rect.fromLTRB(left, splitY, right, bottom),
    ];
  }
  final stagger = width * .10518;
  return [
    Rect.fromLTRB(0, top, right, -stagger),
    Rect.fromLTRB(left, stagger, 0, bottom),
    Rect.fromLTRB(left, top, 0, stagger),
    Rect.fromLTRB(0, -stagger, right, bottom),
  ];
}

class _CoverCollageClipper extends CustomClipper<Path> {
  const _CoverCollageClipper(this.path);

  final Path path;

  @override
  Path getClip(Size size) => path;

  @override
  bool shouldReclip(_CoverCollageClipper oldClipper) => oldClipper.path != path;
}
