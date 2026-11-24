import 'package:flutter/material.dart';
import 'package:reader_ui/theme/reader_frosted_popup.dart';

import '../library/library_store.dart';

/// 每本重名图书单独选择，关闭弹窗等同取消本次导入。
Future<BookImportChoice> chooseBookImport(
  BuildContext context,
  BookImportConflict conflict,
) async =>
    await showReaderDialog<BookImportChoice>(
      context: context,
      builder: (context) => ReaderFrostedAlertDialog(
        title: const Text('导入重复图书'),
        content: Text(
          '本地存在相同书名或 UUID 的图书《${conflict.title}》，是否覆盖导入？\n覆盖后保留原书的阅读时长、进度、笔记、书签和书评。'
          '${conflict.books.length > 1 ? '\n存在多个版本，将覆盖匹配身份的图书或首个同名版本。' : ''}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(BookImportChoice.cancel),
            child: const Text('取消导入'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(BookImportChoice.independent),
            child: const Text('独立导入'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(context).pop(BookImportChoice.overwrite),
            child: const Text('覆盖导入'),
          ),
        ],
      ),
    ) ??
    BookImportChoice.cancel;
