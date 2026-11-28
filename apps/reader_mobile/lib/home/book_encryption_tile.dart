import 'dart:io';

import 'package:flutter/material.dart';
import 'package:reader_core/epub/encryption_inspector.dart';
import 'package:reader_core/epub/epub_document.dart';
import 'package:reader_ui/theme/reader_common_widgets.dart';

import '../library/library_store.dart';
import '../reader/reader_selection_ocr.dart';

/// 在详情页按需检测书库副本，结果仅保存在当前界面。
class BookEncryptionTile extends StatefulWidget {
  const BookEncryptionTile({
    super.key,
    required this.entry,
    required this.library,
  });

  final BookEntry entry;
  final LibraryStore library;

  @override
  State<BookEncryptionTile> createState() => _BookEncryptionTileState();
}

class _BookEncryptionTileState extends State<BookEncryptionTile> {
  EpubEncryptionReport? _report;
  bool _checking = false;
  String? _error;

  Future<void> _check() async {
    if (_checking) return;
    setState(() {
      _checking = true;
      _error = null;
    });
    try {
      final opened = widget.library.supportsPersistence
          ? await openEpubFile(File(widget.entry.filePath))
          : await openEpub(await widget.library.readBytes(widget.entry));
      final bool? requiresOcr;
      try {
        requiresOcr = opened.document == null
            ? false
            : await ReaderSelectionOcr().requiresOcr(opened.document!);
      } catch (_) {
        opened.document?.archive.close();
        rethrow;
      }
      var report = await EpubEncryptionInspector.inspectOpened(opened);
      if (requiresOcr != false) {
        report = EpubEncryptionReport(
          requiresOcr == true
              ? EpubEncryptionStatus.suspiciousFontMapping
              : EpubEncryptionStatus.inconclusive,
          [
            requiresOcr == true
                ? '书内字形与字符编码不一致；复制、划线、想法和选区编辑使用离线 OCR，装饰已禁用。'
                : '字体视觉复核未完成；阅读时文字操作使用 OCR，装饰暂不可用。',
            '识别结果可能有误字，编辑前请校对。',
            '不覆盖书内字体；搜索和朗读仍可能受原始编码影响。',
          ],
        );
      }
      if (mounted) setState(() => _report = report);
    } catch (_) {
      if (mounted) setState(() => _error = '检测失败，请重试');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) => ReaderOptionTile(
    tileKey: const ValueKey('book-encryption-check'),
    title: '加密检测',
    subtitle: _checking
        ? '正在检查加密声明与书内字体…'
        : _error ??
              (_report == null
                  ? '检查 DRM、字体混淆及字形映射'
                  : '${_report!.label}\n${_report!.details.join('\n')}'),
    trailing: TextButton(
      onPressed: _checking ? null : _check,
      child: Text(
        _checking
            ? '检测中…'
            : _report == null && _error == null
            ? '检测'
            : '重新检测',
      ),
    ),
  );
}
