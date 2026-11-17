import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/css.dart';
import 'package:re_highlight/languages/xml.dart';
import 'package:re_highlight/styles/github.dart';
import 'package:reader_ui/icons/app_icon.dart';

import 'book_editor_controller.dart';
import 'xhtml_chunk_analyzer.dart';

/// ReEditor 保持每份文档独立缓冲、选择范围和撤销栈。
class BookEditorSource extends StatelessWidget {
  const BookEditorSource({super.key, required this.controller, this.onLocate});
  final BookEditorController controller;
  final VoidCallback? onLocate;

  @override
  Widget build(BuildContext context) {
    final document = controller.activeDocument;
    return Column(
      children: [
        SizedBox(
          height: 44,
          child: Row(
            children: [
              Expanded(
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final doc in controller.documents.values)
                      InputChip(
                        key: ValueKey('document-${doc.path}'),
                        selected: doc.path == controller.activePath,
                        label: Text(
                          '${doc.path.split('/').last}${controller.documentDirty(doc.path) ? ' •' : ''}',
                        ),
                        onPressed: () => controller.openDocument(doc.path),
                        deleteIcon: const AppIcon(AppGlyph.close),
                        onDeleted: () => controller.closeDocument(doc.path),
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '定位到预览',
                onPressed: document == null || controller.busy
                    ? null
                    : onLocate,
                icon: const AppIcon(AppGlyph.locate),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        if (document == null)
          const Expanded(child: Center(child: Text('从文件列表打开 XHTML、CSS 或包文件')))
        else ...[
          if (document.error != null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                '校验未通过，预览保留上次有效内容。\n${document.error}',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          Expanded(
            child: CodeEditor(
              key: ValueKey(document.path),
              controller: document.code,
              autofocus: false,
              wordWrap: false,
              chunkAnalyzer: document.path.toLowerCase().endsWith('.css')
                  ? const DefaultCodeChunkAnalyzer()
                  : const XhtmlChunkAnalyzer(),
              padding: const EdgeInsets.all(12),
              style: CodeEditorStyle(
                fontSize: 14,
                codeTheme: CodeHighlightTheme(
                  languages: {
                    if (document.path.toLowerCase().endsWith('.css'))
                      'css': CodeHighlightThemeMode(mode: langCss)
                    else
                      'xml': CodeHighlightThemeMode(mode: langXml),
                  },
                  theme: githubTheme,
                ),
              ),
              indicatorBuilder: (context, editing, chunks, notifier) => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DefaultCodeLineNumber(
                    controller: editing,
                    notifier: notifier,
                  ),
                  DefaultCodeChunkIndicator(
                    width: 20,
                    controller: chunks,
                    notifier: notifier,
                  ),
                ],
              ),
              findBuilder: (context, find, readOnly) =>
                  EditorFindBar(controller: find),
            ),
          ),
        ],
      ],
    );
  }
}

class EditorFindBar extends StatelessWidget implements PreferredSizeWidget {
  const EditorFindBar({super.key, required this.controller});
  final CodeFindController controller;

  @override
  Size get preferredSize => const Size.fromHeight(108);

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<CodeFindValue?>(
    valueListenable: controller,
    builder: (context, value, _) => Column(
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller.findInputController,
                focusNode: controller.findInputFocusNode,
                decoration: const InputDecoration(labelText: '文档内查找'),
                onSubmitted: (_) => controller.nextMatch(),
              ),
            ),
            IconButton(
              tooltip: '上一处',
              onPressed: controller.previousMatch,
              icon: const AppIcon(AppGlyph.chevronUp),
            ),
            IconButton(
              tooltip: '下一处',
              onPressed: controller.nextMatch,
              icon: const AppIcon(AppGlyph.chevronDown),
            ),
            IconButton(
              tooltip: '关闭查找',
              onPressed: controller.close,
              icon: const AppIcon(AppGlyph.close),
            ),
          ],
        ),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller.replaceInputController,
                focusNode: controller.replaceInputFocusNode,
                decoration: const InputDecoration(labelText: '替换为'),
              ),
            ),
            TextButton(
              onPressed: controller.replaceMatch,
              child: const Text('替换'),
            ),
            TextButton(
              onPressed: controller.replaceAllMatches,
              child: const Text('全部'),
            ),
          ],
        ),
      ],
    ),
  );
}
