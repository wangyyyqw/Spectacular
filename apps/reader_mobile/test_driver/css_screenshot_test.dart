import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

/// 保存结构化断言数据；截图由 USB 宿主直接保存。
Future<void> main() async {
  final output = Directory(
    Platform.environment['CSS_DEVICE_OUTPUT'] ?? 'build/css-device-results',
  );
  await output.create(recursive: true);
  await integrationDriver(
    responseDataCallback: (data) async {
      final report = Map<String, dynamic>.from(data ?? <String, dynamic>{})
        ..remove('screenshots');
      await File('${output.path}/report.json')
          .writeAsString(const JsonEncoder.withIndent('  ').convert(report));
    },
    writeResponseOnFailure: true,
  );
}
