/// 宽度的内容尺寸关键字；与百分比、像素、auto 的长度模型分开。
enum CssIntrinsicWidth {
  minContent,
  maxContent,
  fitContent;

  static CssIntrinsicWidth? parse(String? raw) =>
      switch (raw?.trim().toLowerCase()) {
        'min-content' => minContent,
        'max-content' => maxContent,
        'fit-content' => fitContent,
        _ => null,
      };
}
