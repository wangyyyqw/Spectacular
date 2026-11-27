import 'package:flutter/material.dart';
import 'package:reader_core/css/font_face.dart';

import 'reader_ui_style.dart';

/// 应用字体与正文字体共用的试读样本，字体加载与选择由调用方管理。
class ReaderFontPreview extends StatelessWidget {
  const ReaderFontPreview({
    super.key,
    required this.sample,
    required this.family,
    this.fallback,
    this.textKey,
  });

  final String sample;
  final String? family;
  final List<String>? fallback;
  final Key? textKey;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: ReaderUiStyle.controlRadius,
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Text(
        sample,
        key: textKey,
        style: TextStyle(
          fontFamily: family == null
              ? null
              : FontFamilyAliases.resolve(family!) ?? family,
          fontFamilyFallback: fallback,
          fontSize: 18,
          height: 1.6,
        ),
      ),
    );
  }
}
