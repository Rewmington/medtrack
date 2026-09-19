import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../app.dart';
import '../models.dart';
import '../theme.dart';
import 'home_page.dart' show confirmUndoCheckIn;

/// 今天：三色圆环总览 + 「现在该吃的 / 已完成 / 稍后」分段打卡清单。
class TodayPage extends StatelessWidget {
  const TodayPage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final t = AppTokens.of(context);
    final now = app.now;
    final nowMin = now.hour * 60 + now.minute;
    final plans = app.todayPlan;
    final due = plans.where((p) => !p.taken && p.minute <= nowMin).toList();
    final done = plans.where((p) => p.taken).toList();
    final later = plans.where((p) => !p.taken && p.minute > nowMin).toList();
    final week = app.weeklyAdherence;
    final weekAvg = week.isEmpty ? 0.0 : week.reduce((a, b) => a + b) / 7;
    final next = plans.where((p) => !p.taken).firstOrNull;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 28),
          children: [
            PageHeader(
              sub: DateFormat('M月d日 · EEEE', 'zh_CN').format(now),
              title: '今天',
              actions: [
                if (app.busy)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else
                  IconButton(
                    tooltip: '立即同步',
                    icon: const Icon(Icons.sync),
                    onPressed: () => app.syncNow(context),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Row(
                    children: [
                      ActivityRings(
                        today: app.todayProgress,
                        week: weekAvg,
                        streak: (app.streakDays / 7).clamp(0.0, 1.0),
                      ),
                      const SizedBox(width: 18),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _RingLegend(
                              color: t.accent,
                              label: '今日服药',
                              value: '${done.length} / ${plans.length}',
                            ),
                            _RingLegend(
                              color: t.ok,
                              label: '本周依从',
                              value: '${(weekAvg * 100).round()}%',
                            ),
                            _RingLegend(
                              color: t.warn,
                              label: '连续打卡',
                              value: '${app.streakDays} 天',
                            ),
                            if (next != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  '下一次 ${formatMinutes(next.minute)} · ${next.medicine.name}',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: t.accent,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (plans.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(22),
                    child: Column(
                      children: [
                        Icon(
                          Icons.medication_liquid_outlined,
                          size: 40,
                          color: t.tx2,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          '还没有药品',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            color: t.tx,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '到「药品」页添加后，这里会按时间点安排每日打卡',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12.5, color: t.tx2),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            _Section(title: '现在该吃的'),
            ...due.map((p) => _DueRow(plan: p)),
            if (due.isEmpty && plans.isNotEmpty)
              _EmptyRow(text: done.isNotEmpty ? '本时段都完成啦' : '还没有到时间的药'),
            if (done.isNotEmpty) ...[
              _Section(title: '已完成'),
              ...done.map((p) => _DoneRow(plan: p)),
            ],
            if (later.isNotEmpty) ...[
              _Section(title: '稍后'),
              ...later.map((p) => _LaterRow(plan: p)),
            ],
          ],
        ),
      ),
    );
  }
}

class _RingLegend extends StatelessWidget {
  final Color color;
  final String label;
  final String value;
  const _RingLegend({
    required this.color,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.5),
      child: Row(
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          Text(label, style: TextStyle(fontSize: 12.5, color: t.tx2)),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              fontFamily: AppTokens.serif,
              color: t.tx,
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  const _Section({required this.title});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          letterSpacing: 1,
          color: t.tx2,
        ),
      ),
    );
  }
}

class _EmptyRow extends StatelessWidget {
  final String text;
  const _EmptyRow({required this.text});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      child: Text(text, style: TextStyle(fontSize: 12.5, color: t.tx2)),
    );
  }
}

/// 清单行：左侧圆形勾选按钮 + 名称/说明 + 右侧动作。
class _TodoRow extends StatelessWidget {
  final Widget circle;
  final String name;
  final String info;
  final Color? infoColor;
  final Widget trailing;
  final double opacity;
  final VoidCallback? onTap;
  const _TodoRow({
    required this.circle,
    required this.name,
    required this.info,
    this.infoColor,
    required this.trailing,
    this.opacity = 1,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      child: Card(
        child: Opacity(
          opacity: opacity,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(15, 13, 15, 13),
              child: Row(
                children: [
                  circle,
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          info,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: infoColor ?? t.tx2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  trailing,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CheckCircle extends StatelessWidget {
  final bool filled;
  final bool ghost;
  const _CheckCircle({this.filled = false, this.ghost = false});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    if (filled) {
      return Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(color: t.ok, shape: BoxShape.circle),
        child: const Icon(Icons.check, size: 18, color: Colors.white),
      );
    }
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: ghost ? t.line : t.accent, width: 2.5),
      ),
    );
  }
}

/// 已到时间未打卡。
class _DueRow extends StatelessWidget {
  final DayPlan plan;
  const _DueRow({required this.plan});

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppController>();
    final t = AppTokens.of(context);
    final m = plan.medicine;
    final out = m.isOut;
    final info = plan.overdue
        ? '${formatMinutes(plan.minute)} · 超时 ${_overdueMin(plan.minute)} 分钟${out ? ' · 库存已用完' : ''}'
        : '${formatMinutes(plan.minute)}${m.note.isEmpty ? '' : ' · ${m.note}'} · 已到时间';
    return _TodoRow(
      circle: _CheckCircle(ghost: out),
      name: '${m.name} · ${_fmt(m.amountPerDose)} ${m.unit}',
      info: info,
      infoColor: plan.overdue ? t.accent : null,
      trailing: GestureDetector(
        onTap: () => app.checkIn(m),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            color: out ? Colors.transparent : t.accent,
            borderRadius: BorderRadius.circular(99),
            border: out ? Border.all(color: t.accent, width: 1.5) : null,
          ),
          child: Text(
            '打卡',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: out ? t.accent : t.onAccent,
            ),
          ),
        ),
      ),
    );
  }

  static int _overdueMin(int minute) {
    final now = DateTime.now();
    return now.hour * 60 + now.minute - minute;
  }
}

/// 已完成：点按行可撤销。
class _DoneRow extends StatelessWidget {
  final DayPlan plan;
  const _DoneRow({required this.plan});

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppController>();
    final t = AppTokens.of(context);
    final m = plan.medicine;
    final log = app.latestTodayLog(m.id);
    final time = log == null
        ? ''
        : DateFormat('HH:mm').format(log.takenDateTime);
    final info = [
      if (time.isNotEmpty) '$time 打卡',
      if (m.note.isNotEmpty) m.note,
    ].join(' · ');
    return _TodoRow(
      circle: const _CheckCircle(filled: true),
      name: '${m.name} · ${_fmt(m.amountPerDose)} ${m.unit}',
      info: info.isEmpty ? '已完成' : info,
      opacity: 0.62,
      onTap: () => confirmUndoCheckIn(context, app, m),
      trailing: Text(
        '点按撤销',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: t.ok,
        ),
      ),
    );
  }
}

/// 未到时间。
class _LaterRow extends StatelessWidget {
  final DayPlan plan;
  const _LaterRow({required this.plan});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final m = plan.medicine;
    return _TodoRow(
      circle: const _CheckCircle(ghost: true),
      name: '${m.name} · ${_fmt(m.amountPerDose)} ${m.unit}',
      info: m.note.isEmpty ? '还没到时间' : m.note,
      opacity: 0.5,
      trailing: Text(
        formatMinutes(plan.minute),
        style: TextStyle(fontSize: 12, color: t.tx2),
      ),
    );
  }
}

String _fmt(double v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
