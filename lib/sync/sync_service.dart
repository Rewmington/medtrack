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
      case SyncChannel.webdav:
        if (settings.webdavUser.isEmpty || settings.webdavPass.isEmpty) {
          return SyncResult(error: '请先填写坚果云账号与应用密码');
        }
        return _webdavSync();
    }
  }

  // ---------- 局域网通道 ----------

  Future<SyncResult> _lanSync() async {
    try {
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
              // 固定全量拉取：时间戳游标取的是对端时钟，换主机或时钟有偏差就会永久漏记录。
              'since': {for (final t in tables) t: 0},
              ...outbox.map((t, rows) => MapEntry(t, _json(rows))),
            }),
          )
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) {
        return SyncResult(error: '对端返回 ${resp.statusCode}');
      }
      final data =
          jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      var pushed = 0, pulled = 0;
      for (final t in tables) {
        final incoming = (data[t] as List? ?? [])
            .map((e) => Map<String, Object?>.from(e as Map))
            .toList();
        pulled += await db.applyIncoming(t, incoming);
        final rows = outbox[t]!;
        await db.clearDirty(t, _versions(rows));
        pushed += rows.length;
      }
      return SyncResult(pushed: pushed, pulled: pulled);
    } catch (e) {
      return SyncResult(error: e.toString());
    }
  }

  /// 推送出去的那些行的版本（id → updated_at），用于确认没被并发改动。
  static Map<String, int> _versions(List<Map<String, Object?>> rows) => {
    for (final r in rows)
      r['id'] as String: (r['updated_at'] as num?)?.toInt() ?? 0,
  };

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
      for (final t in tables) {
        // 全量拉取：游标若用本机时钟，另一端时钟落后于上次游标的行会被永久跳过，
        // 表现就是手机满勤、电脑一堆遗漏。数据量是个位到几百行，代价可忽略。
        final getResp = await http
            .get(Uri.parse('$base/rest/v1/$t?select=*'), headers: headers)
            .timeout(const Duration(seconds: 20));
        if (getResp.statusCode != 200) {
          return SyncResult(error: '拉取 $t 失败 ${getResp.statusCode}');
        }
        final incoming = (jsonDecode(utf8.decode(getResp.bodyBytes)) as List)
            .map((e) => Map<String, Object?>.from(e as Map))
            .toList();
        pulled += await db.applyIncoming(t, incoming);

        // 上一步已见过远端每一版，剩下的 dirty 行必然更新，可安全覆盖
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
          await db.clearDirty(t, _versions(out));
          pushed += out.length;
        }
      }
      return SyncResult(pushed: pushed, pulled: pulled);
    } catch (e) {
      return SyncResult(error: e.toString());
    }
  }

  // ---------- 坚果云 WebDAV 通道（国内直连，不依赖任何代理） ----------

  static const _wdBase = 'https://dav.jianguoyun.com/dav/';

  /// 坚果云不允许在根目录直接建文件，所以所有数据都放在这一层目录下。
  static const _wdDir = 'medicine-sync';

  Future<http.Response> _wd(String method, String path,
      {String? body, String contentType = 'text/plain'}) async {
    final req = http.Request(method, Uri.parse('$_wdBase$path'))
      ..headers['Authorization'] =
          'Basic ${base64Encode(utf8.encode('${settings.webdavUser}:${settings.webdavPass}'))}'
      ..headers['Content-Type'] = contentType;
    if (method == 'PROPFIND') req.headers['Depth'] = '1';
    if (body != null) req.bodyBytes = utf8.encode(body);
    return http.Response.fromStream(
        await req.send().timeout(const Duration(seconds: 25)));
  }

  Future<SyncResult> _webdavSync() async {
    final mine = 'device-${settings.deviceId}.json';
    try {
      final mk = await _wd('MKCOL', '$_wdDir/');
      if (mk.statusCode != 201 && mk.statusCode != 405) {
        return SyncResult(error: _wdHint(mk.statusCode, '建目录'));
      }
      final list = await _wd('PROPFIND', '$_wdDir/');
      if (list.statusCode != 207) {
        return SyncResult(error: _wdHint(list.statusCode, '列目录'));
      }
      var pulled = 0;
      for (final name in _propfindFiles(list.body)) {
        if (name == mine) continue; // 自己那份必然与本地一致，省一次请求
        final get = await _wd('GET', '$_wdDir/$name');
        if (get.statusCode != 200) {
          return SyncResult(error: _wdHint(get.statusCode, '读取 $name'));
        }
        final doc = jsonDecode(utf8.decode(get.bodyBytes)) as Map;
        for (final t in tables) {
          final rows = (doc[t] as List? ?? [])
              .map((e) => Map<String, Object?>.from(e as Map))
              .toList();
          pulled += await db.applyIncoming(t, rows);
        }
      }

      // 合并完之后整表发布自己这一份：第三台设备只读任意一份就能拿到全量，
      // 不存在"谁持有权威副本"的问题，各设备只覆盖自己的文件。
      final dirty = {for (final t in tables) t: await db.outbox(t)};
      final doc = <String, Object?>{
        'device': settings.deviceId,
        'published_at': DateTime.now().millisecondsSinceEpoch,
        for (final t in tables)
          t: [
            for (final r in await db.outboxAll(t))
              Map<String, Object?>.from(r)..remove('dirty'),
          ],
      };
      final put = await _wd('PUT', '$_wdDir/$mine',
          body: jsonEncode(doc), contentType: 'application/json');
      if (put.statusCode != 201 && put.statusCode != 204) {
        return SyncResult(error: _wdHint(put.statusCode, '推送'));
      }
      for (final t in tables) {
        await db.clearDirty(t, _versions(dirty[t]!));
      }
      return SyncResult(
          pushed: dirty.values.fold(0, (n, rows) => n + rows.length),
          pulled: pulled);
    } catch (e) {
      return SyncResult(error: e.toString());
    }
  }

  static String _wdHint(int code, String step) => switch (code) {
        401 || 403 => '坚果云$step 被拒（$code）：检查账号是否填注册邮箱、密码是否用「第三方应用管理」里的应用密码',
        _ => '坚果云$step 失败 $code',
      };

  /// 只认本 App 发布的设备文件；同目录下他放的东西（比如手动备份的 JSON）不参与合并。
  static List<String> _propfindFiles(String xml) => RegExp(
          r'<[a-zA-Z]*:?href>([^<]*)</[a-zA-Z]*:?href>',
          caseSensitive: false)
      .allMatches(xml)
      .map((m) => Uri.decodeComponent(m.group(1)!.split('/').last))
      .where((n) => n.startsWith('device-') && n.endsWith('.json'))
      .toList();
}
