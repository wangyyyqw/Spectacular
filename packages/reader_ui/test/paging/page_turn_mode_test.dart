import 'package:flutter_test/flutter_test.dart';
import 'package:reader_ui/paging/page_turn_mode.dart';

void main() {
  test('旧版 3D 可持久化恢复并显示名称', () {
    expect(PageTurnMode.fromId('simulation3d'), PageTurnMode.simulation3d);
    expect(PageTurnMode.simulation3d.label, '3D（旧版）');
  });

  test('新版 3D 使用独立持久化标识并显示名称', () {
    expect(
      PageTurnMode.fromId('simulation3dNext'),
      PageTurnMode.simulation3dNext,
    );
    expect(PageTurnMode.simulation3dNext.label, '3D（新版）');
    expect(PageTurnMode.simulation3dNext, isNot(PageTurnMode.simulation3d));
  });

  test('旧值仍回退到覆盖模式', () {
    expect(PageTurnMode.fromId('missing'), PageTurnMode.cover);
    expect(PageTurnMode.fromId(null), PageTurnMode.cover);
  });
}
