/// CSS 2 保留的四种伪元素同时接受单、双冒号，内部统一使用双冒号名称。
String? originatingSelector(String raw, String pseudo) {
  final selector = raw.trim();
  final lower = selector.toLowerCase();
  final suffix = lower.endsWith(pseudo) ? pseudo : pseudo.substring(1);
  if (!lower.endsWith(suffix)) return null;
  final main = selector.substring(0, selector.length - suffix.length);
  if (main.isEmpty) return '*';
  // `div ::before` 的起源元素是 div 的后代，不能误改成 div 自身。
  return RegExp(r'[\s>+~]$').hasMatch(main) ? '$main*' : main;
}

/// 排除伪元素分支，避免把其计数器等声明应用到起源元素。
bool hasLegacyPseudoElement(String selector) => const [
  '::before',
  '::after',
  '::first-letter',
  '::first-line',
].any((pseudo) => originatingSelector(selector, pseudo) != null);
