import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/api.dart';
import 'package:reader_core/epub/epub_document.dart';
import 'package:reader_core/parser/block_builder.dart';
import 'package:reader_core/parser/document_parser.dart';
import 'package:reader_core/parser/text_aggregator.dart';
import 'package:reader_core/position/cfi.dart';

import '../support/corpus.dart';

class _Checker {
  _Checker(this.book, this.spineIndex, this.itemref);
  final String book;
  final int spineIndex;
  final int itemref;
  final List<String> violations = <String>[];
  final Set<Object> _seen = <Object>{};

  String _where(String target) => '$book spine=$spineIndex $target';

  void check(bool condition, String message, {required String target}) {
    if (!condition) {
      violations.add(_where('$target: $message'));
    }
  }

  void checkCfi(EpubCfi cfi, {required String target}) {
    final serialized = cfi.serialize();
    final parsed = EpubCfi.parse(serialized);
    check(parsed != null, 'CFI 无法解析：$serialized', target: target);
    check(
      cfi.itemref == itemref,
      'itemref=${cfi.itemref}，期望 $itemref',
      target: target,
    );
  }

  void walkRaw(ParsedNode node, {String target = 'root'}) {
    check(_seen.add(node), '节点重复出现', target: target);
    checkCfi(node.cfi, target: target);
    if (node is ParsedText) {
      check(node.text.isNotEmpty, '文本节点为空串', target: target);
      check(node.start <= node.end, '源码位置倒置', target: target);
    } else if (node is ParsedElement) {
      for (var i = 0; i < node.children.length; i++) {
        walkRaw(
          node.children[i],
          target: '${node.tag}>${node.children[i].runtimeType}[$i]',
        );
      }
    }
  }
}

void main() {
  final corpus = findCorpusRoot();
  final skip = corpus == null ? '本地样本库缺失（test_corpus/ 不入库）' : null;

  test(
    '样本库全部书籍的文档树不变量',
    () async {
      final manifest = jsonDecode(
        File('${corpus!.path}/manifest.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      final samples = (manifest['samples'] as List)
          .cast<Map<String, dynamic>>();
      final allViolations = <String>[];
      var chapters = 0;

      for (final sample in samples) {
        final name = sample['file'] as String;
        final opened = await openEpub(readSampleBytes(corpus, name)!);
        final document = opened.document!;
        for (var i = 0; i < document.spine.length; i++) {
          final parsed = document.parseDocument(i);
          final checker = _Checker(name, i, (i + 1) * 2);
          checker.walkRaw(parsed.root);
          for (final text in parsed.textNodes) {
            checker.check(
              identical(parsed.nodeAtCfi(text.cfi), text),
              'nodeAtCfi 未命中原文本节点',
              target: 'text:${text.cfi.serialize()}',
            );
          }
          allViolations.addAll(checker.violations);

          final blocks = BlockBuilder.build(parsed);
          final aggregated = TextAggregator.aggregate(blocks);
          _checkAggregated(aggregated, name, i, allViolations);
          chapters += 1;
        }
      }

      // ignore: avoid_print
      print(
        'P1-17 books=${samples.length} chapters=$chapters violations=${allViolations.length}',
      );
      expect(allViolations, isEmpty, reason: allViolations.take(50).join('\n'));
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 15)),
  );
}

void _checkAggregated(
  BlockDocument document,
  String book,
  int spineIndex,
  List<String> violations,
) {
  final where = '$book spine=$spineIndex';
  void fail(String message) => violations.add('$where $message');
  EpubCfi? previous;

  void walk(EpubNode node, String path) {
    if (node is BlockNode) {
      if (previous != null && previous!.compareTo(node.cfi) >= 0) {
        fail('块节点 CFI 非单调：${previous!.serialize()} >= ${node.cfi.serialize()}');
      }
      previous = node.cfi;
      for (var i = 0; i < node.children.length; i++) {
        walk(node.children[i], '$path/${node.tag}[$i]');
      }
    } else if (node is InlineNode) {
      for (var i = 0; i < node.children.length; i++) {
        walk(node.children[i], '$path/${node.tag}[$i]');
      }
    } else if (node is TextContentNode) {
      if (node.text.isEmpty) {
        fail('聚合文本为空：$path');
      }
      if (node.runs.isEmpty) {
        fail('文本块缺少 runs：$path');
      }
      var last = 0;
      for (final run in node.runs) {
        if (run.start < last ||
            run.end < run.start ||
            run.end > node.text.length) {
          fail(
            'run 区间非法 [${run.start},${run.end}) len=${node.text.length}：$path',
          );
        }
        last = run.end;
      }
      for (final index in node.hardBreaks) {
        if (index < 0 ||
            index >= node.text.length ||
            node.text[index] != '\n') {
          fail('hardBreak 下标非法 $index：$path');
        }
      }
    }
  }

  walk(document.root, 'root');
  final expectedText = <String>[];
  void collect(EpubNode node) {
    if (node is TextContentNode) {
      expectedText.add(node.text);
    } else if (node is BlockNode) {
      node.children.forEach(collect);
    } else if (node is InlineNode) {
      node.children.forEach(collect);
    }
  }

  collect(document.root);
  if (document.plainText != expectedText.join()) {
    fail('plainText 与文本块不一致');
  }
}
