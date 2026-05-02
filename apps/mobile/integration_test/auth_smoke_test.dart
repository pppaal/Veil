// Phase AP: integration test scaffold. These run on a real device or
// emulator and exercise the full app boot + auth flow. They are NOT
// run by `flutter test` — use `flutter test integration_test/` from
// apps/mobile, with a connected device.
//
// Status: SCAFFOLD only. The actual register flow needs a running API
// (see docs/vps-deploy-runbook.md or pnpm demo:up). When a real-device
// QA pass happens, expand this file to cover:
//   - register → challenge → verify happy path
//   - re-register collision (existing handle)
//   - session restore on app restart
//   - logout wipes secure storage

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('VEIL mobile integration smoke', () {
    testWidgets('app boots without crashing', (tester) async {
      // Mount a placeholder app so the test runner verifies the
      // toolchain (build_runner outputs, flutter test integration_test/)
      // works end-to-end before we wire the real entrypoint.
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Text('VEIL'))));
      expect(find.text('VEIL'), findsOneWidget);
    });
  });
}
