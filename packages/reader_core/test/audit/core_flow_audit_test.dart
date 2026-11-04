import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/epub/epub_document.dart';
import 'package:reader_core/epub/importer.dart';
import 'package:reader_core/epub/toc_cfi.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/text_layout.dart';
import 'package:reader_core/parser/document_parser.dart';
import 'package:reader_core/position/cfi.dart';

import 'audit_epub_fixture.dart';

PageBlock _pageBlock(String text, {bool before = false, bool after = false}) =>
    PageBlock(
      layout: TextLayoutEngine.layout(
        text: text,
        style: ComputedStyle(const {
          'font-size': '16px',
          'line-height': '1.5',
          'font-family': 'Ahem',
        }),
        maxWidth: 400,
      ),
      pageBreakBefore: before,
      pageBreakAfter: after,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('完整 EPUB 导入后元信息、正文和目录可相互定位', () async {
    final result = await openEpub(auditEpub());
    addTearDown(() => result.document?.archive.close());
    expect(result.ok, isTrue, reason: result.report.message);
    expect(result.report.readabilityLevel, EpubReadability.l0);
    final document = result.document!;
    expect(document.meta.title, '审计样本');
    expect(document.meta.author, '审计作者');
    expect(document.spine, hasLength(2));
    expect(document.parseDocument(0).plainText, auditFirstText);
    expect(document.parseDocument(1).plainText, auditSecondText);
    expect(await document.countChapterCharacters(), [
      auditFirstText.length,
      auditSecondText.length,
    ]);
    expect(document.tocSource, 'nav');
    expect(document.toc.map((entry) => entry.title), ['甲章', '乙章']);
    final bound = TocCfiBinder.bind(
      archive: document.archive,
      spine: document.spine,
      opfPath: document.opfPath,
      toc: document.toc,
    );
    expect(bound.bound, 2);
    expect(bound.missing, 0);
    for (var index = 0; index < bound.toc.length; index++) {
      final entry = bound.toc[index];
      expect(entry.spineIndex, index);
      final node = document.parseDocument(index).nodeAtCfi(entry.cfi!);
      expect(node, isA<ParsedElement>());
      expect((node! as ParsedElement).id, index == 0 ? 'first' : 'second');
    }
  });

  test('非 ZIP 输入返回拒绝报告且没有文档或未捕获异常', () async {
    final result = await openEpub(Uint8List.fromList(List.filled(64, 0x21)));
    expect(result.ok, isFalse);
    expect(result.document, isNull);
    expect(result.report.errorCode, 'E_ARCHIVE');
    expect(result.report.readabilityLevel, EpubReadability.l4);
    expect(result.report.message, isNotEmpty);
  });

  test('缺失一个章节时保留可读正文并报告 L2', () async {
    final result = await openEpub(auditEpub(missingSecondChapter: true));
    addTearDown(() => result.document?.archive.close());
    expect(result.ok, isTrue);
    expect(result.report.readabilityLevel, EpubReadability.l2);
    expect(result.report.warnings, contains('E_SPINE_MISSING: 1 个章节文件不存在'));
    expect(result.document!.parseDocument(0).plainText, auditFirstText);
    expect(result.document!.chapterXhtml(1), isNull);
  });

  test('没有 OPF 的 EPUB 以章节拼装恢复为 L3，正文顺序稳定', () async {
    final result = await openEpub(
      auditZip({
        'mimetype': 'application/epub+zip',
        'chapter02.xhtml': auditChapter('second', auditSecondText),
        'chapter01.xhtml': auditChapter('first', auditFirstText),
      }),
    );
    addTearDown(() => result.document?.archive.close());
    expect(result.ok, isTrue);
    expect(result.report.readabilityLevel, EpubReadability.l3);
    expect(result.document!.toc, hasLength(2));
    expect(result.document!.parseDocument(0).plainText, auditFirstText);
    expect(result.document!.parseDocument(1).plainText, auditSecondText);
    expect(
      result.report.warnings.any(
        (warning) => warning.startsWith('E_CONTAINER_FALLBACK:'),
      ),
      isTrue,
    );
  });

  test('解析期绑定 CFI 序列化往返后仍定位到相同文本与偏移', () async {
    final result = await openEpub(auditEpub());
    addTearDown(() => result.document?.archive.close());
    final document = result.document!;
    final chapter = document.parseDocument(1);
    final original = chapter.textNodes.single.cfi.withCharOffset(3);
    final restored = EpubCfi.parse(original.serialize());
    expect(restored, isNotNull);
    expect(restored!.serialize(), original.serialize());
    expect(spineIndexOfCfi(restored), 1);
    expect(chapter.nodeAtCfi(restored), same(chapter.textNodes.single));
    final resolved = document.resolveCfi(1, restored);
    expect(resolved.exact, isTrue);
    expect(resolved.textOffset, 3);
    expect(resolved.cfi!.serialize(), original.serialize());
    expect(resolved.warnings, isEmpty);
  });

  test('CFI 越界偏移钳制，跨章定位拒绝，非法字符串不抛异常', () async {
    final result = await openEpub(auditEpub());
    addTearDown(() => result.document?.archive.close());
    final document = result.document!;
    final target = document
        .parseDocument(0)
        .textNodes
        .single
        .cfi
        .withCharOffset(999);
    final resolved = document.resolveCfi(0, target);
    expect(resolved.ok, isTrue);
    expect(resolved.adjusted, isTrue);
    expect(resolved.textOffset, auditFirstText.length);
    expect(resolved.warnings, isNotEmpty);
    expect(document.resolveCfi(1, target).ok, isFalse);
    expect(EpubCfi.parse('epubcfi(/6/2!/4/2[unclosed)'), isNull);
  });

  test('文本跨页后每行恰好出现一次，重组正文无丢失且页高受限', () {
    const text = 'alpha\nbeta\ngamma\ndelta\nepsilon';
    final block = _pageBlock(text);
    final result = Paginator(
      pageHeight: 48,
      tolerance: 0,
    ).measureChapter(blocks: [block], spineIndex: 1);
    expect(result.pages, hasLength(3));
    final lineIndexes = <int>[];
    final reconstructed = StringBuffer();
    for (var index = 0; index < result.pages.length; index++) {
      final page = result.pages[index];
      expect(page.pageIndex, index);
      expect(page.spineIndex, 1);
      expect(page.isEmpty, isFalse);
      expect(page.usedHeight, lessThanOrEqualTo(48));
      for (final slice in page.slices) {
        for (var line = slice.startLine; line < slice.endLine; line++) {
          lineIndexes.add(line);
        }
        for (final line in slice.lines) {
          reconstructed.write(text.substring(line.start, line.end));
        }
      }
    }
    expect(lineIndexes, [0, 1, 2, 3, 4]);
    expect(
      reconstructed.toString().replaceAll('\n', ''),
      text.replaceAll('\n', ''),
    );
  });

  test('相邻强制分页与空块不生成空页或重复正文', () {
    final first = _pageBlock('甲', after: true);
    final second = _pageBlock('乙', before: true);
    final result = Paginator(
      pageHeight: 72,
    ).measureChapter(blocks: [_pageBlock(''), first, second, _pageBlock('')]);
    expect(result.pages, hasLength(2));
    expect(result.pages[0].slices.single.block, same(first));
    expect(result.pages[1].slices.single.block, same(second));
    expect(result.pages.every((page) => !page.isEmpty), isTrue);
  });
}
