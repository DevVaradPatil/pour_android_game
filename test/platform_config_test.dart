import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Generators (flutter_native_splash, flutter_launcher_icons) rewrite these files
// and have silently dropped the portrait lock before.
void main() {
  test('Android activity is locked to portrait', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(manifest, contains('android:screenOrientation="portrait"'));
  });

  test('iOS supports only portrait', () {
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    expect(plist, contains('UIInterfaceOrientationPortrait'));
    expect(plist, isNot(contains('UIInterfaceOrientationLandscape')));
    expect(plist, contains('UIRequiresFullScreen'));
  });
}
