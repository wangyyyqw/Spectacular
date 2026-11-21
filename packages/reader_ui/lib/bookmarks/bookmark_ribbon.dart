import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'bookmark_style.dart';
import 'bookmark_image.dart';

/// 书签标记与设置预览共用同一绘制，自定义图片按指定宽长缩放。
class ReaderBookmarkRibbon extends StatefulWidget {
  const ReaderBookmarkRibbon({
    super.key,
    required this.style,
    required this.color,
    this.imageLoader,
    this.image,
  });

  final ReaderBookmarkStyle style;
  final Color color;
  final Future<Uint8List> Function(String id)? imageLoader;
  final ReaderBookmarkImage? image;

  @override
  State<ReaderBookmarkRibbon> createState() => _ReaderBookmarkRibbonState();
}

class _ReaderBookmarkRibbonState extends State<ReaderBookmarkRibbon> {
  final _ownedImage = ReaderBookmarkImage();

  ReaderBookmarkImage get _image => widget.image ?? _ownedImage;

  void _loadImage() {
    if (widget.image == null) {
      _ownedImage.load(widget.style.imageId, widget.imageLoader);
    }
  }

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  @override
  void didUpdateWidget(ReaderBookmarkRibbon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.style.imageId != widget.style.imageId ||
        oldWidget.imageLoader != widget.imageLoader ||
        oldWidget.image != widget.image) {
      _loadImage();
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _image,
    builder: (context, _) => SizedBox(
      width: widget.style.width,
      height: widget.style.length,
      child: _image.image != null
          ? RawImage(image: _image.image, fit: BoxFit.fill)
          : _image.loading
          ? null
          : ClipPath(
              clipper: const _RibbonClipper(),
              child: ColoredBox(color: widget.color),
            ),
    ),
  );

  @override
  void dispose() {
    _ownedImage.dispose();
    super.dispose();
  }
}

class _RibbonClipper extends CustomClipper<Path> {
  const _RibbonClipper();

  @override
  Path getClip(Size size) => Path()
    ..lineTo(size.width, 0)
    ..lineTo(size.width, size.height)
    ..lineTo(size.width / 2, size.height - size.shortestSide * 0.4)
    ..lineTo(0, size.height)
    ..close();

  @override
  bool shouldReclip(_RibbonClipper oldClipper) => false;
}
