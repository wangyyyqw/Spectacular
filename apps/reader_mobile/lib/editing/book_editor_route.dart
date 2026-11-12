import 'dart:io';

import 'package:flutter/material.dart';
import 'package:reader_core/editing/epub_editing.dart';
import 'package:reader_ui/reader_page.dart';

import 'book_edit_repository.dart';
import 'book_editor_controller.dart';
import 'book_editor_page.dart';
import 'book_editor_tools.dart';
import 'epub_export.dart';
import '../reader/reader_settings.dart';

/// 宿主边界：草稿、导出与书库提交不进入通用阅读 UI。
class BookEditorRoute extends StatefulWidget {
  const BookEditorRoute({
    super.key,
    required this.repository,
    required this.bookId,
    required this.sourcePath,
    required this.contentRevision,
    required this.title,
    this.target,
    this.readingSettings,
    this.editInitialTarget = false,
  });
  final BookEditRepository repository;
  final String bookId;
  final String sourcePath;
  final String contentRevision;
  final String title;
  final ReaderEditTarget? target;
  final ReaderSettings? readingSettings;
  final bool editInitialTarget;

  @override
  State<BookEditorRoute> createState() => _BookEditorRouteState();
}

class _BookEditorRouteState extends State<BookEditorRoute> {
  BookEditorController? _controller;
  String? _error;
  Set<String> _versions = {};
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    if (_opening) return;
    _opening = true;
    EpubEditSession? opened;
    if (mounted) setState(() => _error = null);
    try {
      final draft = await widget.repository.openDraft(widget.bookId);
      if (draft != null && draft.baseRevision != widget.contentRevision) {
        throw StateError('草稿属于旧版书籍；请保留备份后丢弃旧草稿再编辑');
      }
      final session = await EpubEditSession.open(
        draft?.sourceFile ?? File(widget.sourcePath),
        draft: draft?.data,
        readBlob: draft?.readBlob,
      );
      opened = session;
      if (!mounted) {
        session.close();
        return;
      }
      final versions = await widget.repository.versions(widget.bookId);
      if (!mounted) {
        session.close();
        return;
      }
      _versions = versions.map((version) => version.kind).toSet();
      final rawBuffers = draft?.data['uiBuffers'];
      final buffers = rawBuffers is Map
          ? rawBuffers.cast<String, String>()
          : <String, String>{};
      final controller = BookEditorController(
        session: session,
        initialTarget: widget.target,
        readingSettings: widget.readingSettings,
        editInitialTarget: widget.editInitialTarget,
        discardDraft: () => widget.repository.discardDraft(widget.bookId),
        recovered: draft != null,
        buffers: buffers,
        saveDraft: (session, buffers) => widget.repository.saveDraft(
          widget.bookId,
          widget.contentRevision,
          (storeBlob) => {
            ...session.toDraft(storeBlob: storeBlob),
            'uiBuffers': buffers,
          },
        ),
        commit: (session) => _write(session, commit: true),
        export: (session) => _write(session),
      );
      setState(() {
        _controller = controller;
        _error = null;
      });
      opened = null;
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      opened?.close();
      _opening = false;
    }
  }

  Future<void> _exportRecovery() async {
    if (_opening) return;
    setState(() => _opening = true);
    EpubEditSession? session;
    try {
      final draft = await widget.repository.readDraftForRecovery(widget.bookId);
      if (draft == null) throw StateError('没有可导出的旧草稿');
      session = await EpubEditSession.open(
        draft.sourceFile,
        draft: draft.data,
        readBlob: draft.readBlob,
      );
      await _write(session);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('旧草稿的有效内容已导出；未完成源码仍保留在本地草稿中')),
        );
      }
    } on EditorExportCancelled {
      // 用户取消文件选择时保留草稿与当前恢复提示。
    } catch (error) {
      if (mounted) setState(() => _error = '旧草稿未能导出：$error');
    } finally {
      session?.close();
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _discardRecovery() async {
    if (_opening ||
        !await editorConfirm(
          context,
          '丢弃旧草稿？',
          '旧草稿及其中未完成的源码会被删除，当前书籍不变。请先导出需要保留的内容。',
        )) {
      return;
    }
    try {
      await widget.repository.discardDraft(widget.bookId);
      await _open();
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  Future<void> _write(EpubEditSession session, {bool commit = false}) async {
    final directory = await EpubExport.createTemporaryDirectory();
    final file = File('${directory.path}/edited.epub');
    try {
      await EpubWriter.write(session, file);
      if (commit) {
        await widget.repository.commitEditedFile(
          widget.bookId,
          widget.contentRevision,
          file,
          session.summary,
        );
      } else {
        final title = widget.title.replaceAll(RegExp(r'[/\\:*?"<>|]'), '_');
        if (!await EpubExport.save(file, fileName: '$title.epub')) {
          throw const EditorExportCancelled();
        }
      }
    } finally {
      await directory.delete(recursive: true);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller != null) {
      return BookEditorPage(
        controller: controller,
        title: widget.title,
        restoreOriginal: _versions.contains('original')
            ? () async {
                await widget.repository.restoreOriginal(
                  widget.bookId,
                  widget.contentRevision,
                );
              }
            : null,
        restorePrevious: _versions.contains('previous')
            ? () async {
                await widget.repository.restorePrevious(
                  widget.bookId,
                  widget.contentRevision,
                );
              }
            : null,
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('打开编辑器')),
      body: Center(
        child: _error == null
            ? const CircularProgressIndicator()
            : Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!),
                    TextButton(
                      onPressed: _opening ? null : _open,
                      child: const Text('重试'),
                    ),
                    TextButton(
                      onPressed: _opening ? null : _exportRecovery,
                      child: const Text('导出旧草稿 EPUB'),
                    ),
                    TextButton(
                      onPressed: _opening ? null : _discardRecovery,
                      child: const Text('丢弃旧草稿并打开当前书籍'),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
