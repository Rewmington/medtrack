import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../db.dart';
import '../settings.dart';
import 'sync_service.dart';

/// 内置局域网同步服务：任一设备开启后，对端可直接 POST /api/sync 完成双向增量同步。
class LanSyncServer {
  final LocalDb db;
  final Settings settings;
  HttpServer? _server;

  LanSyncServer(this.db, this.settings);

  bool get running => _server != null;

  Future<String?> start() async {
    if (_server != null) return null;
    try {
      _server = await HttpServer.bind(
        InternetAddress.anyIPv4,
        settings.lanPort,
        shared: false,
      );
    } on SocketException catch (e) {
      return '端口 ${settings.lanPort} 占用：$e';
    }
    unawaited(_loop());
    return null;
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  Future<List<String>> localAddresses() async {
    final result = <String>[];
    for (final iface in await NetworkInterface.list()) {
      for (final addr in iface.addresses) {
        if (addr.address.contains('.')) result.add(addr.address);
      }
    }
    return result;
  }

  Future<void> _loop() async {
    await for (final req in _server!) {
      try {
        await _handle(req);
      } catch (e) {
        req.response.statusCode = 500;
        req.response.write(jsonEncode({'error': '$e'}));
        await req.response.close();
      }
    }
  }

  Future<void> _handle(HttpRequest req) async {
    req.response.headers.set('content-type', 'application/json; charset=utf-8');
    if (req.method == 'GET' && req.uri.path == '/api/ping') {
      req.response.write(jsonEncode({'ok': true, 'device': settings.deviceId}));
      await req.response.close();
      return;
    }
    if (req.method != 'POST' || req.uri.path != '/api/sync') {
      req.response.statusCode = 404;
      await req.response.close();
      return;
    }
    if (settings.lanKey.isNotEmpty &&
        req.headers.value('x-sync-key') != settings.lanKey) {
      req.response.statusCode = 401;
      req.response.write(jsonEncode({'error': '密钥不正确'}));
      await req.response.close();
      return;
    }
    final body =
        jsonDecode(await utf8.decoder.bind(req).join()) as Map<String, dynamic>;
    final now = DateTime.now().millisecondsSinceEpoch;
    // 容忍最多 1 小时的时钟偏差，拒绝明显来自未来的写入。
    final tolerance = now + const Duration(hours: 24).inMilliseconds;
    final response = <String, Object?>{
      'serverTime': now,
      'device': settings.deviceId,
    };
    for (final t in SyncService.tables) {
      final incoming = (body[t] as List? ?? [])
          .map((e) => Map<String, Object?>.from(e as Map))
          .toList();
      await db.applyIncoming(t, incoming, notNewerThan: tolerance);
      final since = (body['since']?[t] as num?)?.toInt() ?? 0;
      response[t] = await db.changesSince(t, since);
    }
    req.response.write(jsonEncode(response));
    await req.response.close();
  }
}
