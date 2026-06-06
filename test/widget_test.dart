import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:player/main.dart';

void main() {
  testWidgets('App builds smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.byType(GetMaterialApp), findsOneWidget);
  });
}
