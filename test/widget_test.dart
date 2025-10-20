import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:ask_psu/user/ws1.dart';

void main() {
  testWidgets('Admin Login Page UI loads', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: OnboardingScreen()));

    expect(find.text('Welcome back!'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('Forgot password?'), findsOneWidget);
  });
}
