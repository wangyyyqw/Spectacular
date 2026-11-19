import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/services.dart';
import 'package:reader_core/editing/epub_editing.dart';
import 'package:reader_core/epub/opf.dart';
import 'package:spectacular_epub_tools/local_epub_tools.dart';

import 'book_editor_controller.dart';

class BookEditorToolResult {
  const BookEditorToolResult(this.result, this.directory, this.applied);
  final LocalToolResult result;
  final Directory directory;
  final bool applied;

  Future<void> dispose() => directory.delete(recursive: true);
}

class BookEditorToolkit {
  const BookEditorToolkit(this.editor);
  final BookEditorController editor;

  Future<BookEditorToolResult?> run(
    LocalEpubTool tool, {
    Map<String, Object?> options = const {},
  }) async {
    BookEditorToolResult? result;
    await editor.runAsyncCommand(() async {
      final directory = await Directory.systemTemp.createTemp(
        'epub-local-tool-',
      );
      try {
        result = await _run(tool, options, directory);
      } catch (_) {
        await directory.delete(recursive: true);
        rethrow;
      }
    });
    return result;
  }

  Future<BookEditorToolResult> _run(
    LocalEpubTool tool,
    Map<String, Object?> options,
    Directory directory,
  ) async {
    final session = editor.session;
    final revision = session.revision;
    final snapshot = File('${directory.path}/working.epub');
    await EpubWriter.write(session, snapshot);
    final dictionary = await _dictionary(tool);
    final note = await rootBundle.load(
      'packages/spectacular_epub_tools/assets/note.png',
    );
    final output = tool == LocalEpubTool.split
        ? '${directory.path}/parts'
        : '${directory.path}/result.epub';
    final processed = await Isolate.run(
      () => executeLocalEpubTool(
        tool,
        input: snapshot.path,
        output: output,
        options: options,
        dictionary: dictionary,
        noteImage: note.buffer.asUint8List(
          note.offsetInBytes,
          note.lengthInBytes,
        ),
      ),
    );
    if (session.isClosed ||
        session.revision != revision ||
        editor.hasPendingText) {
      throw const EpubEditException('处理期间内容已变化，结果未应用，请重试');
    }
    if (tool.output == LocalToolOutput.workingCopy) {
      await _apply(processed, tool);
    }
    final applied = session.revision != revision;
    return BookEditorToolResult(processed, directory, applied);
  }

  Future<void> _apply(LocalToolResult result, LocalEpubTool tool) async {
    final candidate = await EpubEditSession.open(File(result.files.single));
    try {
      _preserveOwnership(candidate);
      editor.session.replaceWith(candidate, label: tool.label);
      if (editor.previewTarget case final target?) {
        if (target.spineIndex >= editor.session.spinePaths.length) {
          editor.previewTarget = null;
        }
      }
    } finally {
      candidate.close();
    }
  }

  void _preserveOwnership(EpubEditSession candidate) {
    final metadata = editor.session.metadata;
    final stylesheet = metadata['classStylesheet'] as String?;
    if (stylesheet == null) return;
    final before = _manifestPaths(editor.session);
    final after = _manifestPaths(candidate);
    final paths = {
      for (final entry in before.entries)
        if (after.containsKey(entry.key)) entry.value: after[entry.key]!,
    };
    final nextStylesheet = paths[stylesheet] ?? stylesheet;
    if (candidate.readBytes(nextStylesheet) == null) {
      throw const EpubEditException('处理结果丢失编辑器样式表，未应用');
    }
    final owners = [
      for (final owner in (metadata['classStyleOwners'] as List? ?? const []))
        ?_remapOwner(candidate, Map<String, dynamic>.from(owner as Map), paths),
    ];
    final next = {
      ...metadata,
      'classStylesheet': nextStylesheet,
      'classStyleOwners': owners,
    };
    candidate.transaction('保留样式归属', (tx) {
      tx.metadata
        ..clear()
        ..addAll(next);
      tx.writeText(
        'META-INF/spectacular-editor.json',
        jsonEncode({
          'version': 1,
          'classStylesheet': nextStylesheet,
          'classStyleOwners': owners,
        }),
      );
    });
  }

  Map<String, String> _manifestPaths(EpubEditSession session) => {
    for (final item in OpfParser.parse(
      session.readText(session.opfPath),
    ).manifest)
      item.id: resolvePath(item.href, session.opfPath),
  };

  Map<String, dynamic>? _remapOwner(
    EpubEditSession candidate,
    Map<String, dynamic> owner,
    Map<String, String> paths,
  ) {
    final path = paths[owner['path']] ?? owner['path'] as String;
    if (candidate.readBytes(path) == null) return null;
    final elements = candidate.editableDocument(path).elements.where((element) {
      final id = element.attributes['id'];
      final key = id?.isNotEmpty == true
          ? '${element.tag}#$id'
          : [...element.ancestors, element]
                .map(
                  (node) =>
                      '${node.qualifiedName}:${node.parent?.children.indexOf(node) ?? 0}',
                )
                .join('/');
      return key == owner['element'] &&
          element.classes.contains(owner['className']) &&
          element.attributes['style'] == owner['generatedStyle'];
    });
    if (elements.length != 1) return null;
    final element = elements.single;
    return {
      ...owner,
      'path': path,
      'signature': editDigest(
        '${element.qualifiedName}|${Map.of(element.attributes)..remove('style')}',
      ),
    };
  }

  Future<ChineseDictionary?> _dictionary(LocalEpubTool tool) => switch (tool) {
    LocalEpubTool.s2t => ChineseDictionary.load(
      ChineseConversion.simplifiedToTraditional,
    ),
    LocalEpubTool.t2s => ChineseDictionary.load(
      ChineseConversion.traditionalToSimplified,
    ),
    _ => Future.value(),
  };
}
