import 'package:flutter/material.dart';
import 'package:reader_ui/theme/reader_frosted_popup.dart';

import '../library/library_store.dart';

Future<bool> confirmDeleteBookTag(BuildContext context, BookTag tag) =>
    showReaderConfirmDialog(
      context: context,
      title: '删除标签「${tag.name}」？',
      message: '将从所有书籍和标签堆叠中移除此标签，并更新本机 EPUB 中的标签。书籍、阅读进度和笔记会保留。',
      confirmLabel: '删除标签',
      confirmKey: const ValueKey('delete-tag-confirm'),
      destructive: true,
    );
