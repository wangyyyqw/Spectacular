import 'package:flutter/material.dart';

/// 翻页原型：200 个静态页，验证页码与内容一致、连续翻页不错位。
///
/// 帧率验收需要真机 profile 模式，尚未完成（见交接文档 P0-15）。
class PagerDemoPage extends StatefulWidget {
  /// 创建原型页面。
  const PagerDemoPage({super.key, this.pageCount = 200});

  /// 页数。
  final int pageCount;

  @override
  State<PagerDemoPage> createState() => _PagerDemoPageState();
}

class _PagerDemoPageState extends State<PagerDemoPage> {
  late final PageController _controller;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _controller = PageController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('翻页原型（P0-15） 第 ${_currentPage + 1}/${widget.pageCount} 页'),
      ),
      body: PageView.builder(
        controller: _controller,
        itemCount: widget.pageCount,
        onPageChanged: (page) => setState(() => _currentPage = page),
        itemBuilder: (context, index) {
          return ColoredBox(
            color: index.isEven
                ? const Color(0xFFF5F0E6)
                : const Color(0xFFEDE3D2),
            child: Center(
              child: Text(
                '第 ${index + 1} 页',
                style: const TextStyle(fontSize: 32),
              ),
            ),
          );
        },
      ),
    );
  }
}
