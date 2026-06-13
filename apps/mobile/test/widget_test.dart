import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kiyat_mobile/main.dart';

void main() {
  testWidgets('Kiyat passenger home smoke test', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: KiyatApp()));
    await tester.pumpAndSettle();

    expect(find.text('كيات'), findsOneWidget);
    expect(find.text('الخطوط القريبة'), findsOneWidget);
    expect(find.text('من وين؟'), findsOneWidget);
  });
}
