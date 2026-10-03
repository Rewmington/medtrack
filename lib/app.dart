import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'db.dart';
import 'models.dart';
import 'settings.dart';
import 'sync/lan_server.dart';
import 'sync/sync_service.dart';

class DayPlan {
  final Medicine medicine;
  final int minute; // 计划时间
  bool taken; // 已打卡
  bool skipped; // 标记为「这顿没吃」，不扣库存、不算依从
  int? takenAtMs; // 对应打卡的实际时刻
  DoseLog? takenLog; // 命中的那条打卡记录（补录的在别处展示）
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
  DayPlan(
    this.medicine,
    this.minute, {
    this.taken = false,
    this.skipped = false,
    this.takenAtMs,
    this.takenLog,
  });
}

/// 过去某日没打卡的时间槽，用于补录。
class MissedSlot {
  final Medicine medicine;
  final DateTime slotTime; // 本该服药的时刻
  MissedSlot(this.medicine, this.slotTime);
}

class AppController extends ChangeNotifier {
  final LocalDb db = LocalDb();
  final Settings settings = Settings();
  late final SyncService sync;
  late final LanSyncServer lanServer;

  List<Medicine> medicines = [];
  List<DoseLog> todayLogs = [];
  List<DoseLog> weekLogs = [];
  Map<String, List<DoseLog>> weekMap = {}; // 药 id → 近 7 天打卡
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
    weekMap = {
      for (final m in medicines)
        m.id: weekLogs.where((l) => l.medicineId == m.id).toList(),
    };
    notifyListeners();
  }

  /// 今天真正服下的次数（不含标记「没吃」的 0 剂量记录）。
  int takenToday(String medicineId) =>
      todayLogs.where((l) => l.medicineId == medicineId && !l.isSkipped).length;

  /// 今天被标记「没吃」的次数，这些格子从应服数里扣掉。
  int skippedToday(String medicineId) =>
      todayLogs.where((l) => l.medicineId == medicineId && l.isSkipped).length;

  /// 该药今天最近一次打卡，用于误点撤销。
  DoseLog? latestTodayLog(String medicineId) {
    final logs = todayLogs.where((l) => l.medicineId == medicineId).toList()
      ..sort((a, b) => b.takenAt.compareTo(a.takenAt));
    return logs.isEmpty ? null : logs.first;
  }

  /// 今日应服计划表（药 × 时间点），按时间排序；打卡按时刻就近匹配到槽位。
  List<DayPlan> get todayPlan {
    final dayStart = DateTime(
      now.year,
      now.month,
      now.day,
    ).millisecondsSinceEpoch;
    final plans = <DayPlan>[];
    for (final m in medicines) {
      final slots = m.scheduleMinutes;
      final logs = todayLogs.where((l) => l.medicineId == m.id).toList()
        ..sort((a, b) => a.takenAt.compareTo(b.takenAt));
      final matched = matchSlots(slots, [
        for (final l in logs) l.takenAt,
      ], dayStart);
      for (var i = 0; i < slots.length; i++) {
        final log = matched[i] == null
            ? null
            : logs.firstWhere((l) => l.takenAt == matched[i]);
        plans.add(
          DayPlan(
            m,
            slots[i],
            taken: log != null && !log.isSkipped,
            skipped: log != null && log.isSkipped,
            takenAtMs: matched[i],
            takenLog: log,
          ),
        );
      }
    }
    plans.sort((a, b) => a.minute.compareTo(b.minute));
    return plans;
  }

  /// 最近 [backfillDays] 天里该服却没打卡的槽（不含今天，今天归「现在该吃的」管）。
  List<MissedSlot> get missedSlots {
    final result = <MissedSlot>[];
    for (final m in medicines) {
      final slots = m.scheduleMinutes;
      if (slots.isEmpty) continue;
      final logs = weekMap[m.id] ?? const <DoseLog>[];
      for (var back = backfillDays; back >= 1; back--) {
        final day = DateTime(now.year, now.month, now.day - back);
        final dayStart = day.millisecondsSinceEpoch;
        final nextStart = dayStart + const Duration(days: 1).inMilliseconds;
        final dayLogs = logs
            .where((l) => l.takenAt >= dayStart && l.takenAt < nextStart)
            .map((l) => l.takenAt)
            .toList();
        final matched = matchSlots(slots, dayLogs, dayStart);
        for (var i = 0; i < slots.length; i++) {
          if (matched[i] != null) continue;
          final slotTime = DateTime(
            day.year,
            day.month,
            day.day,
            slots[i] ~/ 60,
            slots[i] % 60,
          );
          // 药品是那天之后才添加的，不存在"漏打"
          if (slotTime.isBefore(
            DateTime.fromMillisecondsSinceEpoch(m.createdAt),
          )) {
            continue;
          }
          result.add(MissedSlot(m, slotTime));
        }
      }
    }
    result.sort((a, b) => a.slotTime.compareTo(b.slotTime));
    return result;
  }

  static const backfillDays = 6; // 与 weekLogs 的 7 天窗口一致

  /// 补录一条漏打卡：按槽位时刻写记录、按每次剂量扣库存（与正常打卡同一条链路）。
  Future<void> backfillCheckIn(MissedSlot slot, BuildContext? context) async {
    final messenger = _messengerOf(context);
    await db.checkInWithDeduction(_backfillLog(slot));
    await refresh();
    final m = slot.medicine;
    messenger?.showSnackBar(
      SnackBar(
        content: Text(
          '已补录 ${m.name} ${DateFormat('M月d日 HH:mm').format(slot.slotTime)}，'
          '扣减 ${_trim(m.amountPerDose)} ${m.unit}',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// 批量补录：逐条写记录并扣库存，最后统一刷新一次。
  Future<void> backfillAll(
    List<MissedSlot> slots,
    BuildContext? context,
  ) async {
    final messenger = _messengerOf(context);
    for (final s in slots) {
      await db.checkInWithDeduction(_backfillLog(s));
    }
    await refresh();
    messenger?.showSnackBar(
      SnackBar(
        content: Text('已补录 ${slots.length} 条打卡'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  static ScaffoldMessengerState? _messengerOf(BuildContext? context) =>
      context == null || !context.mounted
      ? null
      : ScaffoldMessenger.of(context);

  static DoseLog _backfillLog(MissedSlot slot) => DoseLog(
    id: LocalDb.newId(),
    medicineId: slot.medicine.id,
    takenAt: slot.slotTime.millisecondsSinceEpoch,
    amount: slot.medicine.amountPerDose,
    note: '补录',
    updatedAt: 0,
  );

  /// 这顿没吃：写一条 0 剂量记录占住那个格子，不扣库存，也不算依从。
  Future<void> markSkipped(
    Medicine m,
    DateTime when,
    BuildContext? context,
  ) async {
    final messenger = _messengerOf(context);
    final ms = when.millisecondsSinceEpoch;
    // 同一格重复标记（连点、或两端各标一次）只留一条，否则会多占掉相邻的格子
    if (weekLogs.any(
      (l) => l.medicineId == m.id && l.isSkipped && l.takenAt == ms,
    )) {
      return;
    }
    await db.addLog(
      DoseLog(
        id: LocalDb.newId(),
        medicineId: m.id,
        takenAt: ms,
        amount: 0,
        note: '没吃',
        updatedAt: 0,
      ),
    );
    await refresh();
    messenger?.showSnackBar(
      SnackBar(
        content: Text(
          '已标记 ${m.name} ${DateFormat('M月d日 HH:mm').format(when)} 没吃，不扣库存',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// 批量标记没吃。
  Future<void> markAllSkipped(
    List<MissedSlot> slots,
    BuildContext? context,
  ) async {
    final messenger = _messengerOf(context);
    for (final s in slots) {
      await db.addLog(
        DoseLog(
          id: LocalDb.newId(),
          medicineId: s.medicine.id,
          takenAt: s.slotTime.millisecondsSinceEpoch,
          amount: 0,
          note: '没吃',
          updatedAt: 0,
        ),
      );
    }
    await refresh();
    messenger?.showSnackBar(
      SnackBar(
        content: Text('已标记 ${slots.length} 次没吃，未扣库存'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// 今天某个计划格子的实际时刻。
  DateTime slotTimeOf(int minute) =>
      DateTime(now.year, now.month, now.day, minute ~/ 60, minute % 60);

  static String _trim(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  /// 今日完成比例：分母扣掉标记没吃的格子。
  double get todayProgress {
    final plans = todayPlan.where((p) => !p.skipped).toList();
    if (plans.isEmpty) return 0;
    return plans.where((p) => p.taken).length / plans.length;
  }

  /// 近 7 天每日依从率（0~1）。标记没吃的格子既不算完成，也从应服数里扣除。
  List<double> get weeklyAdherence {
    final planned = medicines.fold<int>(
      0,
      (s, m) => s + m.scheduleMinutes.length,
    );
    final result = <double>[];
    for (var i = 6; i >= 0; i--) {
      final day = DateTime(now.year, now.month, now.day - i);
      final next = day.add(const Duration(days: 1));
      final thatDay = weekLogs.where(
        (l) =>
            l.takenAt >= day.millisecondsSinceEpoch &&
            l.takenAt < next.millisecondsSinceEpoch,
      );
      final taken = thatDay.where((l) => !l.isSkipped).length;
      final skipped = thatDay.length - taken;
      final owed = planned - skipped;
      result.add(switch (planned) {
        0 => 0.0,
        _ => (owed <= 0 ? 1.0 : taken / owed).clamp(0.0, 1.0),
      });
    }
    return result;
  }

  /// 近 7 天依从率里已打卡的连续天数（今天没打卡则从昨天起算）。
  int get streakDays {
    final dayCounts = List<int>.filled(7, 0);
    for (final l in weekLogs) {
      if (l.isSkipped) continue; // 没吃不算打卡
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
