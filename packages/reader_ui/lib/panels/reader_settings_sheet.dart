import 'package:flutter/material.dart';

import '../theme/reader_frosted_surface.dart';
import '../theme/reader_ui_style.dart';

/// 设置菜单共用的固定高度面板，内容可滚动，保存按钮固定在底部。
class ReaderSettingsSheet extends StatelessWidget {
  const ReaderSettingsSheet({
    super.key,
    required this.header,
    required this.child,
    required this.footer,
  });

  final Widget header;
  final Widget child;
  final Widget footer;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: MediaQuery.sizeOf(context).height * .64,
    child: Material(
      color: ReaderFrostedSurface.panelColorOf(context),
      borderRadius: ReaderUiStyle.sheetRadius,
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: header,
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: child,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: footer,
            ),
          ],
        ),
      ),
    ),
  );
}
