import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app.dart';
import '../db.dart';
import '../models.dart';
import '../theme.dart';
import 'time_sheet.dart';

class EditPage extends StatefulWidget {
  final Medicine? medicine;
  const EditPage({super.key, this.medicine});

  @override
  State<EditPage> createState() => _EditPageState();
}

class _EditPageState extends State<EditPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  double _boxes = 1;
  bool _boxesTouched = false; // 直接改盒数才重算库存，避免除不尽的舍入误差
  double _perBox = 30;
  double _doses = 3;
  double _amount = 1;
  late final TextEditingController _unit;
  int _lowDays = 7;
  late final TextEditingController _note;
  List<int> _times = []; // 空 = 自动
  late bool _autoTimes;

  /// 早/中/晚快捷时段：窗口用于初始识别，默认时间用于首次点选。
  static const _slotDefs = [
    (label: '早晨', start: 5 * 60, end: 11 * 60, def: 8 * 60),
    (label: '中午', start: 11 * 60, end: 16 * 60, def: 12 * 60),
    (label: '晚上', start: 16 * 60, end: 24 * 60, def: 20 * 60),
  ];

  /// 已选时段 → 该时段对应的时间点（分钟）；未选则无键。
  final Map<int, int> _slotState = {};

  /// 未选时段被长按改过的默认时间，下次点选时沿用。
  final Map<int, int> _slotCustom = {};

  bool get isNew => widget.medicine == null;

  @override
  void initState() {
    super.initState();
    final m = widget.medicine;
    _name = TextEditingController(text: m?.name ?? '');
    _unit = TextEditingController(text: m?.unit ?? '片');
    _note = TextEditingController(text: m?.note ?? '');
    if (m != null) {
      final b = m.perBox > 0 ? m.remaining / m.perBox : m.boxesDisplay;
      _boxes = (b * 100).roundToDouble() / 100; // 展示用，2 位小数
      _perBox = m.perBox;
      _doses = m.dosesPerDay;
      _amount = m.amountPerDose;
      _lowDays = m.lowDays;
      _autoTimes = m.times.isEmpty;
      _times = m.times.isEmpty ? [] : m.scheduleMinutes;
      for (var i = 0; i < _slotDefs.length; i++) {
        final d = _slotDefs[i];
        for (final t in _times) {
          if (t >= d.start && t < d.end) {
            _slotState[i] = t;
            break;
          }
        }
      }
    } else {
      _autoTimes = true;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _unit.dispose();
    _note.dispose();
    super.dispose();
  }

  double get _remaining => _boxesTouched
      ? _boxes * _perBox
      : (widget.medicine?.remaining ?? _boxes * _perBox);
  double get _dailyUse => _doses * _amount;
  double? get _daysLeft => _dailyUse > 0 ? _remaining / _dailyUse : null;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final days = _daysLeft;
    return Scaffold(
      appBar: AppBar(title: Text(isNew ? '添加药品' : '编辑药品')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                children: [
                  _Group(
                    label: '基本信息',
                    children: [
                      TextFormField(
                        controller: _name,
                        textCapitalization: TextCapitalization.none,
                        style: const TextStyle(fontSize: 16),
                        decoration: const InputDecoration(
                          labelText: '药品名称',
                          prefixIcon: Icon(Icons.label_outline),
                        ),
                        validator: (v) =>
                            v == null || v.trim().isEmpty ? '请填写名称' : null,
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _unit,
                              decoration: const InputDecoration(
                                labelText: '单位',
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _StepperField(
                              label: '预警天数',
                              value: _lowDays.toDouble(),
                              min: 1,
                              max: 60,
                              step: 1,
                              onChanged: (v) =>
                                  setState(() => _lowDays = v.toInt()),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _note,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: '备注（饭前饭后等说明）',
                          prefixIcon: Icon(Icons.notes),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _Group(
                    label: '库存',
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _StepperField(
                              label: '剩余盒数',
                              value: _boxes,
                              min: 0,
                              max: 99,
                              step: 1,
                              onChanged: (v) => setState(() {
                                _boxes = v;
                                _boxesTouched = true;
                              }),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _StepperField(
                              label: '每盒数量',
                              value: _perBox,
                              min: 1,
                              max: 1000,
                              step: 1,
                              onChanged: (v) => setState(() => _perBox = v),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _Group(
                    label: '用法用量',
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _StepperField(
                              label: '每天次数',
                              value: _doses,
                              min: 0,
                              max: 12,
                              step: 1,
                              onChanged: (v) => setState(() => _doses = v),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _StepperField(
                              label: '每次用量',
                              value: _amount,
                              min: 0,
                              max: 20,
                              step: 0.5,
                              onChanged: (v) => setState(() => _amount = v),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _Group(
                    label: '服药时间',
                    children: [
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('自动安排时间'),
                        subtitle: Text(
                          _autoTimes
                              ? '按每天 ${_doses.toInt()} 次自动生成提醒点'
                              : '手动指定提醒时间点',
                        ),
                        value: _autoTimes,
                        onChanged: (v) => setState(() {
                          _autoTimes = v;
                          if (v) {
                            _times = [];
                            _slotState.clear();
                          }
                        }),
                      ),
                      if (!_autoTimes) ...[
                        Wrap(
                          spacing: 8,
                          children: [
                            for (var i = 0; i < _slotDefs.length; i++)
                              GestureDetector(
                                onLongPress: () => _editSlot(i),
                                child: FilterChip(
                                  selected: _slotState.containsKey(i),
                                  label: Text(
                                    _slotState[i] != null
                                        ? '${_slotDefs[i].label} ${formatMinutes(_slotState[i]!)}'
                                        : _slotCustom[i] != null
                                        ? '${_slotDefs[i].label} ${formatMinutes(_slotCustom[i]!)}'
                                        : _slotDefs[i].label,
                                  ),
                                  onSelected: (v) => _toggleSlot(i, v),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '点按时段选择 · 长按改该时段时间',
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (var i = 0; i < _times.length; i++)
                            InputChip(
                              label: Text(formatMinutes(_times[i])),
                              avatar: const Icon(Icons.alarm, size: 16),
                              onDeleted: () => setState(() {
                                final min = _times.removeAt(i);
                                _slotState.removeWhere((_, v) => v == min);
                              }),
                            ),
                          if (!_autoTimes)
                            ActionChip(
                              avatar: const Icon(Icons.add_alarm, size: 16),
                              label: const Text('添加时间点'),
                              onPressed: _addTime,
                            ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          scheme.primaryContainer,
                          scheme.primaryContainer.withValues(alpha: 0.5),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.hourglass_bottom_rounded,
                          color: scheme.onPrimaryContainer,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                '估算还能吃',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.blueGrey,
                                ),
                              ),
                              Text(
                                days == null
                                    ? '设置用量后自动计算'
                                    : days < 1
                                    ? '不足 1 天（约 ${(days * 24).ceil()} 小时）'
                                    : '约 ${days.ceil()} 天 · ${_trim(_remaining)} ${_unit.text}',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                  color: scheme.onPrimaryContainer,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    onPressed: _save,
                    child: Text(isNew ? '保存' : '保存修改'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _trim(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  void _toggleSlot(int i, bool on) {
    setState(() {
      if (on) {
        final min = _slotCustom[i] ?? _slotDefs[i].def;
        _slotState[i] = min;
        if (!_times.contains(min)) _times.add(min);
      } else {
        final min = _slotState.remove(i);
        if (min != null) {
          _times.remove(min);
          _slotCustom[i] = min; // 记住这次的时间，取消再选不丢
        }
      }
      _times.sort();
    });
  }

  Future<void> _editSlot(int i) async {
    final cur = _slotState[i] ?? _slotCustom[i] ?? _slotDefs[i].def;
    final t = await showTimeSheet(
      context: context,
      title: '${_slotDefs[i].label} · 服药时间',
      initial: TimeOfDay(hour: cur ~/ 60, minute: cur % 60),
    );
    if (t == null || !mounted) return;
    final min = t.hour * 60 + t.minute;
    setState(() {
      if (_slotState.containsKey(i)) {
        final old = _slotState[i]!;
        if (old != min) _times.remove(old);
        _slotState[i] = min;
        if (!_times.contains(min)) _times.add(min);
      } else {
        _slotCustom[i] = min;
      }
      _times.sort();
    });
  }

  Future<void> _addTime() async {
    final t = await showTimeSheet(context: context, initial: TimeOfDay.now());
    if (t != null) {
      setState(() {
        _times.add(t.hour * 60 + t.minute);
        _times.sort();
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final app = context.read<AppController>();
    final now = DateTime.now().millisecondsSinceEpoch;
    final m = Medicine(
      id: widget.medicine?.id ?? LocalDb.newId(),
      name: _name.text.trim(),
      perBox: _perBox,
      remaining: _remaining,
      dosesPerDay: _doses,
      amountPerDose: _amount,
      unit: _unit.text.trim().isEmpty ? '片' : _unit.text.trim(),
      lowDays: _lowDays,
      note: _note.text.trim(),
      times: _autoTimes ? '' : _times.map(formatMinutes).join(','),
      createdAt: widget.medicine?.createdAt ?? now,
      updatedAt: now,
    );
    await app.saveMedicine(m);
    if (mounted) Navigator.pop(context);
  }
}

class _Group extends StatelessWidget {
  final String label;
  final List<Widget> children;
  const _Group({required this.label, required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: children),
          ),
        ),
      ],
    );
  }
}

class _StepperField extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final double step;
  final ValueChanged<double> onChanged;
  const _StepperField({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.onChanged,
  });

  static String fmt(double v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    var s = v.toStringAsFixed(2);
    if (s.endsWith('0')) s = s.substring(0, s.length - 1);
    return s;
  }

  static double bump(double v, double delta) =>
      ((v + delta) * 100).roundToDouble() / 100;

  /// 点按数值直接输入，避免非整十数（如每盒 21 片）逐格点击。
  Future<void> _editValue(BuildContext context) async {
    final controller = TextEditingController(text: fmt(value));
    final result = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(label),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onSubmitted: (s) => Navigator.pop(ctx, double.tryParse(s.trim())),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(ctx, double.tryParse(controller.text.trim())),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (result != null) onChanged(result.clamp(min, max));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.brightness == Brightness.dark
            ? Colors.white.withValues(alpha: 0.07)
            : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                iconSize: 18,
                onPressed: value > min
                    ? () => onChanged(bump(value, -step).clamp(min, max))
                    : null,
                icon: const Icon(Icons.remove_circle_outline),
              ),
              Expanded(
                child: Tooltip(
                  message: '点按直接输入',
                  triggerMode: TooltipTriggerMode.tap,
                  child: GestureDetector(
                    onTap: () => _editValue(context),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        fmt(value),
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          fontFamily: AppTokens.serif,
                          color: Theme.of(context).colorScheme.onSurface,
                          decoration: TextDecoration.underline,
                          decorationColor: Colors.blueGrey,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              IconButton(
                iconSize: 18,
                onPressed: value < max
                    ? () => onChanged(bump(value, step).clamp(min, max))
                    : null,
                icon: const Icon(Icons.add_circle_outline),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
