import 'package:flutter/material.dart';

import '../theme.dart';

/// G 风格底部滚轮时间选择，替代 Material 默认的 showTimePicker 弹窗。
Future<TimeOfDay?> showTimeSheet({
  required BuildContext context,
  required TimeOfDay initial,
  String title = '选择时间',
}) {
  final t = AppTokens.of(context);
  var hour = initial.hour;
  var minute = initial.minute;
  return showModalBottomSheet<TimeOfDay>(
    context: context,
    backgroundColor: t.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) {
      final bottomInset = MediaQuery.of(ctx).viewInsets.bottom;
      return Padding(
        padding: EdgeInsets.fromLTRB(20, 6, 20, 10 + bottomInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: t.tx.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Row(
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: t.tx,
                    fontFamily: AppTokens.serif,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(
                    '取消',
                    style: TextStyle(color: t.tx.withValues(alpha: 0.6)),
                  ),
                ),
                const SizedBox(width: 6),
                FilledButton(
                  onPressed: () =>
                      Navigator.pop(ctx, TimeOfDay(hour: hour, minute: minute)),
                  child: const Text('确定'),
                ),
              ],
            ),
            SizedBox(
              height: 208,
              child: Row(
                children: [
                  Expanded(
                    child: _Wheel(
                      count: 24,
                      initial: hour,
                      unit: '时',
                      t: t,
                      onChanged: (v) => hour = v,
                    ),
                  ),
                  Expanded(
                    child: _Wheel(
                      count: 60,
                      initial: minute,
                      unit: '分',
                      t: t,
                      onChanged: (v) => minute = v,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _Wheel extends StatelessWidget {
  final int count;
  final int initial;
  final String unit;
  final AppTokens t;
  final ValueChanged<int> onChanged;

  const _Wheel({
    required this.count,
    required this.initial,
    required this.unit,
    required this.t,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Stack(
            alignment: Alignment.center,
            children: [
              ListWheelScrollView.useDelegate(
                itemExtent: 40,
                perspective: 0.001,
                physics: const FixedExtentScrollPhysics(),
                controller: FixedExtentScrollController(initialItem: initial),
                onSelectedItemChanged: onChanged,
                childDelegate: ListWheelChildBuilderDelegate(
                  childCount: count,
                  builder: (context, i) => Center(
                    child: Text(
                      i.toString().padLeft(2, '0'),
                      style: TextStyle(
                        fontSize: 22,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: t.tx,
                      ),
                    ),
                  ),
                ),
              ),
              IgnorePointer(
                child: Container(
                  height: 40,
                  margin: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: t.tx.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
        ),
        Text(
          unit,
          style: TextStyle(fontSize: 12, color: t.tx.withValues(alpha: 0.5)),
        ),
      ],
    );
  }
}
