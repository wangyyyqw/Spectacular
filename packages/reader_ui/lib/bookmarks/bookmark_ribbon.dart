import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'bookmark_style.dart';

/// 书签标记与设置预览共用同一绘制，自定义图片按指定宽长缩放。
class ReaderBookmarkRibbon extends StatefulWidget {
  const ReaderBookmarkRibbon({
    super.key,
    required this.style,
    required this.color,
    this.imageLoader,
  });

  final ReaderBookmarkStyle style;
  final Color color;
  final Future<Uint8List> Function(String id)? imageLoader;

  @override
  State<ReaderBookmarkRibbon> createState() => _ReaderBookmarkRibbonState();
}

class _ReaderBookmarkRibbonState extends State<ReaderBookmarkRibbon> {
  Future<Uint8List>? _image;

  void _loadImage() {
    final id = widget.style.imageId;
    _image = id == null ? null : widget.imageLoader?.call(id);
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
        oldWidget.imageLoader != widget.imageLoader) {
      _loadImage();
    }
  }

  @override
  Widget build(BuildContext context) {
    final fallback = ClipPath(
      clipper: const _RibbonClipper(),
      child: ColoredBox(color: widget.color),
    );
    return SizedBox(
      width: widget.style.width,
      height: widget.style.length,
      child: _image == null
          ? fallback
          : FutureBuilder<Uint8List>(
              future: _image,
              builder: (context, snapshot) => snapshot.hasData
                  ? Image.memory(
                      snapshot.data!,
                      fit: BoxFit.fill,
                      excludeFromSemantics: true,
                      errorBuilder: (_, _, _) => fallback,
                    )
                  : fallback,
            ),
    );
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
