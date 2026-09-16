import 'package:flutter_test/flutter_test.dart';
import 'package:yokonex_ems_game/app/ems_game_app.dart';

void main() {
  test('应用入口类型可创建', () {
    expect(const EmsGameApp(), isA<EmsGameApp>());
  });
}
