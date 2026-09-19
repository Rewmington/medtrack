import 'dart:convert';

import 'package:http/http.dart' as http;

import '../db.dart';
import '../settings.dart';

/// 一轮同步的结果摘要，用于界面提示。
class SyncResult {
  final int pushed;
  final int pulled;
  final String? error;
  SyncResult({this.pushed = 0, this.pulled = 0, this.error});
  bool get ok => error == null;
  @override
  String toString() => ok ? '上传 $pushed 条，下载 $pulled 条' : '同步失败：$error';
}

/// 双向增量同步核心：先拉对端变更，再推本地 outbox。
class SyncService {
  final LocalDb db;
  final Settings settings;

  SyncService(this.db, this.settings);

  static const tables = [tableMedicines, tableDoseLogs];

  Future<SyncResult> syncNow() async {
    switch (settings.syncChannel) {
      case SyncChannel.off:
        return SyncResult(error: '未启用同步（当前为纯本地模式）');
      case SyncChannel.lan:
        if (settings.lanPeerUrl.isEmpty) {
          return SyncResult(error: '请先在设置中填写对端地址');
        }
        return _lanSync();
      case SyncChannel.supabase:
        if (settings.supabaseUrl.isEmpty || settings.supabaseAnonKey.isEmpty) {
          return SyncResult(error: '请先填写 Supabase 地址与 anon key');
        }
        return _supabaseSync();
    }
  }

  // ---------- 局域网通道 ----------

  Future<SyncResult> _lanSync() async {
    try {
      final since = {for (final t in tables) t: settings.cursor('lan:$t')};
      final outbox = {for (final t in tables) t: await db.outbox(t)};
      final url = settings.lanPeerUrl.replaceAll(RegExp(r'/+$'), '');
      final resp = await http
          .post(
            Uri.parse('$url/api/sync'),
            headers: {
              'content-type': 'application/json',
              if (settings.lanKey.isNotEmpty) 'x-sync-key': settings.lanKey,
            },
            body: jsonEncode({
              'device': settings.deviceId,
              'since': since,
              ...outbox.map((t, rows) => MapEntry(t, _json(rows))),
            }),
          )
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) {
        return SyncResult(error: '对端返回 ${resp.statusCode}');
      }
      final data =
          jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      final serverTime = (data['serverTime'] as num).toInt();
      var pushed = 0, pulled = 0;
      for (final t in tables) {
        final incoming = (data[t] as List? ?? [])
            .map((e) => Map<String, Object?>.from(e as Map))
            .toList();
        pulled += await db.applyIncoming(t, incoming);
        final ids = outbox[t]!.map((r) => r['id'] as String).toList();
        await db.clearDirty(t, ids, serverTime);
        pushed += ids.length;
        await settings.setCursor('lan:$t', serverTime);
      }
      return SyncResult(pushed: pushed, pulled: pulled);
    } catch (e) {
      return SyncResult(error: e.toString());
    }
  }

  static String _json(List<Map<String, Object?>> rows) => jsonEncode(rows);
  // ---------- Supabase 通道（PostgREST，无需登录） ----------

  Future<SyncResult> _supabaseSync() async {
    final base = settings.supabaseUrl.replaceAll(RegExp(r'/+$'), '');
    final headers = {
      'content-type': 'application/json',
      'apikey': settings.supabaseAnonKey,
      'Authorization': 'Bearer ${settings.supabaseAnonKey}',
      'Prefer': 'resolution=merge-duplicates',
    };
    try {
      var pushed = 0, pulled = 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      for (final t in tables) {
        final cursor = settings.cursor('sb:$t');
        final getResp = await http
            .get(
              Uri.parse('$base/rest/v1/$t?select=*&updated_at=gt.$cursor'),
              headers: headers,
            )
            .timeout(const Duration(seconds: 20));
        if (getResp.statusCode != 200) {
          return SyncResult(error: '拉取 $t 失败 ${getResp.statusCode}');
        }
        final incoming = (jsonDecode(utf8.decode(getResp.bodyBytes)) as List)
            .map((e) => Map<String, Object?>.from(e as Map))
            .toList();
        pulled += await db.applyIncoming(t, incoming);

        final out = await db.outbox(t);
        if (out.isNotEmpty) {
          final postResp = await http
              .post(
                Uri.parse('$base/rest/v1/$t?on_conflict=id'),
                headers: headers,
                // 安卓 sqflite 查询结果是只读 Map，推送前须复制再去掉 dirty。
                body: jsonEncode([
                  for (final r in out)
                    Map<String, Object?>.from(r)..remove('dirty'),
                ]),
              )
              .timeout(const Duration(seconds: 20));
          if (postResp.statusCode != 201 && postResp.statusCode != 200) {
            return SyncResult(
              error: '推送 $t 失败 ${postResp.statusCode}: ${postResp.body}',
            );
          }
          await db.clearDirty(
            t,
            out.map((r) => r['id'] as String).toList(),
            now,
          );
          pushed += out.length;
        }
        await settings.setCursor('sb:$t', now);
      }
      return SyncResult(pushed: pushed, pulled: pulled);
    } catch (e) {
      return SyncResult(error: e.toString());
    }
  }
}
