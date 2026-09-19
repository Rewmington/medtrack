import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

import 'models.dart';

const tableMedicines = 'medicines';
const tableDoseLogs = 'dose_logs';

const _columns = {
  tableMedicines:
      'id TEXT PRIMARY KEY, name TEXT, boxes REAL, per_box REAL, remaining REAL, '
      'doses_per_day REAL, amount_per_dose REAL, unit TEXT, low_days INTEGER, '
      'note TEXT, times TEXT, created_at INTEGER, updated_at INTEGER, deleted INTEGER, dirty INTEGER',
  tableDoseLogs:
      'id TEXT PRIMARY KEY, medicine_id TEXT, taken_at INTEGER, amount REAL, '
      'note TEXT, updated_at INTEGER, deleted INTEGER, dirty INTEGER',
};

class LocalDb {
  late final Database _db;

  static final _uuid = const Uuid();
  static String newId() => _uuid.v4();

  Future<void> open() async {
    final isDesktop =
        Platform.isWindows || Platform.isLinux || Platform.isMacOS;
    if (isDesktop) sqfliteFfiInit();
    final factory = isDesktop ? databaseFactoryFfi : databaseFactory;
    final dir = await getApplicationSupportDirectory();
    final path = p.join(dir.path, 'medicine_tracker.db');
    _db = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 2,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, v) async {
          for (final e in _columns.entries) {
            await db.execute('CREATE TABLE ${e.key} (${e.value})');
          }
          await db.execute(
            'CREATE INDEX idx_logs_med ON dose_logs(medicine_id, taken_at)',
          );
        },
        onUpgrade: (db, old, newV) async {
          if (old < 2 && newV >= 2) {
            await db.execute('ALTER TABLE medicines ADD COLUMN remaining REAL');
            await db.execute('ALTER TABLE medicines ADD COLUMN times TEXT');
            await db.execute(
              'UPDATE medicines SET remaining = boxes * per_box WHERE remaining IS NULL',
            );
          }
        },
      ),
    );
  }

  int _now() => DateTime.now().millisecondsSinceEpoch;

  // ---------- 业务读写（本地写入一律标 dirty=1） ----------

  Future<List<Medicine>> activeMedicines() async {
    final rows = await _db.query(
      tableMedicines,
      where: 'deleted = 0',
      orderBy: 'updated_at DESC',
    );
    return rows.map(Medicine.fromRow).toList();
  }

  Future<List<DoseLog>> logsFor(DateTime day) async {
    final start = DateTime(day.year, day.month, day.day);
    return logsBetween(start, start.add(const Duration(days: 1)));
  }

  Future<List<DoseLog>> logsBetween(DateTime start, DateTime end) async {
    final rows = await _db.query(
      tableDoseLogs,
      where: 'deleted = 0 AND taken_at >= ? AND taken_at < ?',
      whereArgs: [start.millisecondsSinceEpoch, end.millisecondsSinceEpoch],
      orderBy: 'taken_at DESC',
    );
    return rows.map(DoseLog.fromRow).toList();
  }

  Future<List<DoseLog>> recentLogs({int limit = 200}) async {
    final rows = await _db.query(
      tableDoseLogs,
      where: 'deleted = 0',
      orderBy: 'taken_at DESC',
      limit: limit,
    );
    return rows.map(DoseLog.fromRow).toList();
  }

  Future<void> saveMedicine(Medicine m) async {
    m.updatedAt = _now();
    final row = m.toRow()..['dirty'] = 1;
    await _db.insert(
      tableMedicines,
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> softDeleteMedicine(String id) async {
    await _db.update(
      tableMedicines,
      {'deleted': 1, 'updated_at': _now(), 'dirty': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> addLog(DoseLog log) async {
    log.updatedAt = _now();
    final row = log.toRow()..['dirty'] = 1;
    await _db.insert(
      tableDoseLogs,
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 打卡并自动扣减库存，二者同一事务。
  Future<void> checkInWithDeduction(DoseLog log) async {
    log.updatedAt = _now();
    final now = log.updatedAt;
    final row = log.toRow()..['dirty'] = 1;
    await _db.transaction((txn) async {
      await txn.insert(
        tableDoseLogs,
        row,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.rawUpdate(
        'UPDATE medicines SET remaining = MAX(COALESCE(remaining, boxes * per_box) - ?, 0), '
        'updated_at = ?, dirty = 1 WHERE id = ?',
        [log.amount, now, log.medicineId],
      );
    });
  }

  /// 补货：加 [boxes] 盒。
  Future<void> restock(String medicineId, double boxes) async {
    await _db.rawUpdate(
      'UPDATE medicines SET remaining = COALESCE(remaining, boxes * per_box) + ? * per_box, '
      'updated_at = ?, dirty = 1 WHERE id = ?',
      [boxes, _now(), medicineId],
    );
  }

  Future<void> softDeleteLog(String id) async {
    await _db.update(
      tableDoseLogs,
      {'deleted': 1, 'updated_at': _now(), 'dirty': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// 撤销打卡并回补库存。
  Future<void> undoLogWithRefund(DoseLog log) async {
    final now = _now();
    await _db.transaction((txn) async {
      await txn.update(
        tableDoseLogs,
        {'deleted': 1, 'updated_at': now, 'dirty': 1},
        where: 'id = ?',
        whereArgs: [log.id],
      );
      await txn.rawUpdate(
        'UPDATE medicines SET remaining = COALESCE(remaining, boxes * per_box) + ?, '
        'updated_at = ?, dirty = 1 WHERE id = ?',
        [log.amount, now, log.medicineId],
      );
    });
  }

  // ---------- 同步原语 ----------

  /// 本地待推送的变更（含软删除）。
  Future<List<Map<String, Object?>>> outbox(String table) =>
      _db.query(table, where: 'dirty = 1');

  /// 全表导出（备份用）。
  Future<List<Map<String, Object?>>> outboxAll(String table) =>
      _db.query(table);

  /// 更新晚于 [since] 的全部行，用于推送给对端。
  Future<List<Map<String, Object?>>> changesSince(String table, int since) =>
      _db.query(table, where: 'updated_at > ?', whereArgs: [since]);

  /// 应用对端推来的行：时间戳新者胜；本地更新则保留待推送。
  Future<int> applyIncoming(
    String table,
    List<Map<String, Object?>> rows, {
    int? notNewerThan,
    bool forceDirty = false,
  }) async {
    var applied = 0;
    await _db.transaction((txn) async {
      for (final row in rows) {
        final id = row['id'];
        if (id is! String ||
            (notNewerThan != null &&
                (row['updated_at'] as int? ?? 0) > notNewerThan)) {
          continue;
        }
        final local = await txn.query(
          table,
          columns: ['updated_at', 'dirty'],
          where: 'id = ?',
          whereArgs: [id],
        );
        if (!forceDirty &&
            local.isNotEmpty &&
            (local.first['updated_at'] as int? ?? 0) >=
                (row['updated_at'] as int? ?? 0)) {
          continue; // 本地更新或相同，保留本地（dirty 行稍后推回去）
        }
        final clean = Map<String, Object?>.from(row)
          ..['dirty'] = forceDirty ? 1 : 0;
        await txn.insert(
          table,
          clean,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        applied++;
      }
    });
    return applied;
  }

  /// 推送成功后清 dirty（仅当行未被再次本地修改）。
  Future<void> clearDirty(String table, List<String> ids, int pushedAt) async {
    if (ids.isEmpty) return;
    final placeholders = List.filled(ids.length, '?').join(',');
    await _db.update(
      table,
      {'dirty': 0},
      where: 'id IN ($placeholders) AND updated_at <= ?',
      whereArgs: [...ids, pushedAt],
    );
  }

  Future<void> markAllDirty() => _db.transaction((txn) async {
    for (final t in _columns.keys) {
      await txn.update(t, {'dirty': 1}, where: '1=1');
    }
  });
}
