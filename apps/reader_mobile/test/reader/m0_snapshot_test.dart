import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/m0_snapshot.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('首版页序列 hash 与基线一致（CI 可跑）', () async {
    final snapshot = await buildM0Snapshot();
    final baselineFile = File('integration_test/m0_page_sequence.json');
    expect(baselineFile.existsSync(), isTrue, reason: '缺少页序列基线');
    final baseline =
        jsonDecode(baselineFile.readAsStringSync()) as Map<String, dynamic>;
    expect(snapshot.pages, hasLength(baseline['pageCount'] as int));
    expect(snapshot.hash, baseline['hash']);
  });
}
