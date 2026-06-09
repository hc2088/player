import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:player/main.dart';
import 'package:player/services/playback_service.dart';

void main() {
  testWidgets('App builds smoke test', (WidgetTester tester) async {
    Get.put(PlaybackService(), permanent: true);
    await tester.pumpWidget(const MyApp());

    expect(find.byType(GetMaterialApp), findsOneWidget);
    Get.reset();
  });

  testWidgets('Privacy gate password field accepts text', (
    WidgetTester tester,
  ) async {
    Get.put(PlaybackService(), permanent: true);
    await tester.pumpWidget(const MyApp());

    await tester.tap(find.text('helloworld'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(EditableText), 'q');
    await tester.pump();

    expect(tester.takeException(), isNull);
    Get.reset();
  });
}
