import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../app.dart';
import '../models.dart';
import '../theme.dart';

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
    final active = plans.where((p) => !p.skipped).toList();
    final due = active.where((p) => !p.taken && p.minute <= nowMin).toList();
    final done = active.where((p) => p.taken).toList();
    final later = active.where((p) => !p.taken && p.minute > nowMin).toList();
    final skipped = plans.where((p) => p.skipped).toList();
    final weekAvg = app.weekStats.rate;
    final next = active.where((p) => !p.taken).firstOrNull;
    final missed = app.missedSlots;

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
                              value: '${done.length} / ${active.length}',
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
            if (app.settings.missedReminders && missed.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                child: _MissedCard(slots: missed),
              ),
            _Section(title: '现在该吃的'),
            ...due.map((p) => _DueRow(plan: p)),
            if (due.isEmpty && plans.isNotEmpty)
              _EmptyRow(text: done.isNotEmpty ? '本时段都完成啦' : '还没有到时间的药'),
            if (done.isNotEmpty) ...[
              _Section(title: '已完成'),
              ...done.map((p) => _DoneRow(plan: p)),
            ],
            if (skipped.isNotEmpty) ...[
              _Section(title: '标记为没吃'),
              ...skipped.map((p) => _SkippedRow(plan: p)),
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
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: () => _confirmSkip(context, app, plan),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(99),
                border: Border.all(color: t.line, width: 1.5),
              ),
              child: Text(
                '没吃',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: t.tx2,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
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
        ],
      ),
    );
  }

  static int _overdueMin(int minute) {
    final now = DateTime.now();
    return now.hour * 60 + now.minute - minute;
  }

  Future<void> _confirmSkip(
    BuildContext context,
    AppController app,
    DayPlan plan,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('这顿没吃？'),
        content: Text(
          '「${plan.medicine.name}」${formatMinutes(plan.minute)} 标记为没吃：'
          '不扣库存，也不计入今日应服数。点错了可以撤销。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('没吃'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (!context.mounted) return;
    await app.markSkipped(plan.medicine, app.slotTimeOf(plan.minute), context);
  }
}

/// 标记为没吃的格子：不扣库存、不算依从，点按可撤销标记。
class _SkippedRow extends StatelessWidget {
  final DayPlan plan;
  const _SkippedRow({required this.plan});

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppController>();
    final t = AppTokens.of(context);
    final m = plan.medicine;
    final log = plan.takenLog;
    return _TodoRow(
      circle: _DashCircle(color: t.tx2.withValues(alpha: 0.55)),
      name: '${m.name} · ${_fmt(m.amountPerDose)} ${m.unit}',
      info: '${formatMinutes(plan.minute)} 没吃 · 未扣库存',
      opacity: 0.5,
      onTap: log == null
          ? null
          : () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('取消这个「没吃」标记？'),
                  content: const Text('取消后这一格会重新变成应服，可以正常打卡。'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('保留'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('取消标记'),
                    ),
                  ],
                ),
              );
              if (ok == true) await app.undoLog(log);
            },
      trailing: Text(
        '点按撤销',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: t.tx2,
        ),
      ),
    );
  }
}

class _DashCircle extends StatelessWidget {
  final Color color;
  const _DashCircle({required this.color});

  @override
  Widget build(BuildContext context) => Container(
    width: 34,
    height: 34,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(color: color, width: 2.5),
    ),
    child: Icon(Icons.remove, size: 16, color: color),
  );
}

/// 已完成：点按行可撤销（撤销的是这一格对应的打卡，不是最近一条）。
class _DoneRow extends StatelessWidget {
  final DayPlan plan;
  const _DoneRow({required this.plan});

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppController>();
    final t = AppTokens.of(context);
    final m = plan.medicine;
    final log = plan.takenLog;
    final time = plan.takenAtMs == null
        ? ''
        : DateFormat('HH:mm')
              .format(DateTime.fromMillisecondsSinceEpoch(plan.takenAtMs!));
    final backfilled = log?.note == '补录';
    final info = [
      if (time.isNotEmpty) '$time 打卡',
      if (backfilled) '补录',
      if (m.note.isNotEmpty) m.note,
    ].join(' · ');
    return _TodoRow(
      circle: const _CheckCircle(filled: true),
      name: '${m.name} · ${_fmt(m.amountPerDose)} ${m.unit}',
      info: info.isEmpty ? '已完成' : info,
      opacity: 0.62,
      onTap: log == null ? null : () => _confirmUndo(context, app, log, m),
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

  Future<void> _confirmUndo(
    BuildContext context,
    AppController app,
    DoseLog log,
    Medicine m,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('撤销打卡？'),
        content: Text(
          '撤销「${m.name}」${DateFormat('M月d日 HH:mm').format(log.takenDateTime)} '
          '的打卡，退回 ${_fmt(log.amount)} ${m.unit} 库存。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('保留'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('撤销打卡'),
          ),
        ],
      ),
    );
    if (ok == true) await app.undoLog(log);
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

/// 近 6 天漏打卡的补录清单：补一条即按该时刻扣减库存。
class _MissedCard extends StatefulWidget {
  final List<MissedSlot> slots;
  const _MissedCard({required this.slots});

  @override
  State<_MissedCard> createState() => _MissedCardState();
}

class _MissedCardState extends State<_MissedCard> {
  static const _visible = 4;
  bool _expanded = false;
  String? _open; // 当前展开选择的漏打卡行

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppController>();
    final t = AppTokens.of(context);
    final all = widget.slots;
    final shown = _expanded ? all : all.take(_visible).toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.how_to_reg_outlined, size: 18, color: t.warn),
                const SizedBox(width: 7),
                Text(
                  '漏打卡补录（${all.length}）',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: t.tx,
                  ),
                ),
                const Spacer(),
                if (all.length > _visible)
                  TextButton(
                    onPressed: () => setState(() => _expanded = !_expanded),
                    child: Text(_expanded ? '收起' : '展开'),
                  ),
              ],
            ),
            Text(
              '这些时间点还没有打卡记录。点一条可以单独补打卡或标记没吃；'
              '确实全都吃过了，就全部补录，库存才会扣对。',
              style: TextStyle(fontSize: 12, color: t.tx2, height: 1.45),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _MiniButton(
                  label: '全部补录',
                  color: t.accent,
                  onTap: () => _confirmBulk(context, app, false),
                ),
                const SizedBox(width: 8),
                _MiniButton(
                  label: '全部没吃',
                  color: t.tx2,
                  onTap: () => _confirmBulk(context, app, true),
                ),
              ],
            ),
            const SizedBox(height: 6),
            for (final s in shown)
              _MissedRow(
                slot: s,
                open: _open == _keyOf(s),
                onToggle: () => setState(
                  () => _open = _open == _keyOf(s) ? null : _keyOf(s),
                ),
                onBackfill: () => _backfillOne(context, app, s),
                onSkip: () => _skipOne(context, app, s),
              ),
          ],
        ),
      ),
    );
  }

  static String _keyOf(MissedSlot s) =>
      '${s.medicine.id}@${s.slotTime.millisecondsSinceEpoch}';

  Future<void> _confirmBulk(
    BuildContext context,
    AppController app,
    bool asSkipped,
  ) async {
    final groups = <String, List<MissedSlot>>{};
    for (final s in widget.slots) {
      groups.putIfAbsent(s.medicine.id, () => []).add(s);
    }
    final lines = groups.values
        .map((g) {
          final m = g.first.medicine;
          return asSkipped
              ? '· ${m.name} ${g.length} 次'
              : '· ${m.name} ${g.length} 次，共 ${_fmt(g.length * m.amountPerDose)} ${m.unit}';
        })
        .join('\n');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(asSkipped ? '全部标记没吃？' : '全部补录？'),
        content: Text(
          asSkipped
              ? '将把下面 ${widget.slots.length} 个格子标记为没吃：不扣库存，也不计入依从率。\n$lines'
              : '将补 ${widget.slots.length} 条打卡，并按下列扣减库存：\n$lines\n'
                    '\n只有确实都吃过了才划算全部补。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(asSkipped ? '全部没吃' : '全部补录'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (!context.mounted) return;
    if (asSkipped) {
      await app.markAllSkipped(widget.slots, context);
    } else {
      await app.backfillAll(widget.slots, context);
    }
    if (mounted) setState(() => _open = null);
  }

  Future<void> _backfillOne(
    BuildContext context,
    AppController app,
    MissedSlot s,
  ) async {
    await app.backfillCheckIn(s, context);
    if (mounted) setState(() => _open = null);
  }

  Future<void> _skipOne(
    BuildContext context,
    AppController app,
    MissedSlot s,
  ) async {
    await app.markSkipped(s.medicine, s.slotTime, context);
    if (mounted) setState(() => _open = null);
  }
}

/// 漏打卡清单里的一行：点一下展开「补打卡 / 没吃」两个选择。
class _MissedRow extends StatelessWidget {
  final MissedSlot slot;
  final bool open;
  final VoidCallback onToggle;
  final VoidCallback onBackfill;
  final VoidCallback onSkip;
  const _MissedRow({
    required this.slot,
    required this.open,
    required this.onToggle,
    required this.onBackfill,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final s = slot;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
              child: Row(
                children: [
                  Icon(
                    open ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: t.tx2,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      '${s.medicine.name} · '
                      '${DateFormat('M月d日 HH:mm').format(s.slotTime)} · '
                      '${_fmt(s.medicine.amountPerDose)} ${s.medicine.unit}',
                      style: TextStyle(
                        fontWeight: open ? FontWeight.w700 : FontWeight.w500,
                        fontSize: 13.5,
                        color: t.tx,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (open)
            Padding(
              padding: const EdgeInsets.only(left: 22, top: 2, bottom: 4),
              child: Row(
                children: [
                  _MiniButton(label: '补打卡', color: t.accent, onTap: onBackfill),
                  const SizedBox(width: 8),
                  _MiniButton(label: '没吃', color: t.tx2, onTap: onSkip),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '补＝扣 ${_fmt(s.medicine.amountPerDose)} ${s.medicine.unit}；没吃＝不扣',
                      style: TextStyle(fontSize: 11, color: t.tx2),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _MiniButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _MiniButton({
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color, width: 1.5),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    ),
  );
}

String _fmt(double v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
