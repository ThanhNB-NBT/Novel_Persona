import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/screens/shell.dart';

void main() {
  testWidgets('AppSplashIntro widget test', (WidgetTester tester) async {
    bool completed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppSplashIntro(
            onComplete: () => completed = true,
          ),
        ),
      ),
    );

    expect(find.byType(AppSplashIntro), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1000));
    expect(find.text('GÁC TRUYỆN'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1400));
    expect(completed, isTrue);
  });
}
