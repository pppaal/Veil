import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/app/veil_app.dart';
import 'src/core/diagnostics/crash_log_service.dart';
import 'src/features/attachments/data/attachment_storage_paths.dart';

void main() {
  runZonedGuarded<void>(
    () {
      WidgetsFlutterBinding.ensureInitialized();
      final crashLog = CrashLogService();
      installCrashHandlers(crashLog);
      // Decrypted copies and picks a previous run left go before anything
      // else, while the app still shows its lock screen.
      unawaited(AttachmentStoragePaths().purgeLeftPlaintext().catchError((Object _) {}));
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
