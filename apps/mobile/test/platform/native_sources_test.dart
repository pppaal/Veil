import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// No Android or iOS build runs here, so the native half of the lock and of
// opening a file is held to its source text: the flags that keep an opened
// file out of Veil's task, the provider that serves one folder, and the iOS
// dismissal and shield that keep a document from showing over the lock.

String _read(String path) => File(path).readAsStringSync();

// Comments say what the code avoids, so only code is searched for it.
String _code(String source) =>
    source.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '').replaceAll(RegExp(r'//[^\n]*'), '');

const _kotlin = 'android/app/src/main/kotlin/io/veil/mobile';

void main() {
  test('Android opens a file in its viewer\'s own task, through the app\'s provider', () {
    final channel = _read('$_kotlin/FileOpenChannel.kt');
    final code = _code(channel);
    for (final needed in [
      'veil/file_open',
      'Intent.ACTION_VIEW',
      'FLAG_ACTIVITY_NEW_TASK',
      'FLAG_ACTIVITY_MULTIPLE_TASK',
      'FLAG_GRANT_READ_URI_PERMISSION',
      'ActivityNotFoundException',
      '"noApp"',
      'veil_open',
      'FileProvider.getUriForFile',
      r'"${context.packageName}.veil_open"',
      'canonicalFile',
    ]) {
      expect(code, contains(needed), reason: needed);
    }
    expect(code, isNot(contains('FLAG_ACTIVITY_SINGLE_TOP')));
    expect(code, isNot(contains('FLAG_GRANT_WRITE_URI_PERMISSION')));

    final provider = _code(_read('$_kotlin/VeilOpenFileProvider.kt'));
    expect(provider, contains('class VeilOpenFileProvider : FileProvider()'));
    expect(provider, contains('import androidx.core.content.FileProvider'));
    expect(_read('android/app/build.gradle.kts'), contains('implementation("androidx.core:core:1.18.0")'));
  });

  test('MainActivity registers the channel and answers the lock calls', () {
    final activity = _code(_read('$_kotlin/MainActivity.kt'));
    expect(activity, contains('FileOpenChannel(applicationContext).register(flutterEngine.dartExecutor.binaryMessenger)'));
    expect(activity, contains('"lockEngaged", "lockScreenShown", "sessionUnlocked" -> {'));
  });

  test('iOS shows a file in Quick Look over the app, from the open folder only, in the existing Swift files', () {
    final delegate = _read('ios/Runner/AppDelegate.swift');
    final code = _code(delegate);
    for (final needed in [
      'import QuickLook',
      'veil/file_open',
      'QLPreviewController',
      '.overFullScreen',
      'QLPreviewController.canPreview',
      'previewControllerDidDismiss',
      '"noApp"',
      '"closed"',
      '"veil_open"',
      'FileOpenPlugin.register(with: registrar)',
      'static func presentationDismissedByLock()',
      // The lock calls reach the scene.
      'case "lockEngaged":',
      'case "lockScreenShown":',
      'case "sessionUnlocked":',
      '"sceneEnteredBackground"',
    ]) {
      expect(code, contains(needed), reason: needed);
    }
    // No new Swift file: project.pbxproj names none.
    final project = _read('ios/Runner.xcodeproj/project.pbxproj');
    expect(project, isNot(contains('FileOpen')));
    final swiftFiles = Directory('ios/Runner')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.swift'))
        .map((file) => file.uri.pathSegments.last)
        .toSet();
    expect(swiftFiles, {'AppDelegate.swift', 'SceneDelegate.swift', 'VeilCryptoBridge.swift'});
  });

  test('the iOS scene closes what is presented on lock and keeps the shield until the lock screen is drawn', () {
    final scene = _code(_read('ios/Runner/SceneDelegate.swift'));
    for (final needed in [
      'dismiss(animated: false)',
      'FileOpenPlugin.presentationDismissedByLock()',
      'emitSceneEnteredBackground()',
      'awaitingLockScreen',
      'sessionLocked',
      'func lockEngaged()',
      'func lockScreenShown()',
      'func sessionUnlocked()',
      'lockScreenFallback: TimeInterval = 1.5',
    ]) {
      expect(scene, contains(needed), reason: needed);
    }
    // The shield goes on becoming active only when no lock screen is awaited.
    final becomeActive = RegExp(r'override func sceneDidBecomeActive\(.*?\n  \}', dotAll: true).firstMatch(scene)!.group(0)!;
    expect(becomeActive, contains('if sessionLocked'));
    expect(becomeActive, contains('if awaitingLockScreen'));
    expect(becomeActive, contains('scheduleShieldFallback()'));
    final enterBackground =
        RegExp(r'override func sceneDidEnterBackground\(.*?\n  \}', dotAll: true).firstMatch(scene)!.group(0)!;
    expect(enterBackground, contains('emitSceneEnteredBackground()'));
  });
}
