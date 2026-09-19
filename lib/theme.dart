import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 全局设计令牌（G 暖纸 / C 纯白 × 浅色 / 深色 四套）。
class AppTokens extends ThemeExtension<AppTokens> {
  final Brightness brightness;
  final Color bg;
  final Color card;
  final Color line;
  final Color tx;
  final Color tx2;
  final Color accent;
  final Color onAccent;
  final Color accentSoft;
  final Color ok;
  final Color okSoft;
  final Color warn;
  final Color warnSoft;
  final Color err;
  final Color errSoft;
  final Color track;

  const AppTokens({
    required this.brightness,
    required this.bg,
    required this.card,
    required this.line,
    required this.tx,
    required this.tx2,
    required this.accent,
    required this.onAccent,
    required this.accentSoft,
    required this.ok,
    required this.okSoft,
    required this.warn,
    required this.warnSoft,
    required this.err,
    required this.errSoft,
    required this.track,
  });

  bool get isDark => brightness == Brightness.dark;

  /// 标题与大数字用的衬线字体；缺字体时回退系统 serif。
  static const serif = 'NotoSerifSC';

  static const warmLight = AppTokens(
    brightness: Brightness.light,
    bg: Color(0xFFF6F1E8),
    card: Color(0xFFFFFDF9),
    line: Color(0xFFE7DECD),
    tx: Color(0xFF2B251C),
    tx2: Color(0xFF948973),
    accent: Color(0xFFC15A2B),
    onAccent: Color(0xFFFFF6EF),
    accentSoft: Color(0xFFF6E3D7),
    ok: Color(0xFF57774F),
    okSoft: Color(0xFFE7EEDF),
    warn: Color(0xFFB98A1F),
    warnSoft: Color(0xFFF6EBD2),
    err: Color(0xFFB3402F),
    errSoft: Color(0xFFF3E0DC),
    track: Color(0xFFEAE2D2),
  );

  static const warmDark = AppTokens(
    brightness: Brightness.dark,
    bg: Color(0xFF17140F),
    card: Color(0xFF221E17),
    line: Color(0xFF3A342A),
    tx: Color(0xFFEFE8DA),
    tx2: Color(0xFFA2967F),
    accent: Color(0xFFD97A4E),
    onAccent: Color(0xFF17140F),
    accentSoft: Color(0xFF3A2A20),
    ok: Color(0xFF8FB582),
    okSoft: Color(0xFF26301F),
    warn: Color(0xFFD9AE55),
    warnSoft: Color(0xFF332A15),
    err: Color(0xFFE0837B),
    errSoft: Color(0xFF3A2422),
    track: Color(0xFF332D23),
  );

  static const pureLight = AppTokens(
    brightness: Brightness.light,
    bg: Color(0xFFFFFFFF),
    card: Color(0xFFF7F6F3),
    line: Color(0xFFECEAE5),
    tx: Color(0xFF161513),
    tx2: Color(0xFF8B8780),
    accent: Color(0xFF161513),
    onAccent: Color(0xFFFFFFFF),
    accentSoft: Color(0xFFEFEDE7),
    ok: Color(0xFF3E7C59),
    okSoft: Color(0xFFE8F0EA),
    warn: Color(0xFFB4691E),
    warnSoft: Color(0xFFF5EBDD),
    err: Color(0xFFB3402F),
    errSoft: Color(0xFFF3E0DC),
    track: Color(0xFFE6E3DC),
  );

  static const pureDark = AppTokens(
    brightness: Brightness.dark,
    bg: Color(0xFF0B0B0C),
    card: Color(0xFF191919),
    line: Color(0xFF2C2C2E),
    tx: Color(0xFFF2F1EE),
    tx2: Color(0xFF98958F),
    accent: Color(0xFFF2F1EE),
    onAccent: Color(0xFF161513),
    accentSoft: Color(0xFF2A2A2B),
    ok: Color(0xFF7FB894),
    okSoft: Color(0xFF1E2A22),
    warn: Color(0xFFD9A05B),
    warnSoft: Color(0xFF2E2517),
    err: Color(0xFFE0837B),
    errSoft: Color(0xFF33211F),
    track: Color(0xFF2C2C2E),
  );

  static AppTokens of(BuildContext context) =>
      Theme.of(context).extension<AppTokens>()!;

  static AppTokens pick(int colorStyle, Brightness brightness) =>
      switch ((colorStyle, brightness)) {
        (0, Brightness.light) => warmLight,
        (0, Brightness.dark) => warmDark,
        (1, Brightness.dark) => pureDark,
        (_, _) => pureLight,
      };

  @override
  ThemeExtension<AppTokens> copyWith() => this;

  @override
  ThemeExtension<AppTokens> lerp(ThemeExtension<AppTokens>? other, double t) =>
      this;
}

ThemeData buildAppTheme(AppTokens t) {
  final scheme = ColorScheme(
    brightness: t.brightness,
    primary: t.accent,
    onPrimary: t.onAccent,
    primaryContainer: t.accentSoft,
    onPrimaryContainer: t.isDark ? t.tx : t.accent,
    secondary: t.ok,
    onSecondary: t.isDark ? t.bg : Colors.white,
    secondaryContainer: t.okSoft,
    onSecondaryContainer: t.ok,
    error: t.err,
    onError: Colors.white,
    errorContainer: t.errSoft,
    onErrorContainer: t.err,
    surface: t.bg,
    onSurface: t.tx,
    surfaceContainerLowest: t.card,
    surfaceContainerLow: t.card,
    surfaceContainer: t.card,
    surfaceContainerHigh: t.accentSoft,
    surfaceContainerHighest: t.line,
    onSurfaceVariant: t.tx2,
    outline: t.line,
    outlineVariant: t.line,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: t.bg,
    extensions: [t],
    textTheme: Typography
        .blackCupertino // 占位，下面 apply 覆盖颜色
        .apply(bodyColor: t.tx, displayColor: t.tx),
    cardTheme: CardThemeData(
      elevation: 0,
      color: t.card,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: t.line),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: t.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: t.line),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: t.card,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: t.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: t.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: t.accent, width: 1.6),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: t.line),
        foregroundColor: t.tx,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        side: WidgetStatePropertyAll(BorderSide(color: t.line)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: t.card,
      side: BorderSide(color: t.line),
      labelStyle: TextStyle(color: t.tx, fontSize: 13),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: t.isDark ? t.card : const Color(0xFF2B251C),
      contentTextStyle: const TextStyle(color: Color(0xFFF6F1E8)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: t.tx,
        fontSize: 20,
        fontWeight: FontWeight.w700,
        fontFamily: AppTokens.serif,
      ),
      iconTheme: IconThemeData(color: t.tx),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: t.card,
      indicatorColor: t.accentSoft,
      height: 64,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected) ? t.accent : t.tx2,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 12,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w400,
          color: states.contains(WidgetState.selected) ? t.accent : t.tx2,
        ),
      ),
    ),
  );
}

/// 页面顶部：小字日期 + 衬线大标题 + 右侧动作按钮。
class PageHeader extends StatelessWidget {
  final String sub;
  final String title;
  final List<Widget> actions;
  const PageHeader({
    super.key,
    required this.sub,
    required this.title,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 12, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sub,
                  style: TextStyle(
                    fontSize: 12,
                    letterSpacing: 2,
                    color: t.tx2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    fontFamily: AppTokens.serif,
                    color: t.tx,
                  ),
                ),
              ],
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

/// 三色活动圆环：今日服药 / 本周依从 / 连续打卡。
class ActivityRings extends StatelessWidget {
  final double today; // 0~1
  final double week;
  final double streak; // 0~1（相对 7 天）
  const ActivityRings({
    super.key,
    required this.today,
    required this.week,
    required this.streak,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return CustomPaint(
      size: const Size(120, 120),
      painter: _RingsPainter(
        today: today,
        week: week,
        streak: streak,
        track: t.track,
        colors: [t.accent, t.ok, t.warn],
      ),
    );
  }
}

class _RingsPainter extends CustomPainter {
  final double today, week, streak;
  final Color track;
  final List<Color> colors;
  _RingsPainter({
    required this.today,
    required this.week,
    required this.streak,
    required this.track,
    required this.colors,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final stroke = size.width * 0.086;
    final values = [
      today.clamp(0.0, 1.0),
      week.clamp(0.0, 1.0),
      streak.clamp(0.0, 1.0),
    ];
    for (var i = 0; i < 3; i++) {
      final radius = size.width / 2 - stroke / 2 - i * stroke * 1.36;
      final rect = Rect.fromCircle(center: c, radius: radius);
      final bg = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = track;
      canvas.drawCircle(c, radius, bg);
      final v = values[i];
      if (v > 0) {
        final fg = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round
          ..color = colors[i];
        canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * v, false, fg);
      }
    }
  }

  @override
  bool shouldRepaint(_RingsPainter old) =>
      old.today != today ||
      old.week != week ||
      old.streak != streak ||
      old.track != track ||
      old.colors != colors;
}
