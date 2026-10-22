import 'package:flutter/material.dart';
import 'package:reader_core/reader_core.dart';
import 'package:reader_ui/reader_ui.dart';

void main() {
  // 依赖引用放在启动路径，确保三包在编译期真正连通。
  assert(readerCorePackageName == 'reader_core');
  assert(readerUiPackageName == 'reader_ui');
  runApp(const ReaderApp());
}

/// 应用壳：M0 之前只提供空白页，后续由 P1 接入阅读视图。
class ReaderApp extends StatelessWidget {
  const ReaderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'Spectacular Reader',
      home: Scaffold(body: SizedBox.shrink()),
    );
  }
}
