import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Generators (flutter_native_splash, flutter_launcher_icons) rewrite these files
// and have silently dropped the portrait lock before.
void main() {
  test('Android activity is locked to portrait', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(manifest, contains('android:screenOrientation="portrait"'));
  });

  test('AdMob app ids are present (the SDK crashes at launch without them)', () {
    expect(File('android/app/src/main/AndroidManifest.xml').readAsStringSync(),
        contains('com.google.android.gms.ads.APPLICATION_ID'));
    expect(File('ios/Runner/Info.plist').readAsStringSync(), contains('GADApplicationIdentifier'));
  });

  test('release keeps Room databases (WorkManager via the ads SDK crashed at launch without it)', () {
    expect(File('android/app/proguard-rules.pro').readAsStringSync(), contains('androidx.room.RoomDatabase'));
  });

  test('iOS supports only portrait', () {
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    expect(plist, contains('UIInterfaceOrientationPortrait'));
    expect(plist, isNot(contains('UIInterfaceOrientationLandscape')));
    expect(plist, contains('UIRequiresFullScreen'));
  });
}
