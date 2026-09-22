import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'models.dart';
import 'settings.dart';

/// 低药量 + 到点服药提醒。Android 走系统通知（每日重复），
/// Windows 端 v1 由应用内横幅提示，不在此调度。
class ReminderService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  Future<void> init() async {
    if (!Platform.isAndroid) return;
    tzdata.initializeTimeZones();
    try {
      final name = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(name));
    } catch (_) {
      // 拿不到时区名时按设备 UTC 偏移兜底（Etc/GMT 符号相反），
      // 直接退回 UTC 会让国内提醒迟到 8 小时。
      final h = -DateTime.now().timeZoneOffset.inHours;
      try {
        tz.setLocalLocation(tz.getLocation('Etc/GMT${h >= 0 ? '+' : ''}$h'));
      } catch (_) {
        tz.setLocalLocation(tz.getLocation('UTC'));
      }
    }
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(
      const InitializationSettings(android: android),
      onDidReceiveNotificationResponse: null,
    );
    final notif = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await notif?.requestNotificationsPermission();
    // Android 12+ 精确闹钟授权（用户拒绝时系统仍可延迟）
    await notif?.requestExactAlarmsPermission();
    _ready = true;
  }

  Future<void> cancelAll() async {
    if (!_ready) return;
    await _plugin.cancelAll();
  }

  static const _low = AndroidNotificationDetails(
    'low_stock',
    '低药量提醒',
    channelDescription: '药品即将吃完时提醒',
    importance: Importance.high,
    priority: Priority.high,
  );
  static const _dose = AndroidNotificationDetails(
    'dose_time',
    '服药提醒',
    channelDescription: '到点了该吃药',
    importance: Importance.max,
    priority: Priority.high,
  );

  /// 根据当前药品状态重建全部提醒（每日重复）。
  Future<void> reschedule(
    List<Medicine> medicines,
    Settings settings, {
    Map<String, int> takenToday = const {},
  }) async {
    if (!_ready) return;
    await _plugin.cancelAll();
    var id = 1000;
    for (final m in medicines) {
      if (settings.remindersEnabled && m.isLow && settings.lowStockReminders) {
        final d = m.daysLeft!;
        await _schedule(
          id++,
          '药品余量不足',
          d <= 0
              ? '${m.name} 预计已吃完，请及时补充'
              : '${m.name} 仅够约 ${d.ceil()} 天，预计 ${m.estimatedFinishDate!.month}月${m.estimatedFinishDate!.day}日 吃完',
          _low,
          settings.reminderHour,
          settings.reminderMinute,
        );
      }
      if (settings.remindersEnabled && settings.doseTimeReminders) {
        final mins = m.scheduleMinutes;
        final taken = takenToday[m.id] ?? 0;
        for (var j = 0; j < mins.length; j++) {
          final min = mins[j];
          // 打卡从最早时段依次点亮：已覆盖到的点位若今天还要触发，跳过。
          if (j < taken && _firesToday(min)) continue;
          await _schedule(
            id++,
            '该吃 ${m.name} 了',
            '每次 ${m.dailyUseLabel.substring(3)}（${m.times.isEmpty ? '默认按次数安排' : '按你设定的时间'}）',
            _dose,
            min ~/ 60,
            min % 60,
          );
        }
      }
    }
  }

  Future<void> _schedule(
    int id,
    String title,
    String body,
    AndroidNotificationDetails details,
    int hour,
    int minute,
  ) async {
    await _plugin.zonedSchedule(
      id,
      title,
      body,
      _nextInstanceOf(hour, minute),
      NotificationDetails(android: details),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  static bool _firesToday(int totalMinutes) {
    final next = _nextInstanceOf(totalMinutes ~/ 60, totalMinutes % 60);
    final now = tz.TZDateTime.now(tz.local);
    return next.year == now.year &&
        next.month == now.month &&
        next.day == now.day;
  }

  static tz.TZDateTime _nextInstanceOf(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );
    if (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }
}
