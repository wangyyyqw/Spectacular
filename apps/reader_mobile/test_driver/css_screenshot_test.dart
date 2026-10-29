import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

/// 保存真机原始截图及结构化断言数据，输出目录由宿主指定。
Future<void> main() async {
  final output = Directory(
    Platform.environment['CSS_DEVICE_OUTPUT'] ?? 'build/css-device-results',
  );
  await output.create(recursive: true);
  await integrationDriver(
    onScreenshot: (name, bytes, [args]) async {
      await File('${output.path}/$name.png').writeAsBytes(bytes);
      return true;
    },
    responseDataCallback: (data) async {
      final report = Map<String, dynamic>.from(data ?? <String, dynamic>{})
        ..remove('screenshots');
      await File('${output.path}/report.json')
          .writeAsString(const JsonEncoder.withIndent('  ').convert(report));
    },
    writeResponseOnFailure: true,
  );
}
