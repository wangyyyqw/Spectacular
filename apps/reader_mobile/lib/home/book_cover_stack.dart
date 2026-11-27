import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../library/library_store.dart';
import 'book_cover_image.dart';

const bookStackFrontScale = .82;
const bookStackBackScale = .74;

/// 首本完整置于前景，后方最多两本露出侧边；整组语义由外层提供。
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
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  if (books.length > 2)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: BookCoverImage(
                        key: const ValueKey('book-cover-stack-back-right'),
                        book: books[2],
                        width: coverWidth * bookStackBackScale,
                        height: coverHeight * bookStackBackScale,
                        showShadow: true,
                      ),
                    ),
                  if (books.length > 1)
                    Positioned(
                      left: 0,
                      bottom: 0,
                      child: BookCoverImage(
                        key: const ValueKey('book-cover-stack-back-left'),
                        book: books[1],
                        width: coverWidth * bookStackBackScale,
                        height: coverHeight * bookStackBackScale,
                        showShadow: true,
                      ),
                    ),
                  if (books.isNotEmpty)
                    Positioned(
                      left: coverWidth * (1 - bookStackFrontScale) / 2,
                      bottom: 0,
                      child: BookCoverImage(
                        key: const ValueKey('book-cover-stack-front'),
                        book: books.first,
                        width: coverWidth * bookStackFrontScale,
                        height: coverHeight * bookStackFrontScale,
                        showShadow: true,
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    ),
  );
}
