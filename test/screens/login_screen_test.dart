import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vica_supervisor/providers/auth_provider.dart';
import 'package:vica_supervisor/screens/login_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('비밀번호는 기본으로 숨겨지고 버튼으로 표시할 수 있다', (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AuthProvider(),
        child: const MaterialApp(home: LoginScreen()),
      ),
    );

    final passwordInput = find.byType(EditableText).at(1);
    expect(tester.widget<EditableText>(passwordInput).obscureText, isTrue);

    await tester.tap(find.byTooltip('비밀번호 표시'));
    await tester.pump();

    expect(tester.widget<EditableText>(passwordInput).obscureText, isFalse);
    expect(find.byTooltip('비밀번호 숨기기'), findsOneWidget);
  });
}
