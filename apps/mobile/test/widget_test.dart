import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kiyat_mobile/main.dart';

void main() {
  testWidgets('Kiyat passenger home smoke test', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: KiyatApp()));
    await tester.pump(const Duration(seconds: 7));
    await tester.pump();

    expect(find.text('كيات'), findsOneWidget);
    expect(find.text('الخطوط القريبة'), findsOneWidget);
    expect(find.text('المحفوظة'), findsOneWidget);
  });
}
