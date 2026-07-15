import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vica_supervisor/providers/auth_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('관리자 계정으로 로그인하면 다음 실행에서도 상태가 유지된다', () async {
    final auth = AuthProvider();

    expect(
      await auth.login(username: 'admin', password: '1234'),
      isTrue,
    );
    expect(auth.isLoggedIn, isTrue);

    final restoredAuth = AuthProvider();
    await restoredAuth.load();
    expect(restoredAuth.isLoggedIn, isTrue);
  });

  test('잘못된 계정은 로그인되지 않는다', () async {
    final auth = AuthProvider();

    expect(
      await auth.login(username: 'admin', password: 'wrong'),
      isFalse,
    );
    expect(auth.isLoggedIn, isFalse);
  });

  test('로그아웃하면 저장된 로그인 상태가 완전히 삭제된다', () async {
    final auth = AuthProvider();
    await auth.login(username: 'admin', password: '1234');

    await auth.logout();

    final prefs = await SharedPreferences.getInstance();
    expect(auth.isLoggedIn, isFalse);
    expect(prefs.containsKey('vica_supervisor_is_logged_in'), isFalse);
  });
}
