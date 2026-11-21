import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/ye_she/ye_she_assets.dart';

void main() {
  test('物品 propId 映射到阅微原图资源', () {
    expect(yeShePropIconAsset(1), 'assets/ye_she/items/shrine_prop_1.png');
    expect(yeShePropIconAsset(15), 'assets/ye_she/items/shrine_prop_15.png');
    expect(yeShePropIconAsset(29), 'assets/ye_she/items/shrine_prop_29.png');
    expect(yeShePropIconAsset(20), isNull);
    expect(yeShePropIconAsset(50), isNull);
  });
}
