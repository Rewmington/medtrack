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
    final adherence = app.weeklyAdherence;
    final weekTotal = adherence.fold<double>(0, (s, v) => s + v);
    final weekAvg = weekTotal / 7;
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
                      color: t.okSoft,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.check, size: 16, color: t.ok),
                  ),
                  title: Text(
                    '${m?.name ?? "（已删除）"} · ${_fmt(log.amount)} ${m?.unit ?? ''}',
                    style: const TextStyle(fontSize: 14),
                  ),
                  subtitle: Text(
                    DateFormat('M月d日 HH:mm').format(log.takenDateTime),
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.undo_outlined, size: 20),
                    tooltip: '撤销（回补库存）',
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
