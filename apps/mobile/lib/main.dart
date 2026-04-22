import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/app/veil_app.dart';
import 'src/core/diagnostics/crash_log_service.dart';

void main() {
  runZonedGuarded<void>(
    () {
      WidgetsFlutterBinding.ensureInitialized();
      final crashLog = CrashLogService();
      installCrashHandlers(crashLog);
      runApp(
        ProviderScope(
          overrides: [
            crashLogServiceProvider.overrideWithValue(crashLog),
          ],
          child: const VeilApp(),
        ),
      );
    },
    (error, stack) {
      // Zone-level fallback for errors that escape Flutter's handlers.
      unawaited(
        CrashLogService().record(error, stack, context: 'ZoneGuarded'),
      );
    },
  );
}
