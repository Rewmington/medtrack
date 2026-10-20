// 只读导出：把本机 App 的当前数据导成与「导出到剪贴板」完全同格式的备份文件。
// 用法：dart run tools/export_backup.dart [输出路径]
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> main(List<String> args) async {
  final live = File(p.join(
      Platform.environment['APPDATA']!, 'dev.mine', 'medicine_tracker', 'medicine_tracker.db'));
  if (!live.existsSync()) {
    stderr.writeln('找不到本机库：${live.path}');
    exit(2);
  }
  // 复制一份再只读打开：真库零写入，App 正在跑也不会互相干扰。
  final tmp = File(p.join(Directory.systemTemp.path, 'export-readonly-${DateTime.now().millisecondsSinceEpoch}.db'));
  await live.copy(tmp.path);

  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(tmp.path,
      options: OpenDatabaseOptions(readOnly: true, singleInstance: false));
  final out = <String, Object?>{
    'version': 2,
    'exportedAt': DateTime.now().toIso8601String(),
    'medicines': await db.query('medicines'),
    'dose_logs': await db.query('dose_logs'),
  };
  final json = const JsonEncoder.withIndent('  ').convert(out);
  final dest = File(args.isEmpty
      ? 'C:\\Users\\hp\\Desktop\\medicine-backup-${DateTime.now().toIso8601String().substring(0, 10)}.json'
      : args.first);
  await dest.writeAsString(json, encoding: utf8);
  await db.close();
  await tmp.delete();

  final logs = out['dose_logs'] as List;
  final meds = out['medicines'] as List;
  print('已写出 ${dest.path}  ${(json.length / 1024).toStringAsFixed(1)} KB');
  print('药品 ${meds.length} 条（含软删除），打卡记录 ${logs.length} 条（含软删除）');
  print('\n药名 / 库存 / 每日剂量次数：');
  for (final m in meds.where((m) => (m['deleted'] ?? 0) == 0)) {
    print('  ${m['name']}  remaining=${m['remaining']}  times=${m['times']}');
  }
  final byMonth = <String, int>{};
  for (final l in logs.where((l) => (l['deleted'] ?? 0) == 0)) {
    final d = DateTime.fromMillisecondsSinceEpoch(l['taken_at'] as int);
    byMonth['${d.year}-${d.month.toString().padLeft(2, '0')}'] =
        (byMonth['${d.year}-${d.month.toString().padLeft(2, '0')}'] ?? 0) + 1;
  }
  print('\n每月有效打卡条数（依从率的分子来源）：');
  for (final k in byMonth.keys.toList()..sort()) {
    print('  $k  ${byMonth[k]}');
  }
}
