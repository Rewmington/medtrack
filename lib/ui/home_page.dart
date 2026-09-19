import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app.dart';
import '../models.dart';
import '../theme.dart';
import 'edit_page.dart';

/// 药品：库存一览。打卡在「今天」页，这里点卡片进编辑。
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final low = app.medicines.where((m) => m.isLow).toList();
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'add-med',
        onPressed: () => _openEditor(context),
        icon: const Icon(Icons.add),
        label: const Text('添加药品'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 100),
          children: [
            PageHeader(
              sub: app.medicines.isEmpty
                  ? '共 0 种'
                  : '共 ${app.medicines.length} 种',
              title: '药品',
            ),
            if (low.isNotEmpty)
              _LowStockBanner(names: low.map((m) => m.name).join('、')),
            const SizedBox(height: 10),
            if (app.medicines.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 40, 20, 0),
                child: Column(
                  children: [
                    Icon(
                      Icons.medication_liquid_outlined,
                      size: 56,
                      color: AppTokens.of(context).tx2,
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      '还没有药品',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '添加后自动计算还能吃几天，到点提醒打卡',
                      style: TextStyle(
                        color: AppTokens.of(context).tx2,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: () => _openEditor(context),
                      icon: const Icon(Icons.add),
                      label: const Text('添加第一种药'),
                    ),
                  ],
                ),
              )
            else
              for (final m in app.medicines)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: _MedicineCard(medicine: m),
                ),
          ],
        ),
      ),
    );
  }

  static Future<void> _openEditor(BuildContext context, [Medicine? m]) async {
    final app = context.read<AppController>();
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => EditPage(medicine: m)));
    await app.refresh();
  }
}

/// 误点打卡后再次点按：确认后删除最近一次打卡并退回库存。电脑/手机通用。
Future<void> confirmUndoCheckIn(
  BuildContext context,
  AppController app,
  Medicine m,
) async {
  final log = app.latestTodayLog(m.id);
  if (log == null) return;
  final t = log.takenDateTime;
  final hhmm =
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('撤销打卡？'),
      content: Text(
        '撤销「${m.name}」$hhmm 的打卡，退回 ${_trim(log.amount)} ${m.unit} 库存。',
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

String _trim(double v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

class _LowStockBanner extends StatelessWidget {
  final String names;
  const _LowStockBanner({required this.names});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 10, 20, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: t.warnSoft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.warn.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(Icons.local_fire_department_outlined, color: t.warn, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$names 余量不足，请及时补充',
              style: TextStyle(color: t.tx, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _MedicineCard extends StatelessWidget {
  final Medicine medicine;
  const _MedicineCard({required this.medicine});

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppController>();
    final t = AppTokens.of(context);
    final m = medicine;
    final days = m.daysLeft;
    final String pillText;
    final Color pillColor, pillSoft;
    if (m.isOut) {
      pillText = '已用完';
      pillColor = t.err;
      pillSoft = t.errSoft;
    } else if (m.isLow) {
      pillText = days == null ? '偏低' : '偏低 · ${days.ceil()} 天';
      pillColor = t.warn;
      pillSoft = t.warnSoft;
    } else if (days == null) {
      pillText = '未设用量';
      pillColor = t.tx2;
      pillSoft = t.track;
    } else {
      pillText = '充足 · ${days.ceil()} 天';
      pillColor = t.ok;
      pillSoft = t.okSoft;
    }
    final barColor = m.isOut
        ? t.err
        : m.isLow
        ? t.warn
        : t.accent;
    final taken = app.takenToday(m.id);
    final planned = m.scheduleMinutes.length;
    final todayHint = planned == 0
        ? ''
        : taken >= planned
        ? '今日已服完'
        : '今天还有 ${planned - taken} 次';
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => HomePage._openEditor(context, m),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
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
                      style: TextStyle(
                        fontFamily: AppTokens.serif,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: t.tx,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: pillSoft,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      pillText,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: pillColor,
                      ),
                    ),
                  ),
                  PopupMenuButton<String>(
                    padding: EdgeInsets.zero,
                    icon: Icon(Icons.more_horiz, color: t.tx2),
                    onSelected: (v) => switch (v) {
                      'edit' => HomePage._openEditor(context, m),
                      'restock' => _restockDialog(context, app),
                      'delete' => _confirmDelete(context, app),
                      _ => null,
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'restock', child: Text('补货（加盒数）')),
                      PopupMenuItem(value: 'edit', child: Text('编辑详情')),
                      PopupMenuItem(value: 'delete', child: Text('删除')),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                '每日 ${_trim(m.dosesPerDay)} 次 · ${m.scheduleMinutes.map(formatMinutes).join(' / ')} · 每次 ${_trim(m.amountPerDose)} ${m.unit}',
                style: TextStyle(fontSize: 12, color: t.tx2),
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: m.isOut ? 0.02 : m.stockRatio,
                  minHeight: 6,
                  color: barColor,
                  backgroundColor: t.track,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      m.isOut
                          ? '余 0 ${m.unit}'
                          : '余 ${_trim(m.boxesDisplay)} 盒 · ${_trim(m.perBox)} ${m.unit}/盒',
                      style: TextStyle(fontSize: 12.5, color: t.tx2),
                    ),
                  ),
                  if (m.isLow || m.isOut)
                    GestureDetector(
                      onTap: () => _restockDialog(context, app),
                      child: Text(
                        m.isOut ? '去药店补货 ›' : '建议补货 ›',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: barColor,
                        ),
                      ),
                    )
                  else if (todayHint.isNotEmpty)
                    Text(
                      todayHint,
                      style: TextStyle(fontSize: 12.5, color: t.tx2),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _restockDialog(BuildContext context, AppController app) {
    showDialog(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        title: Text('补货 ${medicine.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final n in [1, 2, 3])
              ListTile(
                leading: const Icon(Icons.add_box_outlined),
                title: Text('补 $n 盒'),
                onTap: () {
                  Navigator.pop(dlgCtx);
                  app.restock(medicine, n.toDouble());
                },
              ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, AppController app) {
    showDialog(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        title: Text('删除 ${medicine.name}？'),
        content: const Text('历史打卡记录会保留，可同步到其他设备。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dlgCtx),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dlgCtx).colorScheme.error,
            ),
            onPressed: () {
              Navigator.pop(dlgCtx);
              app.deleteMedicine(medicine.id);
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}
