import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:medicine_tracker/db.dart';
import 'package:medicine_tracker/settings.dart';
import 'package:medicine_tracker/sync/sync_service.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 坚果云通道的真机端到端验证：拿本机真实库的副本当两台设备，跑真实 SyncService。
/// 默认跳过；带凭证才跑：
///   NJY_USER=邮箱 NJY_PASS=应用密码 flutter test test/webdav_sync_test.dart
void main() {
  const synthId = 'e2e-synthetic-row';
  const remoteDir = 'https://dav.jianguoyun.com/dav/medicine-sync/';

  final user = Platform.environment['NJY_USER'] ?? '';
  final pass = Platform.environment['NJY_PASS'] ?? '';
  final realDb = File(p.join(
      Platform.environment['APPDATA'] ?? '', 'dev.mine', 'medicine_tracker',
      'medicine_tracker.db'));
  final auth = 'Basic ${base64Encode(utf8.encode('$user:$pass'))}';

  Future<List<String>> remoteFiles() async {
    final c = HttpClient()..findProxy = (_) => 'DIRECT';
    final req = await c.openUrl('PROPFIND', Uri.parse(remoteDir))
      ..headers.set(HttpHeaders.authorizationHeader, auth)
      ..headers.set('Depth', '1');
    final resp = await req.close().timeout(const Duration(seconds: 25));
    final body = await resp.transform(utf8.decoder).join();
    c.close();
    if (resp.statusCode != 207) return [];
    return RegExp(r'<[a-zA-Z]*:?href>([^<]*)</[a-zA-Z]*:?href>',
            caseSensitive: false)
        .allMatches(body)
        .map((m) => Uri.decodeComponent(m.group(1)!.split('/').last))
        .where((n) => n.endsWith('.json'))
        .toList();
  }

  Future<void> removeRemote(String name) async {
    final c = HttpClient()..findProxy = (_) => 'DIRECT';
    final req = await c.openUrl('DELETE', Uri.parse('$remoteDir$name'))
      ..headers.set(HttpHeaders.authorizationHeader, auth);
    await (await req.close().timeout(const Duration(seconds: 25))).drain<void>();
    c.close();
  }

  test('两台设备经坚果云双向同步', () async {
    sqfliteFfiInit();
    final tmp = await Directory.systemTemp.createTemp('mt-e2e');
    final aPath = p.join(tmp.path, 'A.db');
    final bPath = p.join(tmp.path, 'B.db');
    await realDb.copy(aPath);
    await realDb.copy(bPath);

    Settings cfg(String device) => Settings()
      ..syncChannel = SyncChannel.webdav
      ..webdavUser = user
      ..webdavPass = pass
      ..deviceId = device;
    Future<LocalDb> open(String path) async {
      final db = LocalDb();
      await db.open(overridePath: path);
      return db;
    }

    final dbA = await open(aPath);
    final r1 = await SyncService(dbA, cfg('e2e-A')).syncNow();
    expect(r1.ok, isTrue, reason: 'A 首次同步：${r1.error}');

    // B 造一条本地新记录，模拟在手机上刚打了一次卡
    final rawB = await databaseFactoryFfi.openDatabase(bPath);
    final now = DateTime.now().millisecondsSinceEpoch;
    await rawB.insert(tableDoseLogs, {
      'id': synthId,
      'medicine_id': 'e2e',
      'taken_at': now,
      'amount': 1.0,
      'note': '端到端验证行',
      'updated_at': now,
      'deleted': 0,
      'dirty': 1,
    });
    await rawB.close();

    final dbB = await open(bPath);
    final r2 = await SyncService(dbB, cfg('e2e-B')).syncNow();
    expect(r2.ok && r2.pushed >= 1, isTrue, reason: 'B 推送新记录：$r2');

    final r3 = await SyncService(dbA, cfg('e2e-A')).syncNow();
    expect(r3.ok && r3.pulled >= 1, isTrue, reason: 'A 拉取 B 的变更：$r3');

    // 同一路径二次 openDatabase 拿到的是同一个句柄，close 会连带关掉 dbA，
    // 所以这里直接用已打开的 LocalDb 查。
    final merged = await dbA.outboxAll(tableDoseLogs);
    expect(merged.any((r) => r['id'] == synthId), isTrue,
        reason: 'A 库里应查得到那条合成记录');

    // 第三次不该重复拉取，也不该留下待推行
    final r4 = await SyncService(dbA, cfg('e2e-A')).syncNow();
    expect(r4.ok && r4.pulled == 0, isTrue, reason: '重复同步应幂等：$r4');
    expect(await dbA.outbox(tableDoseLogs), isEmpty, reason: '同步后 dirty 应清空');

    final names = await remoteFiles();
    expect(names, containsAll(['device-e2e-A.json', 'device-e2e-B.json']),
        reason: '每台设备应各存一份，实际：$names');

    for (final n in names.where((n) => n.startsWith('device-e2e-'))) {
      await removeRemote(n);
    }
    await dbA.close();
    await dbB.close();
    await tmp.delete(recursive: true);
  }, skip: user.isEmpty || pass.isEmpty || !realDb.existsSync()
      ? '需要 NJY_USER / NJY_PASS 环境变量与本机库文件'
      : false);
}
