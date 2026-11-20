// Local notifications: at most one Daily Jar reminder a day, opt-in.
// Every call is a no-op until init() succeeds, so tests and platforms without
// the plugin never touch it.
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../meta/daily.dart';
import '../meta/progress.dart';

class Notifications {
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static const _android = AndroidNotificationDetails(
    'daily_jar',
    'Daily Jar',
    channelDescription: 'One reminder a day when your Daily Jar is ready',
    icon: 'ic_launcher_monochrome',
  );
  static const _details = NotificationDetails(android: _android, iOS: DarwinNotificationDetails());

  Future<void> init() async {
    try {
      tzdata.initializeTimeZones();
      try {
        tz.setLocalLocation(tz.getLocation((await FlutterTimezone.getLocalTimezone()).identifier));
      } on Object {
        // Unknown zone: stay on UTC; the reminder may drift by the offset.
      }
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('ic_launcher_monochrome'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
      );
      _ready = true;
    } on Object catch (e) {
      debugPrint('notifications unavailable: $e');
    }
  }

  /// Asks the OS (Android 13+, iOS). Only call in response to the player.
  Future<bool> requestPermission() async {
    if (!_ready) return false;
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) return await android.requestNotificationsPermission() ?? false;
    final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    return await ios?.requestPermissions(alert: true, sound: true) ?? false;
  }

  /// Replaces any pending reminder with one at [when] (inexact: no exact-alarm permission).
  Future<void> schedule(DateTime when, String title, String body) async {
    if (!_ready) return;
    await _plugin.cancelAll();
    await _plugin.zonedSchedule(
      id: 1,
      scheduledDate: tz.TZDateTime.from(when, tz.local),
      notificationDetails: _details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      title: title,
      body: body,
    );
  }

  Future<void> cancel() async {
    if (_ready) await _plugin.cancelAll();
  }
}

/// App-wide instance; main() calls init().
Notifications notifications = Notifications();

/// Keeps exactly one upcoming reminder in line with the player's choice and
/// today's progress. Called on launch, after a daily win and on toggling.
Future<void> refreshReminder() async {
  if (!progress.settings.reminders) return notifications.cancel();
  final now = dailyClock();
  final today = dailyNumber(now);
  final streak = progress.data.daily.current(today);
  await notifications.schedule(
    nextReminder(now, doneToday: progress.dailyDone(today)),
    'Your Daily Jar is ready',
    streak > 1 ? 'Keep your $streak-day streak going.' : 'Tilt, pour, cork. A new jar is waiting.',
  );
}
