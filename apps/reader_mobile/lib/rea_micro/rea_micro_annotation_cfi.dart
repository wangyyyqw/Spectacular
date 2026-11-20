import 'dart:io';

import 'package:reader_core/epub/epub_document.dart';
import 'package:reader_core/parser/external_annotation_cfi.dart';
import 'package:reader_core/position/cfi.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/epub/chapter/book_resources.dart';
import 'package:reader_core/epub/chapter/book_fonts.dart';
import 'package:reader_core/epub/chapter/chapter_styles.dart';
import 'package:reader_core/epub/chapter/chapter_raw_styles.dart';
import 'package:reader_core/epub/chapter/chapter_selectors.dart';
import 'package:reader_core/parser/block_builder.dart';
import 'package:reader_core/parser/document_parser.dart';

/// 一轮同步只读取涉及标注的章节，不长期保留第二套 DOM。
class ReaMicroAnnotationCfis {
  final _outgoing = <String, String>{};
  final _incoming = <String, String>{};

  static Future<ReaMicroAnnotationCfis> load(
    String path, {
    Iterable<String> local = const [],
    Iterable<String> remote = const [],
  }) async {
    final result = ReaMicroAnnotationCfis();
    try {
      final opened = await openEpubFile(File(path), verifyCrc: false);
      final document = opened.document;
      if (document == null) return result;
      final resources = BookResources(document);
      final fonts = BookFonts(resources, onFontsChanged: (_) {});
      final styles = ChapterStyles(resources, fonts);
      try {
        final chapters = <int, ExternalAnnotationCfi>{};
        Future<ExternalAnnotationCfi?> mapper(String cfi) async {
          final point = epubCfiCandidates(cfi).map(EpubCfi.parse).firstOrNull;
          final spine = point == null ? null : spineIndexOfCfi(point);
          if (spine == null || spine < 0 || spine >= document.spine.length) {
            return null;
          }
          final xhtml = document.chapterXhtml(spine);
          if (xhtml == null) return null;
          if (chapters.containsKey(spine)) return chapters[spine];
          final parsed = document.parseDocument(spine);
          final selectors = ChapterSelectors(
            parsed.root,
            htmlAttributes: parsed.htmlAttributes,
          );
          final sheets = await styles.prepareStylesheets(spine, width: 320);
          final raw = ChapterRawStyles(
            selectors,
            ComputedStyle({'font-size': '16px'}),
            320,
            sheets,
          );
          final computed = <String, ComputedStyle>{};
          void visit(ParsedElement element) {
            final node = BlockNode(
              tag: element.tag,
              display: DisplayMode.block,
              children: [],
              cfi: element.cfi,
              attributes: element.attributes,
              start: element.start,
              end: element.end,
            );
            computed[element.cfi.serialize()] = raw.styleOf(node);
            for (final child in element.children.whereType<ParsedElement>()) {
              visit(child);
            }
          }

          visit(parsed.root);
          return chapters.putIfAbsent(
            spine,
            () => ExternalAnnotationCfi(
              xhtml,
              isInline: (cfi) {
                final style = computed[cfi];
                if (style?['display'] != null) {
                  return style!.display == CssDisplay.inline;
                }
                final node = parsed.nodeAtCfi(EpubCfi.parse(cfi)!);
                return node is ParsedElement &&
                    const {
                      'span',
                      'a',
                      'b',
                      'i',
                      'em',
                      'strong',
                      'small',
                      'sup',
                      'sub',
                      'code',
                      'u',
                      's',
                      'c',
                      'ruby',
                      'rt',
                    }.contains(node.tag);
              },
              hasInlineDecoration: (cfi) {
                final style = computed[cfi];
                return style != null &&
                    (style.margin.left != 0 ||
                        style.margin.right != 0 ||
                        style.padding.left != 0 ||
                        style.padding.right != 0);
              },
            ),
          );
        }

        for (final cfi in local.toSet()) {
          final converted = (await mapper(cfi))?.toExternal(cfi);
          if (converted != null) result._outgoing[cfi] = converted;
        }
        for (final cfi in remote.toSet()) {
          final mapping = await mapper(cfi);
          final converted = mapping?.toLocal(cfi);
          if (converted != null) {
            result._incoming[cfi] = converted;
            final outgoing = mapping?.toExternal(converted);
            if (outgoing != null) result._outgoing[converted] = outgoing;
          }
        }
      } finally {
        styles.close();
        fonts.close();
        resources.close();
      }
    } on FileSystemException {
      // 原书不可用时保留端点，不猜测 DOM。
    } on FormatException {
      // 损坏章节保持待定位。
    } on StateError {
      // 不含正文的章节没有可转换的字符坐标。
    }
    return result;
  }

  String outgoing(String cfi) => _outgoing[cfi] ?? cfi;

  bool matches(String local, String remote) =>
      local == remote ||
      _incoming[remote] == local ||
      _outgoing[local] == remote ||
      epubCfiCandidates(remote).contains(local);
}
