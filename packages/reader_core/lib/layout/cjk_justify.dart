import 'package:flutter/widgets.dart' show StringCharacters;

import '../css/computed_style.dart';
import '../text/script.dart';

/// 两端对齐的可分配间隙（§8.4，P2-19；P7-21 增加 text-justify 模式）。
///
/// 返回「间隙左侧字符」的代码单元偏移：绘制时给这些字符加额外字距，间距只
/// 落在字符之间，末字之后不产生间隙。
///
/// 与阅微 `AnnotatedStringExtKt.cjkJustifyGapIndices` 的差异：阅微的 `isCjk`
/// 把 `0 <= c < 42720` 整段算作 CJK（ASCII 也被算进去），导致拉丁词内部也会
/// 被加字距；这里改用 [isCjkCodePoint]（只含真正的 CJK 区块），再按
/// 「拉丁字母/数字内部不拆」扣除。
///
/// 规则（[mode] 为 `auto` 时，即现状）：
/// 1. 取相邻字符 `(i, i+1)` 之间；
/// 2. 跳过含换行的间隙；
/// 3. 跳过两侧都是拉丁字母/数字的间隙，不拆英文单词；
/// 4. 纯中文 n 字 → n-1 个 gap；末字之后不设 gap；
/// 5. 不含 CJK 的行改为拉伸词间空格（西文不拆词内字距）。
///
/// [mode] 覆盖（P7-21）：`interWord` 只拉伸词间空格；
/// `interCharacter`/`distribute` 全 gap 分配（不豁免拉丁词内）；
/// `justifyAll` 与 `auto` 相同（末行拉伸在分页对齐层处理）。
List<int> cjkJustifyGapOffsets(
  String text, {
  CssTextJustify mode = CssTextJustify.auto,
}) {
  text = text.trimRight();
  if (text.length < 2) {
    return const <int>[];
  }
  final hasCjk = containsCjk(text);
  if (_simpleBmp.hasMatch(text)) {
    return [
      for (var i = 0; i + 1 < text.length; i++)
        if (_stretchable(
          text.codeUnitAt(i),
          text.codeUnitAt(i + 1),
          hasCjk,
          mode,
        ))
          i,
    ];
  }
  final clusters = text.characters.toList(growable: false);
  final offsets = <int>[];
  var offset = 0;
  for (var i = 0; i < clusters.length; i++) {
    if (i < clusters.length - 1) {
      final left = _firstCodePoint(clusters[i]);
      final right = _firstCodePoint(clusters[i + 1]);
      // 多码点字簇的 letter-spacing 可能被平台累计多次，不在其内部施加字距。
      if (_stretchable(left, right, hasCjk, mode) &&
          clusters[i].length == (left > 0xFFFF ? 2 : 1)) {
        offsets.add(offset);
      }
    }
    offset += clusters[i].length;
  }
  return offsets;
}

// 这些码位各自就是完整字簇；其他脚本和补充平面仍走 Unicode 字簇迭代。
final _simpleBmp = RegExp(
  r'^[\x20-\x7e\u3000-\u3029\u3400-\u9fff\uff01-\uff60\uffe0-\uffe6]+$',
);

bool _stretchable(int left, int right, bool hasCjk, CssTextJustify mode) {
  if (left == 0x0A ||
      right == 0x0A ||
      _isBoundary(left) ||
      _isBoundary(right)) {
    return false;
  }
  return switch (mode) {
    CssTextJustify.interWord => left == 0x20,
    CssTextJustify.interCharacter || CssTextJustify.distribute => true,
    CssTextJustify.auto || CssTextJustify.justifyAll =>
      hasCjk ? !(_isWordPart(left) && _isWordPart(right)) : left == 0x20,
  };
}

bool _isBoundary(int code) => code == 0xFFFC || code == 0x200B || code == 0x0D;

int _firstCodePoint(String cluster) =>
    cluster.length == 1 ? cluster.codeUnitAt(0) : cluster.runes.first;

bool _isWordPart(int code) =>
    isJustifyWordCodePoint(code) ||
    (code >= 0x21 && code <= 0x7E) ||
    code == 0x2019;

/// 拉丁字母或数字（用于「不拆英文单词」判定）。
///
/// 覆盖 ASCII、Latin-1 补充、Latin 扩展、希腊与西里尔字母；CJK 与全角字符
/// 不算（它们属于可拉伸的间隙侧）。
bool isJustifyWordCodePoint(int codePoint) {
  if (codePoint >= 0x30 && codePoint <= 0x39) {
    return true; // 0-9
  }
  if (codePoint >= 0x41 && codePoint <= 0x5A) {
    return true; // A-Z
  }
  if (codePoint >= 0x61 && codePoint <= 0x7A) {
    return true; // a-z
  }
  if (codePoint >= 0xC0 && codePoint <= 0x24F) {
    return true; // Latin-1 补充与扩展
  }
  if (codePoint >= 0x370 && codePoint <= 0x3FF) {
    return true; // 希腊字母
  }
  if (codePoint >= 0x400 && codePoint <= 0x4FF) {
    return true; // 西里尔字母
  }
  return false;
}

/// 逐 gap 的字距增量：`ls = extra / gapCount`（§8.4，P2-20）。
///
/// gap 数为 0 或余量非正时返回 0，调用方据此跳过拉伸。
double justifyGapSpacing(double extra, int gapCount) =>
    gapCount <= 0 || extra <= 0 ? 0 : extra / gapCount;
