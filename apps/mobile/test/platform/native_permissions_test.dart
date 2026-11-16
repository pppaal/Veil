import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// The app sends text only and ships no camera, recorder or picker plugin, so
// it declares no camera, microphone or media-library permission on either
// platform. A store reviewer reads a declared permission as a feature: add
// one here only in the change that makes such a feature work end to end.
void main() {
  test('Android declares only the permissions the app uses', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final declared = RegExp(r'<uses-permission[^>]*android:name="android\.permission\.([A-Z_]+)"')
        .allMatches(manifest)
        .map((match) => match.group(1))
        .toSet();
    expect(declared, {'INTERNET', 'USE_BIOMETRIC', 'POST_NOTIFICATIONS', 'VIBRATE', 'WAKE_LOCK'});
    expect(manifest, isNot(contains('android.hardware.camera')));
    expect(manifest, isNot(contains('android.hardware.microphone')));
  });

  test('iOS asks only for Face ID', () {
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    final usageKeys = RegExp(r'<key>(NS[A-Za-z]+UsageDescription)</key>')
        .allMatches(plist)
        .map((match) => match.group(1))
        .toSet();
    expect(usageKeys, {'NSFaceIDUsageDescription'});
    expect(plist, isNot(contains('VEIL')));
  });
}
