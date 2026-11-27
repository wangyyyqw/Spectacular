import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// 在线与本地释义共用的只读页面设置，调用方保留各自的导航策略。
InAppWebViewSettings dictionaryWebViewSettings({
  bool disableContextMenu = false,
  MixedContentMode? mixedContentMode,
}) => InAppWebViewSettings(
  javaScriptEnabled: false,
  javaScriptCanOpenWindowsAutomatically: false,
  allowFileAccess: false,
  allowContentAccess: false,
  allowFileAccessFromFileURLs: false,
  allowUniversalAccessFromFileURLs: false,
  useShouldOverrideUrlLoading: true,
  transparentBackground: true,
  useHybridComposition: true,
  disableVerticalScroll: false,
  disableHorizontalScroll: true,
  verticalScrollBarEnabled: true,
  horizontalScrollBarEnabled: false,
  supportZoom: false,
  textZoom: 100,
  disableContextMenu: disableContextMenu,
  mixedContentMode: mixedContentMode,
);
