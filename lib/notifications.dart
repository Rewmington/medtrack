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

  /// 立即弹一条（不经 AlarmManager），单独验证通知显示通道。
  Future<void> showNow() async {
    if (!_ready) return;
    await _plugin.show(
      9998,
      '立即测试通知',
      '看得到我=显示通道正常，问题在闹钟送达',
      NotificationDetails(android: _dose),
    );
  }

  /// 诊断信息：通知权限与当前排期数，用于定位"排了但不弹"。
  Future<String> status() async {
    if (!_ready) return '非安卓平台，不接管系统通知';
    final notif = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    final enabled = await notif?.areNotificationsEnabled() ?? false;
    final pending = await _plugin.pendingNotificationRequests();
    return '通知权限：${enabled ? "已允许" : "被拒绝(去设置里开)"}；'
        '当前排期：${pending.length} 条';
  }

  /// 一次性测试提醒（delaySeconds 后触发），返回 null 表示排期成功。
  Future<String?> test(int delaySeconds) async {
    if (!_ready) return '当前平台不走系统通知（仅安卓支持）';
    final when = tz.TZDateTime.now(tz.local)
        .add(Duration(seconds: delaySeconds));
    try {
      await _plugin.zonedSchedule(
        9999,
        '测试提醒',
        '这条准时到达说明系统通知链路正常',
        when,
        NotificationDetails(android: _dose),
        androidScheduleMode: AndroidScheduleMode.alarmClock,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  /// 上一次真正落到系统里的排期指纹与通知 id。
  /// 每分钟刷新时若排期内容没变就整体跳过，变了也只按 id 精确撤销重建——
  /// 绝不能 cancelAll：会把测试通知和刚挂上的闹钟一起抹掉，
  /// 且频繁撤建会被厂商省电策略判定为异常而拦截送达。
  String? _appliedSig;
  List<int> _appliedIds = const [];

  Future<void> reschedule(
    List<Medicine> medicines,
    Settings settings, {
    Map<String, int> takenToday = const {},
  }) async {
    if (!_ready) return;
    final specs =
        <
          ({
            int hour,
            int minute,
            String channel,
            String title,
            String body,
            AndroidNotificationDetails details,
          })
        >[];
    for (final m in medicines) {
      if (settings.remindersEnabled && m.isLow && settings.lowStockReminders) {
        final d = m.daysLeft!;
        specs.add((
          hour: settings.reminderHour,
          minute: settings.reminderMinute,
          channel: _low.channelId,
          title: '药品余量不足',
          body: d <= 0
              ? '${m.name} 预计已吃完，请及时补充'
              : '${m.name} 仅够约 ${d.ceil()} 天，预计 ${m.estimatedFinishDate!.month}月${m.estimatedFinishDate!.day}日 吃完',
          details: _low,
        ));
      }
      if (settings.remindersEnabled && settings.doseTimeReminders) {
        final mins = m.scheduleMinutes;
        final taken = takenToday[m.id] ?? 0;
        for (var j = 0; j < mins.length; j++) {
          final min = mins[j];
          // 打卡从最早时段依次点亮：已覆盖到的点位若今天还要触发，跳过。
          if (j < taken && _firesToday(min)) continue;
          specs.add((
            hour: min ~/ 60,
            minute: min % 60,
            channel: _dose.channelId,
            title: '该吃 ${m.name} 了',
            body:
                '每次 ${m.dailyUseLabel.substring(3)}（${m.times.isEmpty ? '默认按次数安排' : '按你设定的时间'}）',
            details: _dose,
          ));
        }
      }
    }
    final sig = specs
        .map((s) => '${s.hour}:${s.minute}#${s.channel}#${s.title}#${s.body}')
        .join('|');
    if (sig == _appliedSig) return;
    for (final id in _appliedIds) {
      await _plugin.cancel(id);
    }
    final ids = <int>[];
    var id = 1000;
    for (final s in specs) {
      await _schedule(id, s.title, s.body, s.details, s.hour, s.minute);
      ids.add(id);
      id++;
    }
    _appliedIds = ids;
    _appliedSig = sig;
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
      androidScheduleMode: AndroidScheduleMode.alarmClock,
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
