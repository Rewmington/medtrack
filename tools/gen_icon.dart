// 启动图标生成器：纯 Dart，无三方依赖。
// 用法: dart run tools/gen_icon.dart
// 色值取自 lib/theme.dart 的暖纸主题，保证图标和界面同源。
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

class Col {
  final int r, g, b, a;
  const Col(this.r, this.g, this.b, [this.a = 255]);
  static Col hex(String s) => Col(
      int.parse(s.substring(1, 3), radix: 16),
      int.parse(s.substring(3, 5), radix: 16),
      int.parse(s.substring(5, 7), radix: 16));
}

// lib/theme.dart:50-64 暖纸主题
const paper = Col(246, 241, 232); // F6F1E8
const card = Col(255, 253, 249); // FFFDF9
const ink = Col(43, 37, 28); // 2B251C
const accent = Col(193, 90, 43); // C15A2B
const onAccent = Col(255, 246, 239); // FFF6EF
const err = Col(179, 64, 47); // B3402F
const okc = Col(87, 119, 79); // 57774F

typedef Inside = bool Function(double x, double y);

bool inRoundRect(double x, double y, double cx, double cy, double w, double h,
        double r) =>
    _sdRoundRect(x - cx, y - cy, w / 2, h / 2, r) <= 0;

double _sdRoundRect(double px, double py, double hw, double hh, double r) {
  final qx = px.abs() - hw + r;
  final qy = py.abs() - hh + r;
  final ax = math.max(qx, 0), ay = math.max(qy, 0);
  return math.sqrt(ax * ax + ay * ay) +
      math.max(math.min(qx, qy), 0) -
      r;
}

bool inCircle(double x, double y, double cx, double cy, double r) {
  final dx = x - cx, dy = y - cy;
  return dx * dx + dy * dy <= r * r;
}

/// 胶囊体：轴线 a→b，半径 r
bool inCapsule(
        double x, double y, double ax, double ay, double bx, double by, double r) =>
    _sdSegment(x, y, ax, ay, bx, by) <= r;

double _sdSegment(double x, double y, double ax, double ay, double bx, double by) {
  final vx = bx - ax, vy = by - ay;
  final wx = x - ax, wy = y - ay;
  final len2 = vx * vx + vy * vy;
  var t = len2 == 0 ? 0.0 : (wx * vx + wy * vy) / len2;
  t = t.clamp(0.0, 1.0);
  final dx = wx - vx * t, dy = wy - vy * t;
  return math.sqrt(dx * dx + dy * dy);
}

bool inRect(double x, double y, double x0, double y0, double x1, double y1) =>
    x >= x0 && x <= x1 && y >= y0 && y <= y1;

/// 一层：颜色 + 命中判定，后画的盖在先画的上面
typedef Layer = (Col, Inside);

Uint8List render(int size, List<Layer> layers, {Col? background}) {
  const ss = 4; // 超采样倍数
  final out = Uint8List(size * size * 4);
  final step = 1.0 / (size * ss);
  for (var py = 0; py < size; py++) {
    for (var px = 0; px < size; px++) {
      var ar = 0.0, ag = 0.0, ab = 0.0, aa = 0.0;
      for (var sy = 0; sy < ss; sy++) {
        for (var sx = 0; sx < ss; sx++) {
          final x = (px * ss + sx + 0.5) * step;
          final y = (py * ss + sy + 0.5) * step;
          // 图层按"先画在下"排列，从后往前找第一个命中的即顶层
          var c = background ?? const Col(0, 0, 0, 0);
          for (var i = layers.length - 1; i >= 0; i--) {
            if (layers[i].$2(x, y)) {
              c = layers[i].$1;
              break;
            }
          }
          ar += c.r;
          ag += c.g;
          ab += c.b;
          aa += c.a;
        }
      }
      final n = ss * ss;
      final o = (py * size + px) * 4;
      out[o] = (ar / n).round();
      out[o + 1] = (ag / n).round();
      out[o + 2] = (ab / n).round();
      out[o + 3] = (aa / n).round();
    }
  }
  return out;
}

// ---------- 三个方案 ----------

/// A 方印：赭橙圆角方 + 纸白斜胶囊（中间一道分界）
List<Layer> variantA() {
  final tile = (double x, double y) => inRoundRect(x, y, .5, .5, 1, 1, .225);
  final pill = (double x, double y) =>
      inCapsule(x, y, .335, .665, .665, .335, .105);
  final seam = (double x, double y) =>
      pill(x, y) && ((x - .5) + (y - .5)).abs() < .017;
  return [
    (accent, tile),
    (onAccent, pill),
    (accent, seam),
  ];
}

/// B 处方笺：暖纸底 + 砖红细边 + 赭橙胶囊 + 两行墨线
List<Layer> variantB() {
  final tile = (double x, double y) => inRoundRect(x, y, .5, .5, 1, 1, .225);
  final edge = (double x, double y) =>
      tile(x, y) && !inRoundRect(x, y, .5, .5, 1 - .07, 1 - .07, .185);
  final pill = (double x, double y) =>
      inCapsule(x, y, .315, .42, .685, .42, .10);
  final seam = (double x, double y) => pill(x, y) && (x - .5).abs() < .014;
  final l1 = (double x, double y) => inRect(x, y, .30, .625, .70, .660);
  final l2 = (double x, double y) => inRect(x, y, .30, .705, .56, .740);
  return [
    (paper, tile),
    (err, edge),
    (accent, pill),
    (onAccent, seam),
    (ink, l1),
    (ink, l2),
  ];
}

/// 双色胶囊：轴线 45°，整体离中心最远点控制在 R（0..1 归一化画布）
List<Layer> capsuleLayers(double R) {
  // 端点距中心 sqrt(2)*d，再加半径 r；r/d 沿用初版观感
  const ratio = 0.657;
  final d = R / (math.sqrt2 + ratio);
  final r = d * ratio;
  final pill = (double x, double y) =>
      inCapsule(x, y, .5 - d, .5 + d, .5 + d, .5 - d, r);
  final warm = (double x, double y) => pill(x, y) && (y - x) > 0;
  return [(onAccent, pill), (accent, warm)];
}

/// C 夜印：深墨底 + 双色胶囊（赭橙／纸白）—— 最终选定方案
List<Layer> variantC() => [
      (ink, (x, y) => inRoundRect(x, y, .5, .5, 1, 1, .225)),
      ...capsuleLayers(.362),
    ];

/// D 暖印：赭橙底 + 纸白/墨黑双色胶囊（浅深两种桌面上都不糊）
List<Layer> variantD() {
  final tile = (double x, double y) => inRoundRect(x, y, .5, .5, 1, 1, .225);
  final pill = (double x, double y) =>
      inCapsule(x, y, .325, .675, .675, .325, .115);
  final dark = (double x, double y) => pill(x, y) && (y - x) > 0;
  return [
    (accent, tile),
    (onAccent, pill),
    (ink, dark),
  ];
}

// ---------- PNG 编码 ----------

final _crcTable = () {
  final t = Uint32List(256);
  for (var n = 0; n < 256; n++) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1);
    }
    t[n] = c & 0xFFFFFFFF;
  }
  return t;
}();

int _crc32(List<int> data) {
  var c = 0xFFFFFFFF;
  for (final b in data) {
    c = _crcTable[(c ^ b) & 0xFF] ^ (c >> 8);
    c &= 0xFFFFFFFF;
  }
  return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

List<int> _chunk(String type, List<int> data) {
  final out = BytesBuilder();
  final len = ByteData(4)..setUint32(0, data.length);
  out.add(len.buffer.asUint8List());
  final body = Uint8List.fromList([...type.codeUnits, ...data]);
  out.add(body);
  final cr = ByteData(4)..setUint32(0, _crc32(body));
  out.add(cr.buffer.asUint8List());
  return out.toBytes();
}

Uint8List encodePng(int w, int h, Uint8List rgba) {
  final raw = Uint8List(h * (1 + w * 4));
  for (var y = 0; y < h; y++) {
    raw[y * (1 + w * 4)] = 0;
    raw.setRange(y * (1 + w * 4) + 1, y * (1 + w * 4) + 1 + w * 4,
        rgba, y * w * 4);
  }
  final idat = ZLibCodec(level: 9).encode(raw);
  final ihdr = ByteData(13)
    ..setUint32(0, w)
    ..setUint32(4, h)
    ..setUint8(8, 8)
    ..setUint8(9, 6)
    ..setUint8(10, 0)
    ..setUint8(11, 0)
    ..setUint8(12, 0);
  final out = BytesBuilder()
    ..add([137, 80, 78, 71, 13, 10, 26, 10])
    ..add(_chunk('IHDR', ihdr.buffer.asUint8List()))
    ..add(_chunk('IDAT', idat))
    ..add(_chunk('IEND', const []));
  return out.toBytes();
}

/// 把若干 RGBA 图按最近邻放大后横向拼成一张检查条
Uint8List strip(List<({Uint8List px, int size})> items, int scale, int w, int h) {
  final bg = Col(128, 128, 128);
  final out = Uint8List(w * h * 4);
  for (var i = 0; i < w * h; i++) {
    out[i * 4] = bg.r;
    out[i * 4 + 1] = bg.g;
    out[i * 4 + 2] = bg.b;
    out[i * 4 + 3] = 255;
  }
  var x = 0;
  for (final it in items) {
    final big = it.size * scale;
    final yOff = (h - big) ~/ 2;
    for (var y = 0; y < big; y++) {
      for (var px = 0; px < big; px++) {
        final sy = y ~/ scale, sx = px ~/ scale;
        final o = ((y + yOff) * w + px + x) * 4;
        final s = (sy * it.size + sx) * 4;
        out[o] = it.px[s];
        out[o + 1] = it.px[s + 1];
        out[o + 2] = it.px[s + 2];
        out[o + 3] = it.px[s + 3];
      }
    }
    x += big + 24;
  }
  return out;
}

/// ICO 容器：每个尺寸以 PNG 内嵌（Vista 之后的 Windows 全版本支持）。
/// ICONDIR / ICONDIRENTRY 一律小端，和 PNG 的大端相反。
Uint8List encodeIco(List<({int size, Uint8List png})> imgs) {
  const le = Endian.little;
  final head = ByteData(6)
    ..setUint16(0, 0, le)
    ..setUint16(2, 1, le)
    ..setUint16(4, imgs.length, le);
  final dir = ByteData(16 * imgs.length);
  final body = BytesBuilder();
  var offset = 6 + 16 * imgs.length;
  for (var i = 0; i < imgs.length; i++) {
    final im = imgs[i];
    final o = i * 16;
    dir.setUint8(o, im.size >= 256 ? 0 : im.size); // 256 用 0 表示
    dir.setUint8(o + 1, im.size >= 256 ? 0 : im.size);
    dir.setUint8(o + 2, 0); // 调色板色数
    dir.setUint8(o + 3, 0); // 保留
    dir.setUint16(o + 4, 1, le); // 颜色平面
    dir.setUint16(o + 6, 32, le); // 位深
    dir.setUint32(o + 8, im.png.length, le);
    dir.setUint32(o + 12, offset, le);
    body.add(im.png);
    offset += im.png.length;
  }
  return Uint8List.fromList(
      [...head.buffer.asUint8List(), ...dir.buffer.asUint8List(), ...body.toBytes()]);
}

Future<void> install() async {
  const res = 'android/app/src/main/res';
  // 旧版启动器用的方形图标：整块深墨底 + 胶囊
  const legacy = {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192};
  // 自适应图标画布 108dp，可安全显示的是中间 66dp 圆，所以前景要缩
  const fg = {'mdpi': 108, 'hdpi': 162, 'xhdpi': 216, 'xxhdpi': 324, 'xxxhdpi': 432};
  final foreground = capsuleLayers(.30);

  for (final e in legacy.entries) {
    final px = render(e.value, variantC());
    await File('$res/mipmap-${e.key}/ic_launcher.png')
        .writeAsBytes(encodePng(e.value, e.value, px));
  }
  for (final e in fg.entries) {
    final px = render(e.value, foreground);
    await File('$res/mipmap-${e.key}/ic_launcher_foreground.png')
        .writeAsBytes(encodePng(e.value, e.value, px));
  }

  await Directory('$res/mipmap-anydpi-v26').create(recursive: true);
  const adaptive = '''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
</adaptive-icon>
''';
  await File('$res/mipmap-anydpi-v26/ic_launcher.xml')
      .writeAsString(adaptive);

  await Directory('$res/values').create(recursive: true);
  await File('$res/values/ic_launcher_background.xml').writeAsString(
      '''<?xml version="1.0" encoding="utf-8"?>
<resources>
    <!-- lib/theme.dart 暖纸主题 tx -->
    <color name="ic_launcher_background">#FF2B251C</color>
</resources>
''');

  final icoSizes = <({int size, Uint8List png})>[];
  for (final s in const [256, 48, 32, 16]) {
    icoSizes.add((size: s, png: encodePng(s, s, render(s, variantC()))));
  }
  await File('windows/runner/resources/app_icon.ico')
      .writeAsBytes(encodeIco(icoSizes));

  stdout.writeln('已写入 android/ 与 windows/ 图标');
}

Future<void> main(List<String> args) async {
  if (args.contains('--install')) return install();
  final dir = Directory('tools/icon_out');
  await dir.create(recursive: true);
  final variants = {
    'A': variantA(),
    'B': variantB(),
    'C': variantC(),
    'D': variantD(),
  };
  // 每个方案一行，行内 48 / 32 / 16 原生渲染后放大 4 倍，看小尺寸是否还认得出
  const scale = 4;
  const sizes = [48, 32, 16];
  final rows = <List<({Uint8List px, int size})>>[];
  for (final e in variants.entries) {
    final master = render(512, e.value);
    await File('tools/icon_out/${e.key}.png')
        .writeAsBytes(encodePng(512, 512, master));
    stdout.writeln('${e.key} ok');
    rows.add([for (final s in sizes) (px: render(s, e.value), size: s)]);
  }
  final w = sizes.fold(0, (a, b) => a + b * scale) + 24 * (sizes.length - 1) + 16;
  final h = (sizes.first * scale + 8) * rows.length;
  final grid = Uint8List(w * h * 4);
  for (var i = 0; i < w * h; i++) {
    grid[i * 4] = 128;
    grid[i * 4 + 3] = 255;
    grid[i * 4 + 1] = 128;
    grid[i * 4 + 2] = 128;
  }
  for (var r = 0; r < rows.length; r++) {
    final part = strip(rows[r], scale, w, sizes.first * scale + 8);
    final top = r * (sizes.first * scale + 8);
    for (var y = 0; y < sizes.first * scale + 8; y++) {
      grid.setRange((top + y) * w * 4, (top + y) * w * 4 + w * 4,
          part, y * w * 4);
    }
  }
  await File('tools/icon_out/small.png')
      .writeAsBytes(encodePng(w, h, grid));
  stdout.writeln('-> tools/icon_out/');
}
