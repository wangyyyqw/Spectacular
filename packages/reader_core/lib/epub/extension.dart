import 'package:xml/xml.dart';

import '../src/api/models.dart';

/// 解析多看 `META-INF/duokan-extension.xml`。
///
/// 扩展文件是可选元数据：缺失时保持普通重排；损坏或未知值只产生可恢复
/// 警告，不阻断打开书籍。
abstract final class DuokanExtensionParser {
  /// 扩展文件在 ZIP 内的固定路径。
  static const String path = 'META-INF/duokan-extension.xml';

  /// 解析扩展文件；[xmlText] 为 null 表示文件不存在。
  static EpubExtensionConfig parse(String? xmlText) {
    if (xmlText == null) {
      return EpubExtensionConfig.none;
    }
    final warnings = <String>[];
    final XmlDocument document;
    try {
      document = XmlDocument.parse(_stripBom(xmlText));
    } on FormatException catch (error) {
      warnings.add('E_DUOKAN_EXTENSION_XML: 扩展 XML 解析失败：${error.message}');
      return EpubExtensionConfig(
        sourceFound: true,
        warnings: List<String>.unmodifiable(warnings),
      );
    }
    final root = document.childElements.firstOrNull;
    if (root == null) {
      warnings.add('E_DUOKAN_EXTENSION_XML: 扩展 XML 没有根元素，按 reflow 处理');
      return EpubExtensionConfig(
        sourceFound: true,
        warnings: List<String>.unmodifiable(warnings),
      );
    }
    if (root.name.local != 'duokan-extension') {
      warnings.add(
        'E_DUOKAN_EXTENSION_XML: 扩展根元素应为 duokan-extension，'
        '实际为 ${root.name.local}',
      );
      return EpubExtensionConfig(
        sourceFound: true,
        warnings: List<String>.unmodifiable(warnings),
      );
    }

    final display = _firstChild(root, 'display-options');
    final layout = _parseLayout(display, warnings);
    final pageWidth = _parseDimension(display, 'page-width', warnings);
    final pageHeight = _parseDimension(display, 'page-height', warnings);
    return EpubExtensionConfig(
      layout: layout,
      pageWidth: pageWidth,
      pageHeight: pageHeight,
      sourceFound: true,
      warnings: List<String>.unmodifiable(warnings),
    );
  }

  static EpubLayoutType _parseLayout(
    XmlElement? display,
    List<String> warnings,
  ) {
    final element = display?.childElements
        .where((element) => element.name.local == 'layout')
        .firstOrNull;
    if (element == null) {
      return EpubLayoutType.reflow;
    }
    final value = _elementValue(element).toLowerCase();
    if (value.isEmpty) {
      warnings.add(
        'E_DUOKAN_EXTENSION_VALUE: display-options/layout 为空，按 reflow 处理',
      );
      return EpubLayoutType.reflow;
    }
    for (final layout in EpubLayoutType.values) {
      if (layout.token == value) {
        return layout;
      }
    }
    warnings.add('E_DUOKAN_EXTENSION_VALUE: 未知多看布局 $value，按 reflow 处理');
    return EpubLayoutType.reflow;
  }

  static double? _parseDimension(
    XmlElement? display,
    String name,
    List<String> warnings,
  ) {
    if (display == null) {
      return null;
    }
    final option = display.childElements
        .where(
          (element) =>
              element.name.local == 'option' &&
              element.getAttribute('name')?.trim() == name,
        )
        .firstOrNull;
    if (option == null) {
      return null;
    }
    final raw = _elementValue(option);
    final value = double.tryParse(raw);
    if (value == null || !value.isFinite || value <= 0) {
      warnings.add('E_DUOKAN_EXTENSION_VALUE: $name 值 "$raw" 非法，已忽略');
      return null;
    }
    return value;
  }

  static String _elementValue(XmlElement element) {
    final attribute = element.getAttribute('value')?.trim();
    if (attribute != null && attribute.isNotEmpty) {
      return attribute;
    }
    return element.innerText.trim();
  }

  static XmlElement? _firstChild(XmlElement parent, String localName) => parent
      .childElements
      .where((element) => element.name.local == localName)
      .firstOrNull;

  static String _stripBom(String value) =>
      value.startsWith('\uFEFF') ? value.substring(1) : value;
}
