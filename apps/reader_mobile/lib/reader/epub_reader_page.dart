import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:reader_ui/reader_page.dart';
import 'package:reader_ui/reader_session.dart';

import 'epub_chapter_source.dart';

/// 从内存 EPUB 打开的最小阅读页。
class EpubReaderPage extends StatefulWidget {
  /// 创建页面。
  const EpubReaderPage({
    super.key,
    required this.bytes,
    required this.bookId,
    required this.store,
  });

  /// EPUB 字节。
  final Uint8List bytes;

  /// 书籍标识。
  final String bookId;

  /// 进度存储。
  final ReaderProgressStore store;

  @override
  State<EpubReaderPage> createState() => _EpubReaderPageState();
}

class _EpubReaderPageState extends State<EpubReaderPage> {
  EpubChapterSource? _source;
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
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final error = _error;
    if (error != null) {
      return Center(child: Text('打开失败：$error'));
    }
    return ReaderPage(
      source: _source!,
      store: widget.store,
      bookId: widget.bookId,
    );
  }
}
