import 'package:flutter_test/flutter_test.dart';
import 'package:saturday_consumer_app/screens/auth/login_screen.dart';

import '../_helpers.dart';

void main() {
  setUpAll(loadGoldenFonts);

  testWidgets('login_screen', (tester) async {
    await pumpScreen(tester, const LoginScreen());
    await expectLater(
      find.byType(LoginScreen),
      matchesGoldenFile('login_screen.png'),
    );
  }, timeout: const Timeout(Duration(seconds: 30)));
}
