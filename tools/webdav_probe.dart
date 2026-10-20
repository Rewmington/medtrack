// 坚果云 WebDAV 通道探针：只依赖 dart:io，可单独 dart run。
// 用法：NJY_USER=邮箱 NJY_PASS=应用密码 dart run tools/webdav_probe.dart
import 'dart:convert';
import 'dart:io';
import 'dart:math';

const base = 'https://dav.jianguoyun.com/dav/';
const dir = 'medicine-sync-probe';

late final String authHeader;
final rnd = Random(7);

void main() async {
  final user = Platform.environment['NJY_USER'];
  final pass = Platform.environment['NJY_PASS'];
  if (user == null || user.isEmpty || pass == null || pass.isEmpty) {
    stderr.writeln('缺凭证：请先设 NJY_USER（邮箱）与 NJY_PASS（第三方应用密码）');
    exit(2);
  }
  authHeader =
      'Basic ${base64Encode(utf8.encode('$user:$pass'))}';
  print('账号 ${user.substring(0, min(3, user.length))}***@'
      '${user.split("@").last}（凭证只走环境变量，不写盘）');

  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 10)
    // 探针要测的就是"不挂代理能不能直连"，任何环境变量代理都会污染结论。
    ..findProxy = (_) => 'DIRECT';

  var okCnt = 0, badCnt = 0;
  void report(String step, bool ok, String detail) {
    ok ? okCnt++ : badCnt++;
    print('${ok ? ' 通过' : ' 失败'}  $step  $detail');
  }

  // A. 无凭证握手基线：401/403 都说明 TLS 与端点活着（坚果云对裸请求回 403）
  for (var i = 1; i <= 3; i++) {
    final r = await _req(client, 'GET', '', null, null);
    report('A$i 裸握手 TLS 耗时', (r.code == 401 || r.code == 403) && r.ms < 4000,
        'HTTP ${r.code}  TLS+请求 ${r.ms}ms');
  }

  // B. 建目录
  final mk = await _req(client, 'MKCOL', '$dir/', null, null);
  report('B  MKCOL 同步目录', mk.code == 201 || mk.code == 405 || mk.code == 200,
      'HTTP ${mk.code}（405=已存在，也算通过） ${mk.ms}ms');

  // C/D. 真实大小载荷写+读校验
  final payload = _payload(200);
  final put1 = await _req(client, 'PUT', '$dir/probe.json', payload, 'application/json');
  report('C  PUT ${payload.length}B', put1.code == 201 || put1.code == 204 || put1.code == 200,
      'HTTP ${put1.code}  ${put1.ms}ms  ${(payload.length / 1024 / (put1.ms / 1000)).toStringAsFixed(0)} KB/s');

  final get1 = await _req(client, 'GET', '$dir/probe.json', null, null);
  report('D  GET 回读逐字节一致', get1.code == 200 && _same(get1.body, payload),
      'HTTP ${get1.code}  ${get1.body.length}B / 期望 ${payload.length}B  ${get1.ms}ms');

  // E. 覆盖写（同步要反复覆盖同一个文件，这条最关键）
  final payload2 = _payload(260);
  final put2 = await _req(client, 'PUT', '$dir/probe.json', payload2, 'application/json');
  final get2 = await _req(client, 'GET', '$dir/probe.json', null, null);
  report('E  覆盖写后读到新内容', get2.code == 200 && _same(get2.body, payload2),
      'PUT HTTP ${put2.code} ${put2.ms}ms / GET ${get2.body.length}B');

  // F/G. 多设备模型：各写各的文件，靠 PROPFIND 枚举出来
  final devA = _payload(90);
  final devB = _payload(120);
  final pa = await _req(client, 'PUT', '$dir/device-A.json', devA, 'application/json');
  final pb = await _req(client, 'PUT', '$dir/device-B.json', devB, 'application/json');
  report('F  两台设备各写一个文件', (pa.code == 201 || pa.code == 204) && (pb.code == 201 || pb.code == 204),
      'HTTP ${pa.code}/${pb.code}');

  final pf = await _req(client, 'PROPFIND', '$dir/', null, null, depth: '1');
  final names = _propfindNames(pf.text);
  report('G  PROPFIND 能枚举全部设备文件', pf.code == 207 && names.contains('device-A.json') && names.contains('device-B.json'),
      'HTTP ${pf.code}  条目 ${names.length}  ${names.join(', ')}');

  // H. 一轮完整同步的代价：枚举 + 逐个读 + 覆盖写自己那份
  final t0 = DateTime.now();
  for (final n in names.where((n) => n.endsWith('.json'))) {
    await _req(client, 'GET', '$dir/$n', null, null);
  }
  await _req(client, 'PUT', '$dir/device-A.json', _payload(95), 'application/json');
  final roundMs = DateTime.now().difference(t0).inMilliseconds;
  report('H  一轮同步（${names.length} 读 + 1 写）总耗时', roundMs < 8000,
      '${roundMs}ms（Supabase 通道实测 500–2700ms，同一量级即可）');

  // I. 频率余量：连打 20 次，看免费版限制（600 次/30min）会不会碰壁
  var ok20 = 0;
  final costs = <int>[];
  for (var i = 0; i < 20; i++) {
    final r = await _req(client, 'GET', '$dir/probe.json', null, null);
    if (r.code == 200) ok20++;
    costs.add(r.ms);
  }
  costs.sort();
  report('I  连发 20 次无 429/503', ok20 == 20,
      '成功 $ok20/20  中位 ${costs[costs.length ~/ 2]}ms  最慢 ${costs.last}ms');

  // J. 清理
  final delCodes = <String, int>{};
  for (final n in {...names, 'probe.json'}) {
    delCodes[n] = (await _req(client, 'DELETE', '$dir/$n', null, null)).code;
  }
  final rd = await _req(client, 'DELETE', '$dir/', null, null);
  final clean =
      delCodes.values.every((c) => c == 200 || c == 204 || c == 404);
  // 坚果云不允许通过 WebDAV 删除顶层目录（实测一律 403），只能在网页端手删；
  // 目录里已经空了，所以这里不把 403 判为失败。
  report('J  清理探针文件', clean,
      '文件 ${delCodes.values.join("/")}  目录 HTTP ${rd.code}'
      '${rd.code == 403 ? '（顶层目录删不掉，需在网页端手动删除 $dir）' : ''}');

  client.close();
  print('\n合计 通过 $okCnt / 失败 $badCnt');
  exit(badCnt == 0 ? 0 : 1);
}

/// 造一条与 dose_logs 同形状的 JSON，行数决定体积（200 行 ≈ 45KB，与线上实测一致）。
List<int> _payload(int rows) {
  final list = [
    for (var i = 0; i < rows; i++)
      {
        'id': 'log-${i.toString().padLeft(5, '0')}',
        'medicine_id': 'med-0001',
        'taken_at': 1760000000000 + i * 3600000,
        'amount': (i % 2 == 0 ? 1.0 : 0.5),
        'note': i % 7 == 0 ? '早餐后' : null,
        'updated_at': 1760000000000 + i * 3600000 + rnd.nextInt(1000),
        'deleted': 0,
      }
  ];
  return utf8.encode(jsonEncode(list));
}

bool _same(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

List<String> _propfindNames(String xml) => RegExp(r'<D:href>([^<]*)</D:href>',
        caseSensitive: false)
    .allMatches(xml)
    .map((m) => Uri.decodeComponent(m.group(1)!.split('/').last))
    .where((s) => s.isNotEmpty)
    .toList();

class _R {
  final int code;
  final List<int> body;
  final int ms;
  _R(this.code, this.body, this.ms);
  String get text => utf8.decode(body, allowMalformed: true);
}

Future<_R> _req(HttpClient client, String method, String path, List<int>? body,
    String? contentType, {bool auth = true, String? depth}) async {
  final sw = Stopwatch()..start();
  final req = await client.openUrl(method, Uri.parse('$base$path'));
  req.headers.set(HttpHeaders.acceptHeader, 'application/json,*/*');
  if (auth) req.headers.set(HttpHeaders.authorizationHeader, authHeader);
  if (depth != null) req.headers.set('Depth', depth);
  if (contentType != null) req.headers.contentType = ContentType.parse(contentType);
  if (body != null) {
    req.contentLength = body.length;
    req.add(body);
  }
  final resp = await req.close().timeout(const Duration(seconds: 25));
  final out = <int>[];
  await for (final chunk in resp) {
    out.addAll(chunk);
  }
  sw.stop();
  return _R(resp.statusCode, out, sw.elapsedMilliseconds);
}
