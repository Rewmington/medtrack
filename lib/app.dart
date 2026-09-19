import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import 'db.dart';
import 'models.dart';
import 'notifications.dart';
import 'settings.dart';
import 'sync/lan_server.dart';
import 'sync/sync_service.dart';

class DayPlan {
  final Medicine medicine;
  final int minute; // 计划时间
  bool taken; // 已打卡
  bool get overdue =>
      !taken &&
      DateTime.now()
              .difference(
                DateTime.now().copyWith(
                  hour: minute ~/ 60,
                  minute: minute % 60,
                ),
              )
              .inMinutes >
          30;
  DayPlan(this.medicine, this.minute, {this.taken = false});
}

class AppController extends ChangeNotifier {
  final LocalDb db = LocalDb();
  final Settings settings = Settings();
  late final SyncService sync;
  late final LanSyncServer lanServer;
  final reminders = ReminderService();

  List<Medicine> medicines = [];
  List<DoseLog> todayLogs = [];
  List<DoseLog> weekLogs = [];
  bool busy = false;
  String? lastSyncMessage;
  DateTime now = DateTime.now();
  Timer? _ticker;

  AppController() {
    sync = SyncService(db, settings);
    lanServer = LanSyncServer(db, settings);
  }

  Future<void> bootstrap() async {
    await settings.load();
    await db.open();
    await reminders.init();
    if (settings.lanHost) {
      final err = await lanServer.start();
      if (err != null) debugPrint('LAN server: $err');
    }
    await refresh();
    _ticker = Timer.periodic(const Duration(minutes: 1), (_) {
      now = DateTime.now();
      refresh();
    });
    unawaited(autoSync());
  }

  /// 启动后若已配置云/局域网通道，做一次静默同步。
  Future<void> autoSync() async {
    if (settings.syncChannel == SyncChannel.off) return;
    final r = await sync.syncNow();
    lastSyncMessage = r.toString();
    if (r.ok && (r.pushed > 0 || r.pulled > 0)) await refresh();
    notifyListeners();
  }

  Future<void> refresh() async {
    medicines = await db.activeMedicines();
    todayLogs = await db.logsFor(now);
    final weekStart = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(const Duration(days: 6));
    weekLogs = await db.logsBetween(
      weekStart,
      DateTime(now.year, now.month, now.day + 1),
    );
    notifyListeners();
    if (settings.remindersEnabled) {
      unawaited(reminders.reschedule(medicines, settings));
    } else {
      unawaited(reminders.cancelAll());
    }
  }

  int takenToday(String medicineId) =>
      todayLogs.where((l) => l.medicineId == medicineId).length;

  /// 该药今天最近一次打卡，用于误点撤销。
  DoseLog? latestTodayLog(String medicineId) {
    final logs = todayLogs.where((l) => l.medicineId == medicineId).toList()
      ..sort((a, b) => b.takenAt.compareTo(a.takenAt));
    return logs.isEmpty ? null : logs.first;
  }

  /// 今日应服计划表（药 × 时间点），按时间排序并标注是否已打。
  List<DayPlan> get todayPlan {
    final plans = <DayPlan>[];
    for (final m in medicines) {
      for (final min in m.scheduleMinutes) {
        plans.add(DayPlan(m, min));
      }
    }
    plans.sort((a, b) => a.minute.compareTo(b.minute));
    // 打卡数从早到晚依次点亮计划项
    for (final m in medicines) {
      var taken = takenToday(m.id);
      for (final p in plans) {
        if (p.medicine.id == m.id) {
          p.taken = taken > 0;
          taken--;
        }
      }
    }
    return plans;
  }

  double get todayProgress {
    final plans = todayPlan;
    if (plans.isEmpty) return 0;
    return plans.where((p) => p.taken).length / plans.length;
  }

  /// 近 7 天每日依从率（0~1）。
  List<double> get weeklyAdherence {
    final result = <double>[];
    for (var i = 6; i >= 0; i--) {
      final day = DateTime(now.year, now.month, now.day - i);
      final next = day.add(const Duration(days: 1));
      final count = weekLogs
          .where(
            (l) =>
                l.takenAt >= day.millisecondsSinceEpoch &&
                l.takenAt < next.millisecondsSinceEpoch,
          )
          .length;
      final planned = medicines.fold<int>(
        0,
        (s, m) => s + m.scheduleMinutes.length,
      );
      result.add(planned == 0 ? 0 : (count / planned).clamp(0.0, 1.0));
    }
    return result;
  }

  /// 近 7 天依从率里已打卡的连续天数（今天没打卡则从昨天起算）。
  int get streakDays {
    final dayCounts = List<int>.filled(7, 0);
    for (final l in weekLogs) {
      final d = DateTime.fromMillisecondsSinceEpoch(l.takenAt);
      final diff = DateTime(
        now.year,
        now.month,
        now.day,
      ).difference(DateTime(d.year, d.month, d.day)).inDays;
      if (diff >= 0 && diff < 7) dayCounts[6 - diff]++;
    }
    var i = 6;
    if (dayCounts[i] == 0) i--; // 今天还没打不算断
    var streak = 0;
    while (i >= 0 && dayCounts[i] > 0) {
      streak++;
      i--;
    }
    return streak;
  }

  Future<void> saveMedicine(Medicine m) =>
      db.saveMedicine(m).then((_) => refresh());

  Future<void> deleteMedicine(String id) =>
      db.softDeleteMedicine(id).then((_) => refresh());

  Future<void> checkIn(Medicine m) async {
    await db.checkInWithDeduction(
      DoseLog(
        id: LocalDb.newId(),
        medicineId: m.id,
        takenAt: DateTime.now().millisecondsSinceEpoch,
        amount: m.amountPerDose,
        updatedAt: 0,
      ),
    );
    await refresh();
  }

  Future<void> undoLog(DoseLog log) =>
      db.undoLogWithRefund(log).then((_) => refresh());

  Future<void> restock(Medicine m, double boxes) =>
      db.restock(m.id, boxes).then((_) => refresh());

  // ---------- 备份 ----------

  Future<String> exportBackup() async {
    final data = {
      'version': 2,
      'exportedAt': DateTime.now().toIso8601String(),
      'medicines': await db.outboxAll(tableMedicines),
      'dose_logs': await db.outboxAll(tableDoseLogs),
    };
    return const JsonEncoder.withIndent('  ').convert(data);
  }

  /// 导入备份：全部视为本地新变更（dirty），推送时按时间戳合并。
  Future<int> importBackup(String json) async {
    final data = jsonDecode(json) as Map<String, dynamic>;
    var count = 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final table in [tableMedicines, tableDoseLogs]) {
      final rows = (data[table] as List? ?? [])
          .map((e) => Map<String, Object?>.from(e as Map))
          .toList();
      for (final r in rows) {
        r['updated_at'] = now; // 导入的数据以当前时间为准
      }
      count += await db.applyIncoming(table, rows, forceDirty: true);
    }
    await refresh();
    return count;
  }

  /// 手动/自动同步；返回结果供界面提示。
  Future<SyncResult?> syncNow(BuildContext? context) async {
    if (busy) return null;
    busy = true;
    notifyListeners();
    final result = await sync.syncNow();
    busy = false;
    lastSyncMessage = result.toString();
    notifyListeners();
    if (context?.mounted == true) {
      final messenger = ScaffoldMessenger.of(context!);
      await refresh();
      messenger.showSnackBar(
        SnackBar(
          content: Text(result.ok ? '同步完成：$result' : result.toString()),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
    return result;
  }

  bool get isWindowsHost => Platform.isWindows;

  /// 供设置页在改动主题等偏好后触发全局重建。
  void refreshTheme() => notifyListeners();

  /// 暖纸 / 纯白配色一键切换。
  Future<void> setColorStyle(int v) async {
    settings.colorStyle = v;
    await settings.save();
    notifyListeners();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    unawaited(lanServer.stop());
    super.dispose();
  }
}
