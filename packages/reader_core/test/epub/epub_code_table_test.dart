import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/epub/epub_exception.dart';

/// P7-05：诊断码表防漂移——lib 内出现的每个错误码必须登记在
/// [EpubCodeTable]，且带分类/严重度/出处；预留码必须注明消费任务。
void main() {
  test('码表无重复且字段齐全', () {
    final codes = EpubCodeTable.specs.map((spec) => spec.code).toList();
    expect(codes.toSet().length, codes.length, reason: '码不允许重复');
    expect(codes.length, 30, reason: '现有 18 + 预留 12');
    for (final spec in EpubCodeTable.specs) {
      expect(spec.source, isNotEmpty, reason: '${spec.code} 缺出处');
      expect(
        spec.category,
        isNot(EpubErrorCategory.unknown),
        reason: '${spec.code} 分类不能是 unknown',
      );
      if (spec.isReserved) {
        expect(
          spec.reservedFor,
          matches(RegExp(r'^P\d-\d\d$')),
          reason: '${spec.code} 预留码需注明消费任务编号',
        );
      }
    }
  });

  test('lib 内全部码字面量已登记（防漂移）', () {
    final libDir = Directory('lib');
    expect(libDir.existsSync(), isTrue, reason: '需在包根目录运行');
    final used = <String>{};
    final pattern = RegExp(r"'(E_[A-Z_]+)'");
    for (final entity in libDir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) {
        continue;
      }
      for (final match in pattern.allMatches(entity.readAsStringSync())) {
        used.add(match.group(1)!);
      }
    }
    // 码表自身文件里的登记项也参与比对（登记但未用 = 预留，合法；
    // 使用但未登记 = 漂移，必须补表）。
    final registered =
        EpubCodeTable.specs.map((spec) => spec.code).toSet();
    final unregistered = used.difference(registered).difference({'E_'});
    expect(
      unregistered,
      isEmpty,
      reason: 'lib 内存在未登记码：$unregistered（码表见 EpubCodeTable）',
    );
    expect(used, isNot(contains('E_')), reason: '占位串不应出现在码位');
  });

  test('分类与严重度从码表派生', () {
    const archive = EpubException('E_ARCHIVE', '坏 ZIP');
    expect(archive.category, EpubErrorCategory.opening);
    expect(archive.severity, EpubErrorSeverity.fatal);

    const toc = EpubException('E_TOC_NCX_XML', 'NCX 损坏');
    expect(toc.severity, EpubErrorSeverity.recoverable);

    const spine = EpubException('E_SPINE_MISSING', '章节缺文件');
    expect(spine.category, EpubErrorCategory.resource);
    expect(spine.severity, EpubErrorSeverity.recoverable);

    const reserved = EpubException('E_FONT_UNSUPPORTED', 'ttc 不支持');
    expect(reserved.severity, EpubErrorSeverity.informational);
    expect(reserved.spec?.isReserved, isTrue);

    // 未登记码兜底：unknown + fatal（宁严勿漏）。
    const unknown = EpubException('E_NOT_REGISTERED', 'x');
    expect(unknown.category, EpubErrorCategory.unknown);
    expect(unknown.severity, EpubErrorSeverity.fatal);
    expect(unknown.spec, isNull);
  });

  test('toError 保留 detail 与 offset；toString 格式不变', () {
    const error = EpubException(
      'E_TOC_NAV_XML',
      'NAV 解析失败',
      detail: <String, Object?>{'path': 'nav.xhtml'},
      offset: 128,
    );
    final record = error.toError();
    expect(record.detail['path'], 'nav.xhtml');
    expect(record.offset, 128);
    expect(record.isFatal, isFalse);
    expect(error.toString(), 'EpubException(E_TOC_NAV_XML): NAV 解析失败');
  });

  test('码表条目可按码索引', () {
    expect(EpubCodeTable.byCode('E_OCF')?.severity, EpubErrorSeverity.fatal);
    expect(EpubCodeTable.byCode('E_IO_DISK_FULL')?.reservedFor, 'P4-03');
    expect(EpubCodeTable.byCode('E_NOPE'), isNull);
  });
}
