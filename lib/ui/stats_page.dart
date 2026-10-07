import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../app.dart';
import '../models.dart';
import '../theme.dart';

class StatsPage extends StatelessWidget {
  const StatsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final t = AppTokens.of(context);
    final stats = app.weekStats;
    final adherence = stats.daily;
    final weekAvg = stats.rate;
    final byId = {for (final m in app.medicines) m.id: m};
    final sorted = [...app.medicines]
      ..sort((a, b) {
        final da = a.daysLeft ?? 9999, db = b.daysLeft ?? 9999;
        return da.compareTo(db);
      });
    final weekStart = DateTime.now().subtract(Duration(days: 6));
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 28),
          children: [
            PageHeader(
              sub:
                  '${DateFormat('M月d日').format(weekStart)} — ${DateFormat('M月d日').format(DateTime.now())}',
              title: '统计',
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '${(weekAvg * 100).round()}%',
                            style: TextStyle(
                              fontFamily: AppTokens.serif,
                              fontSize: 40,
                              fontWeight: FontWeight.w700,
                              height: 1,
                              color: t.tx,
                            ),
                          ),
                          const Spacer(),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              '本周依从率',
                              style: TextStyle(fontSize: 12.5, color: t.tx2),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      SizedBox(
                        height: 120,
                        child: _AdherenceChart(values: adherence),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          _Legend(color: t.accentSoft, label: '依从率'),
                          const SizedBox(width: 14),
                          _Legend(color: t.accent, label: '今天（进行中）'),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              stats.headline,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                                fontFamily: AppTokens.serif,
                                color: stats.perfect ? t.ok : t.tx,
                              ),
                            ),
                          ),
                          if (stats.perfect)
                            _PerfectSeal(color: t.ok)
                          else if (stats.hasPlan && stats.rate >= 0.8)
                            Icon(
                              Icons.verified_outlined,
                              size: 22,
                              color: t.ok,
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        stats.detail,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: t.tx2,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          _Count(
                            label: '应服',
                            value: '${stats.owed}',
                            color: t.tx,
                          ),
                          _Count(
                            label: '实服',
                            value: '${stats.taken}',
                            color: t.ok,
                          ),
                          _Count(
                            label: '没吃',
                            value: '${stats.skipped}',
                            color: t.tx2,
                          ),
                          _Count(
                            label: '漏了',
                            value: '${stats.missed}',
                            color: stats.missed > 0 ? t.err : t.tx2,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const _Section('库存余量'),
            if (sorted.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  '暂无药品',
                  style: TextStyle(color: t.tx2, fontSize: 13),
                ),
              ),
            ...sorted.map((m) => _StockRow(medicine: m)),
            const _Section('最近打卡'),
            ...app.weekLogs.take(30).map((log) {
              final m = byId[log.medicineId];
              return Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 12, 2),
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: log.isSkipped ? t.track : t.okSoft,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      log.isSkipped ? Icons.remove : Icons.check,
                      size: 16,
                      color: log.isSkipped ? t.tx2 : t.ok,
                    ),
                  ),
                  title: Text(
                    log.isSkipped
                        ? '${m?.name ?? "（已删除）"} · 没吃'
                        : '${m?.name ?? "（已删除）"} · ${_fmt(log.amount)} ${m?.unit ?? ''}',
                    style: const TextStyle(fontSize: 14),
                  ),
                  subtitle: Text(
                    DateFormat('M月d日 HH:mm').format(log.takenDateTime),
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.undo_outlined, size: 20),
                    tooltip: log.isSkipped ? '撤销这个「没吃」标记' : '撤销（回补库存）',
                    onPressed: () => app.undoLog(log),
                  ),
                ),
              );
            }),
            if (app.weekLogs.isEmpty && app.medicines.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text('本周还没有打卡记录', style: TextStyle(color: t.tx2)),
              ),
          ],
        ),
      ),
    );
  }

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();
}

/// 满勤印章：宋体字 + 双线框，略微歪斜，像盖在纸上。
class _PerfectSeal extends StatelessWidget {
  final Color color;
  const _PerfectSeal({required this.color});

  @override
  Widget build(BuildContext context) => Transform.rotate(
    angle: -0.12,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.75), width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(2.5),
        child: Text(
          '满勤',
          style: TextStyle(
            fontFamily: AppTokens.serif,
            fontWeight: FontWeight.w900,
            fontSize: 17,
            letterSpacing: 2,
            color: color,
          ),
        ),
      ),
    ),
  );
}

class _Count extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _Count({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontFamily: AppTokens.serif,
              fontWeight: FontWeight.w700,
              fontSize: 20,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 11.5, color: t.tx2)),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  const _Section(this.title);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 22, 20, 8),
    child: Text(
      title,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        letterSpacing: 1,
        color: AppTokens.of(context).tx2,
      ),
    ),
  );
}

class _Legend extends StatelessWidget {
  final Color color;
  final String label;
  const _Legend({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 11.5, color: t.tx2)),
      ],
    );
  }
}

class _AdherenceChart extends StatelessWidget {
  final List<double> values;
  const _AdherenceChart({required this.values});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return CustomPaint(
      size: Size.infinite,
      painter: _BarsPainter(
        values: values,
        color: t.accent,
        softColor: t.isDark
            ? t.accent.withValues(alpha: 0.35)
            : t.accentSoft.withValues(alpha: 0.8),
        labelColor: t.tx2,
      ),
    );
  }
}

class _BarsPainter extends CustomPainter {
  final List<double> values;
  final Color color;
  final Color softColor;
  final Color labelColor;
  _BarsPainter({
    required this.values,
    required this.color,
    required this.softColor,
    required this.labelColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const gap = 12.0;
    final barW = (size.width - gap * (values.length - 1)) / values.length;
    for (var i = 0; i < values.length; i++) {
      final v = values[i];
      final today = i == values.length - 1;
      final x = i * (barW + gap);
      final h = (size.height - 24) * (v <= 0 ? 0.03 : v);
      final rect = Rect.fromLTWH(x, size.height - 24 - h, barW, h);
      final paint = Paint()..color = today ? color : softColor;
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(5)),
        paint,
      );
      final label = TextPainter(
        text: TextSpan(
          text: _dayLabel(i),
          style: TextStyle(
            fontSize: 10,
            color: labelColor,
            fontWeight: today ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      label.paint(
        canvas,
        Offset(x + barW / 2 - label.width / 2, size.height - 16),
      );
    }
  }

  String _dayLabel(int i) {
    final day = DateTime.now().subtract(Duration(days: 6 - i));
    return i == values.length - 1 ? '今天' : '${day.day}';
  }

  @override
  bool shouldRepaint(_BarsPainter old) =>
      old.values != values || old.color != color || old.softColor != softColor;
}

class _StockRow extends StatelessWidget {
  final Medicine medicine;
  const _StockRow({required this.medicine});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final m = medicine;
    final days = m.daysLeft;
    final barColor = m.isOut
        ? t.err
        : m.isLow
        ? t.warn
        : t.accent;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      m.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                      ),
                    ),
                  ),
                  Text(
                    days == null ? '未设置用量' : '${days.ceil()} 天',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: m.daysLeft == null ? t.tx2 : barColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: m.isOut ? 0.02 : m.stockRatio,
                  minHeight: 5,
                  color: barColor,
                  backgroundColor: t.track,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
