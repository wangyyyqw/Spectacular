import 'package:flutter/material.dart';

/// 关闭水波、悬停与点击高亮的主题。
///
/// 用于不需要按压反馈的图标按钮和列表行：只保留点击行为与状态变化，
/// 不再在按下时出现灰色水波或高亮块。
ThemeData quietInk(ThemeData theme) => theme.copyWith(
  splashFactory: NoSplash.splashFactory,
  splashColor: Colors.transparent,
  highlightColor: Colors.transparent,
  hoverColor: Colors.transparent,
  focusColor: Colors.transparent,
);
