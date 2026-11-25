import 'package:flutter/material.dart';

/// 只在正文未缓存时显示云朵，不触发章节下载。
class OnlineChapterCacheIcon extends StatelessWidget {
  const OnlineChapterCacheIcon({super.key, required this.cached});
  final Future<bool> cached;
  @override
  Widget build(BuildContext context) => FutureBuilder<bool>(
    future: cached,
    builder: (context, snapshot) => snapshot.data == false
        ? const Tooltip(
            message: '未下载',
            child: Icon(Icons.cloud_outlined, size: 18),
          )
        : const SizedBox.shrink(),
  );
}
