import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vica_supervisor/providers/ui_preferences_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('사이드 메뉴 접힘 상태가 다음 실행에도 유지된다', () async {
    final preferences = UiPreferencesProvider();
    await preferences.load();
    expect(preferences.sidebarExpanded, isTrue);

    await preferences.toggleSidebar();
    expect(preferences.sidebarExpanded, isFalse);

    final restoredPreferences = UiPreferencesProvider();
    await restoredPreferences.load();
    expect(restoredPreferences.sidebarExpanded, isFalse);
  });
}
