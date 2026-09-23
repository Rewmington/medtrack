import 'package:shared_preferences/shared_preferences.dart';

enum SyncChannel { off, lan, supabase }

class Settings {
  static const _k = 'mt_';

  late final SharedPreferences _prefs;

  SyncChannel syncChannel = SyncChannel.off;
  bool lanHost = true; // Windows 端是否对外提供同步服务
  int lanPort = 8765;
  String lanPeerUrl = ''; // 如 http://192.168.1.5:8765
  String lanKey = ''; // 可选预共享密钥
  String supabaseUrl = '';
  String supabaseAnonKey = '';
  bool lowStockReminders = true; // 开屏低药量检测提示
  int themeMode = 0; // 0=跟随系统 1=浅色 2=深色
  int colorStyle = 0; // 0=暖纸 1=纯白
  String deviceId = '';

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    syncChannel = SyncChannel
        .values[_prefs.getInt('${_k}channel') ?? SyncChannel.off.index];
    lanHost = _prefs.getBool('${_k}lanHost') ?? true;
    lanPort = _prefs.getInt('${_k}lanPort') ?? 8765;
    lanPeerUrl = _prefs.getString('${_k}lanPeer') ?? '';
    lanKey = _prefs.getString('${_k}lanKey') ?? '';
    supabaseUrl = _prefs.getString('${_k}sbUrl') ?? '';
    supabaseAnonKey = _prefs.getString('${_k}sbKey') ?? '';
    lowStockReminders = _prefs.getBool('${_k}remindLow') ?? true;
    themeMode = _prefs.getInt('${_k}theme') ?? 0;
    colorStyle = _prefs.getInt('${_k}color') ?? 0;
    deviceId = _prefs.getString('${_k}device') ?? '';
    if (deviceId.isEmpty) {
      deviceId = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
      await _prefs.setString('${_k}device', deviceId);
    }
  }

  int cursor(String channel) => _prefs.getInt('${_k}cur_$channel') ?? 0;
  Future<void> setCursor(String channel, int v) =>
      _prefs.setInt('${_k}cur_$channel', v);

  Future<void> save() async {
    await _prefs.setInt('${_k}channel', syncChannel.index);
    await _prefs.setBool('${_k}lanHost', lanHost);
    await _prefs.setInt('${_k}lanPort', lanPort);
    await _prefs.setString('${_k}lanPeer', lanPeerUrl.trim());
    await _prefs.setString('${_k}lanKey', lanKey.trim());
    await _prefs.setString('${_k}sbUrl', supabaseUrl.trim());
    await _prefs.setString('${_k}sbKey', supabaseAnonKey.trim());
    await _prefs.setBool('${_k}remindLow', lowStockReminders);
    await _prefs.setInt('${_k}theme', themeMode);
    await _prefs.setInt('${_k}color', colorStyle);
  }
}
