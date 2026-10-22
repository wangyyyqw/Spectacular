import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

/// 无障碍语义原型：5 个段落按阅读顺序暴露给读屏。
///
/// P0-21 用程序化语义树验证替代 TalkBack/VoiceOver 手工播报。
class SemanticsDemoPage extends StatelessWidget {
  /// 创建原型页面。
  const SemanticsDemoPage({super.key});

  /// 演示段落。
  static const List<String> paragraphs = <String>[
    '第一段：山中何所有，岭上多白云。',
    '第二段：只可自怡悦，不堪持赠君。',
    '第三段：白日依山尽，黄河入海流。',
    '第四段：欲穷千里目，更上一层楼。',
    '第五段：床前明月光，疑是地上霜。',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('无障碍语义原型（P0-21）')),
      body: ListView.builder(
        itemCount: paragraphs.length,
        itemBuilder: (context, index) {
          final text = paragraphs[index];
          return Semantics(
            container: true,
            excludeSemantics: true,
            sortKey: OrdinalSortKey(index.toDouble()),
            label: text,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(text, style: const TextStyle(fontSize: 18)),
            ),
          );
        },
      ),
    );
  }
}
