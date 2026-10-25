import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/paint/image_cache.dart';
import 'package:reader_ui/loading_skeleton.dart';
import 'package:reader_ui/reader_page.dart';
import 'package:reader_ui/reader_session.dart';

import 'epub_chapter_source.dart';

/// 默认阅读设置：段距 10dp（对齐阅微默认档，约 0.625em @16dp 字号）。
///
/// 字号/行高/对齐默认不覆盖，跟随书籍 CSS；用户设置面板接入后由
/// `ReaderOverrides` 覆盖作者声明（reader origin 高于 author）。
const ReaderOverrides defaultReaderOverrides = ReaderOverrides(
  paragraphSpacing: 10,
);

/// 从内存 EPUB 打开的最小阅读页。
class EpubReaderPage extends StatefulWidget {
  /// 创建页面。
  const EpubReaderPage({
    super.key,
    required this.bytes,
    required this.bookId,
    required this.store,
    this.bookmarks,
  });

  /// EPUB 字节。
  final Uint8List bytes;

  /// 书籍标识。
  final String bookId;

  /// 进度存储。
  final ReaderProgressStore store;

  /// 书签存储（P4-13）；为 null 时菜单不显示书签入口。
  final ReaderBookmarkStore? bookmarks;

  @override
  State<EpubReaderPage> createState() => _EpubReaderPageState();
}

class _EpubReaderPageState extends State<EpubReaderPage> {
  EpubChapterSource? _source;
  DecodedImageCache? _imageCache;
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    try {
      final source = await EpubChapterSource.open(widget.bytes);
      if (!mounted) {
        return;
      }
      setState(() {
        _source = source;
        _imageCache = DecodedImageCache(
          loadBytes: (url) => _loadImageBytes(source, url),
        );
        _loading = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error;
          _loading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _imageCache?.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 打开书期间先出骨架；就绪后由 ReaderPage 平滑接管（P2-27）。
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const ReaderLoadingSkeleton();
    }
    final error = _error;
    if (error != null) {
      return Center(
        key: const ValueKey<String>('epub-open-error'),
        child: Text('打开失败：$error'),
      );
    }
    return ReaderPage(
      key: const ValueKey<String>('reader-page'),
      source: _source!,
      store: widget.store,
      bookId: widget.bookId,
      imageCache: _imageCache,
      bookmarks: widget.bookmarks,
      overrides: defaultReaderOverrides,
    );
  }
}

/// 从 EPUB 归档读取图片字节：先按原样路径找，再按 OPF 目录解析，
/// 最后按各 spine 章节目录逐个尝试（背景图 URL 相对所在章节）。
Future<Uint8List?> _loadImageBytes(EpubChapterSource source, String url) async {
  final document = source.document;
  final direct = document.archive.readBytes(url);
  if (direct != null) {
    return direct;
  }
  final resolved = document.resources.resolve(url);
  if (resolved != null) {
    final bytes = document.archive.readBytes(resolved);
    if (bytes != null) {
      return bytes;
    }
  }
  var tried = 0;
  for (final item in document.spine) {
    if (tried >= 64) {
      break;
    }
    tried += 1;
    final slash = item.href.lastIndexOf('/');
    final baseDir = slash < 0 ? '' : item.href.substring(0, slash);
    final candidate = document.resources.resolve(url, baseDir: baseDir);
    if (candidate == null) {
      continue;
    }
    final bytes = document.archive.readBytes(candidate);
    if (bytes != null) {
      return bytes;
    }
  }
  return null;
}
