import 'package:flutter/material.dart';
import 'package:reader_core/reader_core.dart';
import 'package:reader_ui/reader_ui.dart';

import 'reader/demo_source.dart';

void main() {
  // 依赖引用放在启动路径，确保三包在编译期真正连通。
  assert(readerCorePackageName == 'reader_core');
  assert(readerUiPackageName == 'reader_ui');
  runApp(const ReaderApp());
}

/// 应用壳：M0 最小阅读页（30 章纯文本示例）。
class ReaderApp extends StatelessWidget {
  const ReaderApp({super.key});

  static final ReaderProgressStore _store = MemoryReaderProgressStore();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Spectacular Reader',
      home: Scaffold(
        body: SafeArea(
          child: ReaderPage(
            source: DemoChapterSource(),
            store: _store,
            bookId: 'demo-30',
          ),
        ),
      ),
    );
  }
}
