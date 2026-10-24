import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/paint/page_snapshot.dart';

import 'snapshot_harness.dart';

const _spec = SnapshotSpec(
  pageWidth: 320,
  pageHeight: 600,
  devicePixelRatio: 2,
  fontSize: 16,
  lineHeight: 1.5,
  margin: 12,
);

const _baselinePath = 'test/snapshot/baseline/book_snapshot.json';

const List<SnapshotPage> _textPages = <SnapshotPage>[
  SnapshotPage(text: '第一章　　山中有雾，雾里有灯。', annotations: <String>['a1']),
  SnapshotPage(text: '第二章　　灯下有人，人读旧书。'),
  SnapshotPage(text: '第三章　　书页翻过去，风从窗外来。'),
];

const SnapshotConfig _config = SnapshotConfig(
  pageWidth: 390,
  pageHeight: 844,
  devicePixelRatio: 3,
  fontFamily: 'SourceHanSerifSC',
  fontSize: 18,
  lineHeight: 1.6,
  language: 'zh-CN',
);

Future<void> _loadFont() async {
  final bytes = await File('../../test_fonts/SourceHanSerifSC-Regular.otf')
      .readAsBytes();
  await (FontLoader(
    _spec.fontFamily,
  )..addFont(Future<ByteData>.value(ByteData.view(bytes.buffer)))).load();
}

/// 比较当前快照与基线，返回第一处差异描述（一致时返回 null）。
String? describeFirstDifference(
  Map<String, Object?> current,
  Map<String, dynamic> baseline,
) {
  final currentPages = (current['pages'] as List).cast<Map<String, Object?>>();
  final basePages = (baseline['pages'] as List).cast<Map<String, dynamic>>();
  final count = currentPages.length < basePages.length
      ? currentPages.length
      : basePages.length;
  for (var i = 0; i < count; i++) {
    final page = currentPages[i];
    final base = basePages[i];
    if (page['layoutHash'] != base['layoutHash']) {
      return '首个不同页号 $i：版式哈希 ${page['layoutHash']} != '
          '${base['layoutHash']}；像素差 '
          '${(page['inkPixels'] as int) - (base['inkPixels'] as int)}'
          '（当前 ${page['inkPixels']} / 基线 ${base['inkPixels']}）；'
          '摘要 ${page['summary'] ?? ''}';
    }
  }
  if (currentPages.length != basePages.length) {
    return '页数变化：当前 ${currentPages.length} / 基线 ${basePages.length}';
  }
  return null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('页序列哈希（文本级）', () {
    test('同一配置与页序列两次哈希一致', () {
      final first = PageSnapshot.hash(_textPages, _config);
      final second = PageSnapshot.hash(_textPages, _config);
      expect(first, second);
      expect(first, hasLength(64));
    });

    test('字号/DPR/视口/页序/文本变化都会改变哈希', () {
      const changed = SnapshotConfig(
        pageWidth: 360,
        pageHeight: 800,
        devicePixelRatio: 2,
        fontFamily: 'SourceHanSerifSC',
        fontSize: 20,
        lineHeight: 1.6,
        language: 'zh-CN',
      );
      expect(
        PageSnapshot.hash(_textPages, _config),
        isNot(PageSnapshot.hash(_textPages, changed)),
      );
      expect(
        PageSnapshot.hash(_textPages, _config),
        isNot(
          PageSnapshot.hash(
            _textPages.reversed.toList(growable: false),
            _config,
          ),
        ),
      );
    });
  });

  group('差异报告', () {
    test('首个不同页号与像素差', () {
      const current = <String, Object?>{
        'pages': <Object?>[
          <String, Object?>{'index': 0, 'layoutHash': 'a', 'inkPixels': 100},
          <String, Object?>{'index': 1, 'layoutHash': 'b', 'inkPixels': 120},
        ],
      };
      const baseline = <String, dynamic>{
        'pages': <Object?>[
          <String, dynamic>{'index': 0, 'layoutHash': 'a', 'inkPixels': 100},
          <String, dynamic>{'index': 1, 'layoutHash': 'x', 'inkPixels': 90},
        ],
      };
      final message = describeFirstDifference(current, baseline);
      expect(message, isNotNull);
      expect(message, contains('首个不同页号 1'));
      expect(message, contains('像素差 30'));
    });

    test('页数变化也能报告', () {
      const current = <String, Object?>{
        'pages': <Object?>[
          <String, Object?>{'index': 0, 'layoutHash': 'a', 'inkPixels': 1},
        ],
      };
      const baseline = <String, dynamic>{'pages': <Object?>[]};
      expect(describeFirstDifference(current, baseline), contains('页数变化'));
    });
  });

  group('整书渲染快照（P2-25）', () {
    late Uint8List bookBytes;
    late BookSnapshot snapshot;

    setUpAll(() async {
      await _loadFont();
      bookBytes = buildSnapshotEpub();
      snapshot = await snapshotBook(bookBytes, _spec);
    });

    test('重复运行生成相同整书哈希与页哈希', () async {
      final again = await snapshotBook(bookBytes, _spec);
      expect(again.bookHash, snapshot.bookHash);
      expect(again.pages.length, snapshot.pages.length);
      for (var i = 0; i < snapshot.pages.length; i++) {
        expect(again.pages[i].layoutHash, snapshot.pages[i].layoutHash);
        expect(again.pages[i].inkPixels, snapshot.pages[i].inkPixels);
      }
      expect(snapshot.pages, isNotEmpty, reason: '样本应至少分出一页');
    });

    test('与基线 JSON 一致（差异输出首个不同页号与像素差）', () async {
      final file = File(_baselinePath);
      if (Platform.environment['SNAPSHOT_UPDATE'] == '1') {
        file.parent.createSync(recursive: true);
        file.writeAsStringSync(
          const JsonEncoder.withIndent('  ').convert(snapshot.toJson()),
        );
      }
      expect(
        file.existsSync(),
        isTrue,
        reason:
            '基线缺失：运行 SNAPSHOT_UPDATE=1 flutter test '
            'test/snapshot/page_snapshot_test.dart 生成',
      );
      final baseline =
          jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      expect(snapshot.specId, baseline['specId'], reason: '快照配置变化，需更新基线');
      final diff = describeFirstDifference(snapshot.toJson(), baseline);
      expect(diff, isNull, reason: diff ?? '');
      expect(snapshot.bookHash, baseline['bookHash']);
    });
  });
}
