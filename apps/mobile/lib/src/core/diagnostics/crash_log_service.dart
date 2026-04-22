import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Local-only crash/error log. Writes to a rolling file in the app's
/// documents directory — never transmitted unless the user explicitly
/// shares it via the settings screen.
class CrashLogService {
  CrashLogService({Directory? overrideDirectory}) : _override = overrideDirectory;

  static const _fileName = 'veil_crash.log';
  static const _maxBytes = 128 * 1024;

  final Directory? _override;
  Directory? _cached;

  Future<File> _file() async {
    final dir = _override ?? _cached ?? await getApplicationDocumentsDirectory();
    _cached ??= dir;
    return File(p.join(dir.path, _fileName));
  }

  Future<void> record(
    Object error,
    StackTrace? stack, {
    String? context,
    Map<String, String>? tags,
  }) async {
    try {
      final file = await _file();
      if (await file.exists() && await file.length() > _maxBytes) {
        await file.writeAsString('', mode: FileMode.write);
      }
      final buffer = StringBuffer()
        ..writeln('---')
        ..writeln('time=${DateTime.now().toUtc().toIso8601String()}')
        ..writeln('context=${context ?? 'unknown'}');
      if (tags != null) {
        for (final entry in tags.entries) {
          buffer.writeln('${entry.key}=${entry.value}');
        }
      }
      buffer
        ..writeln('error=$error')
        ..writeln('stack:')
        ..writeln(stack?.toString() ?? '(no stack)');
      await file.writeAsString(
        buffer.toString(),
        mode: FileMode.append,
        flush: true,
      );
    } catch (_) {
      // Never let logging failures crash the app.
    }
  }

  Future<String> readAll() async {
    final file = await _file();
    if (!await file.exists()) {
      return '';
    }
    return file.readAsString();
  }

  Future<void> clear() async {
    final file = await _file();
    if (await file.exists()) {
      await file.writeAsString('', mode: FileMode.write);
    }
  }
}

final crashLogServiceProvider = Provider<CrashLogService>((ref) {
  return CrashLogService();
});

/// Installs Flutter + isolate error handlers that forward to [CrashLogService].
/// Safe to call multiple times; last caller wins.
void installCrashHandlers(CrashLogService service) {
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    unawaited(service.record(
      details.exception,
      details.stack,
      context: 'FlutterError',
      tags: {
        if (details.library != null) 'library': details.library!,
      },
    ));
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    unawaited(service.record(error, stack, context: 'PlatformDispatcher'));
    return true;
  };
}
