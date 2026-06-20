import 'package:flutter_test/flutter_test.dart';
import 'package:kiyat_driver/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('shows driver sign in screen', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const KiyatDriverApp());
    await tester.pumpAndSettle();

    expect(find.text('دخول السائق'), findsOneWidget);
    expect(find.text('دخول تجريبي'), findsOneWidget);
  });
}
