import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// The app picks photos and files through the system pickers, which need no
// permission, so it declares no camera, microphone or media-library
// permission on either platform, and no plugin it ships declares one either.
// A store reviewer reads a declared permission as a feature: add one here
// only in the change that makes such a feature work end to end.

const _declared = {'INTERNET', 'USE_BIOMETRIC', 'POST_NOTIFICATIONS', 'VIBRATE', 'WAKE_LOCK'};

final _usesPermission = RegExp(r'<uses-permission(?:-sdk-23)?\b[^>]*android:name="([^"]+)"');

// Comments say what a manifest leaves out, so they are no declaration.
String _withoutComments(String xml) => xml.replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');

Set<String> _permissionsIn(String manifest) => {
      for (final match in _usesPermission.allMatches(_withoutComments(manifest)))
        match.group(1)!.replaceFirst('android.permission.', ''),
    };

void main() {
  final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

  test('Android declares only the permissions the app uses', () {
    expect(_permissionsIn(manifest), _declared);
    // Nothing a plugin declares is taken out again: there is nothing to
    // take out, and a removal line would hide one that is added later.
    expect(manifest, isNot(contains('tools:node')));
    expect(manifest, isNot(contains('android.hardware.camera')));
    expect(manifest, isNot(contains('android.hardware.microphone')));
    // Its own words say why, and stay true.
    expect(
      manifest.replaceAll(RegExp(r'\s+'), ' '),
      contains('No camera, microphone or media-library permission: photos come from the system photo picker and '
          'files from the system document picker, which need none.'),
    );
  });

  test('no plugin the app ships declares a permission the app does not', () {
    final dependencies = File('.flutter-plugins-dependencies');
    expect(dependencies.existsSync(), isTrue, reason: 'run flutter pub get: the plugin list is missing');
    final plugins = (jsonDecode(dependencies.readAsStringSync()) as Map<String, dynamic>)['plugins'] as Map<String, dynamic>;
    final android = (plugins['android'] as List).cast<Map<String, dynamic>>();
    expect(android, isNotEmpty);
    final names = {for (final plugin in android) plugin['name'] as String};
    // The plugins this check exists for are among them.
    expect(names, containsAll(['image_picker_android', 'flutter_file_dialog', 'flutter_local_notifications']));
    for (final plugin in android) {
      final pluginManifest = File('${plugin['path']}android/src/main/AndroidManifest.xml');
      if (!pluginManifest.existsSync()) continue;
      final permissions = _permissionsIn(pluginManifest.readAsStringSync());
      expect(permissions.difference(_declared), isEmpty, reason: '${plugin['name']} declares $permissions');
    }
  });

  test('the app has one file provider, and it serves only the folder a file is opened from', () {
    final providers = RegExp(r'<provider\b(.*?)(?:/>|</provider>)', dotAll: true).allMatches(_withoutComments(manifest)).toList();
    expect(providers, hasLength(1));
    final provider = providers.single.group(1)!;
    expect(provider, contains('android:name=".VeilOpenFileProvider"'));
    expect(provider, contains(r'android:authorities="${applicationId}.veil_open"'));
    expect(provider, contains('android:exported="false"'));
    expect(provider, contains('android:grantUriPermissions="true"'));
    expect(provider, contains('android:resource="@xml/veil_open_paths"'));

    final paths = _withoutComments(File('android/app/src/main/res/xml/veil_open_paths.xml').readAsStringSync());
    final entries = RegExp(r'<([a-z-]+-path)\b([^>]*)/>').allMatches(paths).toList();
    expect(entries, hasLength(1));
    expect(entries.single.group(1), 'cache-path');
    expect(entries.single.group(2), contains('name="veil_open"'));
    expect(entries.single.group(2), contains('path="veil_open/"'));
    for (final wide in ['root-path', 'external-path', 'files-path', 'external-files-path', 'external-cache-path']) {
      expect(paths, isNot(contains(wide)), reason: wide);
    }
  });

  test('iOS asks only for Face ID and the photo picker', () {
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    final usageKeys = RegExp(r'<key>(NS[A-Za-z]+UsageDescription)</key>')
        .allMatches(plist)
        .map((match) => match.group(1))
        .toSet();
    expect(usageKeys, {'NSFaceIDUsageDescription', 'NSPhotoLibraryUsageDescription'});
    for (final absent in ['NSCameraUsageDescription', 'NSMicrophoneUsageDescription', 'NSPhotoLibraryAddUsageDescription']) {
      expect(plist, isNot(contains(absent)), reason: absent);
    }
    expect(plist, contains('<string>Veil sees only the photos you pick.</string>'));
    expect(plist, isNot(contains('VEIL')));
  });

  test('no code asks for the camera, the photo metadata, the photo library or another app to open a file', () {
    final banned = ['ImageSource.camera', 'requestFullMetadata: true', 'saveToCameraRoll', 'share_plus', 'open_filex'];
    for (final file in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      final source = file.readAsStringSync();
      for (final word in banned) {
        expect(source, isNot(contains(word)), reason: '${file.path} contains $word');
      }
    }
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, isNot(contains('open_filex')));
    expect(pubspec, isNot(contains('share_plus')));
  });
}
