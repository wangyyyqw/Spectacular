import 'dart:convert';
import 'dart:typed_data';

import 'package:html/parser.dart' as html_parser;

/// 规范在线书籍字数，兼容 `12.3万`、`123456` 等常见站点写法。
String normalizeOnlineWordCount(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return '';
  final compact = text
      .replaceAll(',', '')
      .replaceAll(RegExp(r'\s+'), '')
      .replaceFirst(RegExp(r'^[.·•。:：]+'), '');
  if (RegExp(r'^[零〇一二三四五六七八九十百千万亿两]+(?:字)?$').hasMatch(compact)) {
    return '';
  }
  final unit = RegExp(r'^([0-9]+(?:\.[0-9]+)?)(万|亿)(?:字)?$')
      .firstMatch(compact);
  if (unit != null) {
    final number = _trimDecimal(unit.group(1)!);
    if (number.isEmpty || number == '0') return '';
    return '$number${unit.group(2)}字';
  }
  final plain = double.tryParse(compact.replaceFirst(RegExp(r'字$'), ''));
  if (plain == null) return text;
  if (plain <= 0) return '';
  if (plain >= 10000) {
    return '${_trimDecimal((plain / 10000).toStringAsFixed(1))}万字';
  }
  return '${_trimDecimal(plain.toStringAsFixed(0))}字';
}

/// 将书源名称归一为搜索结果中使用的平台简称。
String normalizeOnlinePlatformLabel(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return '';
  final lower = text.toLowerCase();
  const aliases = <String, String>{
    'qidian': '起点',
    '起点': '起点',
    'jinjiang': '晋江',
    '晋江': '晋江',
    'zongheng': '纵横',
    '纵横': '纵横',
    'xirang': '息壤',
    '息壤': '息壤',
    'youdu': '有毒',
    '有毒': '有毒',
    'faloo': '飞卢',
    '飞卢': '飞卢',
    'ciweimao': '刺猬猫',
    '刺猬猫': '刺猬猫',
    'fanqie': '番茄',
    '番茄': '番茄',
    'gongzicp': '长佩',
    '长佩': '长佩',
    'sfacg': '菠萝包',
    '菠萝包': '菠萝包',
  };
  for (final entry in aliases.entries) {
    if (lower.contains(entry.key)) return entry.value;
  }
  return text;
}

/// 解析章节数量；无法识别或非正数时返回 0。
int parseOnlineChapterCount(String raw) {
  final text = raw.trim().replaceAll(',', '').replaceAll('，', '');
  if (text.isEmpty) return 0;
  final match = RegExp(r'\d+').firstMatch(text);
  if (match == null) return 0;
  final value = int.tryParse(match.group(0)!) ?? 0;
  return value > 0 ? value : 0;
}

/// 将时间戳或常见日期文本格式化为 `yyyy MM dd`。
String formatOnlineUpdateTime(String raw) {
  final text = raw.trim();
  if (text.isEmpty || text == '0' || text.toLowerCase() == 'null') return '';
  final numeric = int.tryParse(text);
  if (numeric != null && numeric > 0) {
    final millis = numeric < 10000000000 ? numeric * 1000 : numeric;
    return _formatOnlineDate(
      DateTime.fromMillisecondsSinceEpoch(millis).toLocal(),
    );
  }
  final normalized = text
      .replaceFirst('T', ' ')
      .replaceFirst(RegExp(r'\.\d+Z?$'), '')
      .trim();
  final parsed = DateTime.tryParse(normalized);
  if (parsed != null) return _formatOnlineDate(parsed.toLocal());
  if (normalized.length < 8) return normalized;
  return normalized.substring(0, 10).replaceAll('-', ' ').replaceAll('/', ' ');
}

/// 在线搜索结果标签行：平台 / 状态 / 字数 / 章节数 / 更新时间。
String onlineSearchTagLine({
  String platformName = '',
  String sourceName = '',
  String status = '',
  String wordCount = '',
  int chapterCount = 0,
  String updateTime = '',
}) {
  final platform = normalizeOnlinePlatformLabel(
    platformName.trim().isNotEmpty ? platformName : sourceName,
  );
  final time = formatOnlineUpdateTime(updateTime);
  final values = <String>[
    platform,
    status.trim(),
    wordCount.trim(),
    if (chapterCount > 0) '$chapterCount章',
    time,
  ];
  final seen = <String>{};
  final parts = <String>[
    for (final value in values)
      if (value.isNotEmpty && seen.add(value)) value,
  ];
  return parts.isEmpty ? '详情加载中' : parts.join(' / ');
}

String _formatOnlineDate(DateTime value) {
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '${value.year.toString().padLeft(4, '0')} $month $day';
}

/// 将常见状态文本归一为连载、完结、断更或下架；无法识别时返回空串。
String normalizeOnlineStatus(String raw, {String lastChapter = ''}) {
  final text = raw.trim();
  if (text.contains('断更')) return '断更';
  if (text.contains('下架')) return '下架';
  if (text.contains('连载')) return '连载';
  if (text.contains('完结') || text.contains('已完')) return '完结';

  final inferred = _inferStatusFromChapter(lastChapter);
  if (inferred.isNotEmpty) return inferred;

  final normalized = text.toLowerCase();
  return switch (normalized) {
    '1' || 'serial' || 'ongoing' || 'false' => '连载',
    '0' ||
    '2' ||
    '3' ||
    '4' ||
    'finish' ||
    'finished' ||
    'complete' ||
    'completed' ||
    'true' => '完结',
    _ => '',
  };
}

/// 清理目录中的更新频率后缀，例如「第 12 章（三更）」。
String cleanOnlineChapterTitle(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return '';
  return text
      .replaceFirst(
        RegExp(r'\s*[（(]\s*[零〇一二三四五六七八九十百两0-9]+\s*更\s*[）)]\s*$'),
        '',
      )
      .trim();
}

/// 去掉正文末尾的「本章完」标记。
String cleanOnlineChapterContent(String raw) {
  return raw.replaceAll(RegExp(r'[（(]\s*本[章韋韦]完\s*[）)]'), ' ').trim();
}

/// 解码简介中的常见 HTML 实体，并收拢模板产生的多余空行。
String normalizeOnlineIntro(String raw) {
  final text = raw
      .replaceAll('\r\n', '\n')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&lrm;', '')
      .replaceAll('&rlm;', '')
      .replaceAll('&#8206;', '')
      .replaceAll('&#8207;', '')
      .replaceAll('\u00A0', ' ')
      .replaceAll(RegExp(r'[ \t]+\n'), '\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n');
  return text.trim();
}

/// 判断下载到的章节内容是否是可导入的正文；无法使用时返回可读原因。
String? chapterContentFailureReason(String content) {
  final text = content.trim().replaceFirst('\uFEFF', '').trim();
  if (text.isEmpty) return '章节正文为空';
  for (final prefix in const <String>[
    '本章下载失败，已按在线源重试',
    '本章正在后台下载中',
    '本章尚未下载',
  ]) {
    if (text.startsWith(prefix)) return '检测到下载占位正文';
  }
  if (text.contains('批量请求重试') && text.contains('后仍失败')) {
    return '批量请求重试后仍失败';
  }
  if (text.startsWith('批量API返回空响应')) return '批量接口返回空响应';

  if (text.startsWith('{') || text.startsWith('[')) {
    Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      decoded = null;
    }
    if (decoded != null) {
      if (_hasChapterText(decoded)) return null;
      final message = _findJsonMessage(decoded);
      if (message != null && message.isNotEmpty) {
        return '接口未返回正文：${_summarize(message)}';
      }
      if (_signalsFailure(decoded)) return '接口返回失败状态且没有章节正文';
      return '接口返回 JSON，但未找到 content/text 正文';
    }
  }

  final plain = (html_parser.parseFragment(text).text ?? '').trim();
  if (plain.isEmpty) {
    return RegExp(r'<img\b', caseSensitive: false).hasMatch(text)
        ? null
        : '章节正文为空';
  }
  return null;
}

/// 解析 `data:image/...;base64,...` 封面；非图片数据返回空。
Uint8List? decodeDataUrlImage(String raw) {
  final text = raw.trim();
  if (text.length > 12 * 1024 * 1024) return null;
  final match = RegExp(
    r'^data:image/(?:png|jpe?g|webp|gif);base64,',
    caseSensitive: false,
  ).firstMatch(text);
  if (match == null) return null;
  try {
    final bytes = base64Decode(text.substring(match.end));
    return bytes.isEmpty ? null : bytes;
  } on FormatException {
    return null;
  }
}

String _trimDecimal(String value) {
  final text = value.trim();
  if (!text.contains('.')) return text;
  return text.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
}

String _inferStatusFromChapter(String raw) {
  final title = raw.trim();
  if (title.isEmpty) return '';
  if (const <String>[
    '完结感言',
    '完本感言',
    '完结撒花',
    '全文完',
    '全书完',
    '大结局',
  ].any(title.contains)) {
    return '完结';
  }
  if (RegExp(r'^新书\s*[《〈]').hasMatch(title)) return '完结';
  return '';
}

bool _hasChapterText(Object? value) {
  if (value is Map) {
    for (final entry in value.entries) {
      final key = '${entry.key}'.toLowerCase();
      if ((key == 'content' || key == 'text') && _meaningful(entry.value)) {
        return true;
      }
      if (key != 'msg' && key != 'message' && key != 'error') {
        if (_hasChapterText(entry.value)) return true;
      }
    }
    return false;
  }
  if (value is List) {
    for (final item in value) {
      if (_hasChapterText(item)) return true;
    }
  }
  return false;
}

bool _meaningful(Object? value) {
  if (value is String) {
    final text = value.trim();
    return text.isNotEmpty && text.toLowerCase() != 'null';
  }
  if (value is Map) {
    return value.values.any(_meaningful);
  }
  if (value is List) {
    return value.any(_meaningful);
  }
  return false;
}

String? _findJsonMessage(Object? value) {
  if (value is Map) {
    for (final key in const <String>['msg', 'message', 'error', 'detail']) {
      for (final entry in value.entries) {
        if ('${entry.key}'.toLowerCase() != key) continue;
        final message = '${entry.value ?? ''}'.trim();
        if (message.isNotEmpty && message.toLowerCase() != 'null') {
          return message;
        }
      }
    }
    for (final item in value.values) {
      final nested = _findJsonMessage(item);
      if (nested != null) return nested;
    }
  } else if (value is List) {
    for (final item in value) {
      final nested = _findJsonMessage(item);
      if (nested != null) return nested;
    }
  }
  return null;
}

bool _signalsFailure(Object? value) {
  if (value is! Map) return false;
  for (final entry in value.entries) {
    final key = '${entry.key}'.toLowerCase();
    if (key == 'success' && entry.value == false) return true;
    if (key == 'code') {
      final code = '${entry.value ?? ''}'.trim();
      if (code.isNotEmpty && code != '0' && code.toLowerCase() != 'null') {
        return true;
      }
    }
  }
  return false;
}

String _summarize(String value) {
  final text = value.replaceAll(RegExp(r'\s+'), ' ').trim();
  return text.length <= 160 ? text : text.substring(0, 160);
}
