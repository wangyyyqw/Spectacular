import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../library/library_store.dart';
import 'book_cover_image.dart';

const bookStackPreviewCount = 4;
const _coverRotation = -35 * math.pi / 180;

typedef _CoverRegion = ({Path path, Offset center});
typedef _CoverLayout = ({Size coverSize, List<_CoverRegion> regions});

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
  });

  final List<BookEntry> books;
  final double? width;
  final double? height;

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
                child: _cover(
                  index,
                  layout.coverSize,
                  region.center,
                  count == 3 && index == 2,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _cover(int index, Size size, Offset center, bool horizontal) => Stack(
    clipBehavior: Clip.none,
    children: [
      Positioned.fromRect(
        rect: Rect.fromCenter(
          center: center,
          width: size.width,
          height: size.height,
        ),
        child: Transform.rotate(
          angle: _coverRotation + (horizontal ? math.pi / 2 : 0),
          child: BookCoverImage(
            key: ValueKey('book-cover-stack-$index'),
            book: books[index],
            showFrame: false,
          ),
        ),
      ),
    ],
  );
}

_CoverLayout _collageLayout(Size size, int count) {
  if (count <= 1) return (coverSize: size, regions: []);
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
    ));
  }
  // 每张使用同一尺寸；半像素余量覆盖旋转采样边缘，不让接缝露底。
  return (
    coverSize: Size(coverWidth + .5, (coverWidth + .5) * 4 / 3),
    regions: regions,
  );
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
