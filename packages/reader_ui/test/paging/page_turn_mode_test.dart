import 'package:flutter_test/flutter_test.dart';
import 'package:reader_ui/paging/page_turn_mode.dart';

void main() {
  test('旧版 3D 可持久化恢复并显示名称', () {
    expect(PageTurnMode.fromId('simulation3d'), PageTurnMode.simulation3d);
    expect(PageTurnMode.simulation3d.label, '3D（旧版）');
  });

  test('旧值仍回退到覆盖模式', () {
    expect(PageTurnMode.fromId('missing'), PageTurnMode.cover);
    expect(PageTurnMode.fromId(null), PageTurnMode.cover);
  });
}
