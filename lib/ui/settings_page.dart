import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app.dart';
import '../settings.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final AppController app;
  late final TextEditingController _peer, _key, _port, _sbUrl, _sbKey;
  SyncChannel? _channel;

  @override
  void initState() {
    super.initState();
    app = context.read<AppController>();
    final s = app.settings;
    _channel = s.syncChannel;
    _peer = TextEditingController(text: s.lanPeerUrl);
    _key = TextEditingController(text: s.lanKey);
    _port = TextEditingController(text: '${s.lanPort}');
    _sbUrl = TextEditingController(text: s.supabaseUrl);
    _sbKey = TextEditingController(text: s.supabaseAnonKey);
  }

  @override
  void dispose() {
    _peer.dispose();
    _key.dispose();
    _port.dispose();
    _sbUrl.dispose();
    _sbKey.dispose();
    super.dispose();
  }

  Future<void> _apply() async {
    final s = app.settings;
    s.syncChannel = _channel ?? SyncChannel.off;
    s.lanPeerUrl = _peer.text;
    s.lanKey = _key.text;
    s.lanPort = int.tryParse(_port.text) ?? 8765;
    s.supabaseUrl = _sbUrl.text;
    s.supabaseAnonKey = _sbKey.text;
    await s.save();
    await app.lanServer.stop();
    if (s.lanHost) await app.lanServer.start();
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('设置已保存')));
    }
  }

  @override
  Widget build(BuildContext context) {
    // 订阅控制器：今天页的配色切换按钮等外部改动也能反映到本页选项上。
    context.watch<AppController>();
    final s = app.settings;
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
        children: [
          const _H('数据同步'),
          SegmentedButton<SyncChannel>(
            segments: const [
              ButtonSegment(value: SyncChannel.off, label: Text('纯本地')),
              ButtonSegment(value: SyncChannel.lan, label: Text('局域网')),
              ButtonSegment(value: SyncChannel.supabase, label: Text('云端')),
            ],
            selected: {_channel ?? SyncChannel.off},
            onSelectionChanged: (v) => setState(() => _channel = v.first),
          ),
          const SizedBox(height: 12),
          if (_channel == SyncChannel.lan)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('在本机开启同步服务'),
                      subtitle: const Text('Windows 电脑建议开启，供手机连接'),
                      value: s.lanHost,
                      onChanged: (v) => setState(() => s.lanHost = v),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _port,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: '监听端口'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _peer,
                      decoration: const InputDecoration(
                        labelText: '对端地址（另一台设备的同步服务）',
                        hintText: 'http://192.168.1.5:8765',
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _key,
                      decoration: const InputDecoration(
                        labelText: '同步密钥（两端一致，可留空）',
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        icon: const Icon(Icons.lan_outlined),
                        label: const Text('查看本机 IP 地址'),
                        onPressed: _showIps,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (_channel == SyncChannel.supabase)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    TextField(
                      controller: _sbUrl,
                      decoration: const InputDecoration(
                        labelText: 'Supabase URL',
                        hintText: 'https://xxxx.supabase.co',
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _sbKey,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: 'anon key'),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        icon: const Icon(Icons.help_outline),
                        label: const Text('查看云端建表 SQL'),
                        onPressed: _showSql,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (_channel != SyncChannel.off) ...[
            const SizedBox(height: 8),
            FilledButton(onPressed: _apply, child: const Text('保存同步设置')),
          ],
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: Icon(app.busy ? Icons.hourglass_top : Icons.sync),
            label: const Text('立即同步'),
            onPressed: app.busy ? null : () => app.syncNow(context),
          ),
          if (app.lastSyncMessage != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '上次同步：${app.lastSyncMessage}',
                style: const TextStyle(color: Colors.blueGrey, fontSize: 12),
              ),
            ),
          const SizedBox(height: 24),
          const _H('提醒'),
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('打开软件时低药量提醒'),
                    subtitle: const Text('启动时检测库存，不足则弹窗提示'),
                    value: s.lowStockReminders,
                    onChanged: (v) async {
                      setState(() => s.lowStockReminders = v);
                      await s.save();
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          const _H('外观'),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(
                value: 0,
                label: Text('跟随系统'),
                icon: Icon(Icons.brightness_auto),
              ),
              ButtonSegment(
                value: 1,
                label: Text('浅色'),
                icon: Icon(Icons.light_mode),
              ),
              ButtonSegment(
                value: 2,
                label: Text('深色'),
                icon: Icon(Icons.dark_mode),
              ),
            ],
            selected: {s.themeMode},
            onSelectionChanged: (v) async {
              setState(() => s.themeMode = v.first);
              await s.save();
              app.refreshTheme();
            },
          ),
          const SizedBox(height: 10),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(
                value: 0,
                label: Text('暖纸'),
                icon: Icon(Icons.wb_sunny_outlined),
              ),
              ButtonSegment(
                value: 1,
                label: Text('纯白'),
                icon: Icon(Icons.water_outlined),
              ),
            ],
            selected: {s.colorStyle},
            onSelectionChanged: (v) => app.setColorStyle(v.first),
          ),
          const SizedBox(height: 24),
          const _H('数据备份'),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.upload_outlined),
                  label: const Text('导出到剪贴板'),
                  onPressed: _export,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.download_outlined),
                  label: const Text('从剪贴板导入'),
                  onPressed: _import,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Center(
            child: Text(
              '用药记录 v1.1 · 设备号 ${s.deviceId}',
              style: const TextStyle(fontSize: 12, color: Colors.blueGrey),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _export() async {
    final json = await app.exportBackup();
    await Clipboard.setData(ClipboardData(text: json));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已复制 ${json.length} 字符到剪贴板，可粘贴保存到文件')),
      );
    }
  }

  Future<void> _import() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text ?? '';
    if (text.trim().isEmpty || !text.trim().startsWith('{')) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('剪贴板里不是有效的备份 JSON')));
      }
      return;
    }
    try {
      final count = await app.importBackup(text);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('导入成功：$count 条记录（将随下次同步推送）')));
      }
    } on TimeoutException {
      rethrow;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('导入失败：$e')));
      }
    }
  }

  Future<void> _showIps() async {
    final ips = await app.lanServer.localAddresses();
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        title: const Text('本机地址'),
        content: Text(
          app.lanServer.running
              ? '${ips.join('\n')}\n\n端口：${app.settings.lanPort}\n\n在另一台设备的「对端地址」填：http://<上面的IP>:${app.settings.lanPort}'
              : '本机同步服务未开启，请先开启「在本机开启同步服务」并保存。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dlgCtx),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  void _showSql() {
    showDialog(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        title: const Text('Supabase 建表'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: SelectableText(
              'create table medicines (\n'
              '  id text primary key, name text, boxes float8, per_box float8,\n'
              '  remaining float8, doses_per_day float8, amount_per_dose float8,\n'
              '  unit text, low_days int8, note text, times text,\n'
              '  created_at int8, updated_at int8, deleted int8, dirty int8\n'
              ');\n\n'
              'create table dose_logs (\n'
              '  id text primary key, medicine_id text, taken_at int8,\n'
              '  amount float8, note text, updated_at int8,\n'
              '  deleted int8, dirty int8 default 0\n'
              ');\n\n'
              '-- 旧版表升级（已建过表的话执行一次）：\n'
              'alter table medicines add column if not exists remaining float8;\n'
              'alter table medicines add column if not exists times text;\n\n'
              '-- 开启 RLS 并允许 anon 读写（个人自用）：\n'
              'alter table medicines enable row level security;\n'
              'alter table dose_logs enable row level security;\n'
              'create policy mt_rw on medicines for all to anon using (true) with check (true);\n'
              'create policy dl_rw on dose_logs for all to anon using (true) with check (true);',
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dlgCtx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }
}

class _H extends StatelessWidget {
  final String text;
  const _H(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 10),
    child: Text(
      text,
      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
    ),
  );
}
