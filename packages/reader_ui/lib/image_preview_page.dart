import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// 原图预览页（P3-11，技术方案 §50.5）。
///
/// 打开即显示阅读缓存里的缩略图（后台已预解码，Reeden 180 号口径：
/// 不等点开才解码大图），原图在后台解码完成后替换；支持双指缩放、
/// 拖动，点关闭或返回退出。原图解码用独立的缓存实例（fullResolution），
/// 不挤占阅读 LRU。
class ImagePreviewPage extends StatefulWidget {
  /// 创建预览页。
  const ImagePreviewPage({
    super.key,
    required this.loadOriginal,
    this.thumbnail,
  });

  /// 原图解码（fullResolution）；失败返回 null（保持缩略图展示）。
  final Future<ui.Image?> Function() loadOriginal;

  /// 阅读缓存里已有的显示尺寸图（可空；无则先出加载圈）。
  final ui.Image? thumbnail;

  @override
  State<ImagePreviewPage> createState() => _ImagePreviewPageState();
}

class _ImagePreviewPageState extends State<ImagePreviewPage> {
  late Future<ui.Image?> _original;

  @override
  void initState() {
    super.initState();
    _original = widget.loadOriginal();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            key: const ValueKey<String>('preview-close'),
            icon: const Icon(Icons.close),
            tooltip: '关闭',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      body: FutureBuilder<ui.Image?>(
        future: _original,
        builder: (context, snapshot) {
          final image = snapshot.data ?? widget.thumbnail;
          if (image == null) {
            if (snapshot.connectionState == ConnectionState.done) {
              return _unavailable();
            }
            return const Center(child: CircularProgressIndicator());
          }
          return InteractiveViewer(
            key: const ValueKey<String>('preview-viewer'),
            maxScale: 8,
            child: Center(
              child: RawImage(
                image: image,
                fit: BoxFit.contain,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _unavailable() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('图片无法加载', style: TextStyle(color: Colors.white)),
        TextButton.icon(
          style: TextButton.styleFrom(foregroundColor: Colors.white),
          onPressed: () {
            final original = widget.loadOriginal();
            setState(() {
              _original = original;
            });
          },
          icon: const Icon(Icons.refresh),
          label: const Text('重试'),
        ),
      ],
    ),
  );
}
