import 'package:flutter_test/flutter_test.dart';
import 'package:medicine_tracker/models.dart';

void main() {
  Medicine make({
    double remaining = 60,
    double perBox = 30,
    double doses = 3,
    double amount = 1,
    int lowDays = 7,
    String times = '',
  }) => Medicine(
    id: 'x',
    name: '测试药',
    remaining: remaining,
    perBox: perBox,
    dosesPerDay: doses,
    amountPerDose: amount,
    lowDays: lowDays,
    times: times,
    createdAt: 0,
    updatedAt: 0,
  );

  group('剩余天数计算', () {
    test('剩余数量 ÷ 日消耗', () {
      final m = make(); // 60片 ÷ 3片/天 = 20 天
      expect(m.dailyUse, 3);
      expect(m.daysLeft, closeTo(20, 0.001));
      expect(m.boxesDisplay, closeTo(2, 0.001));
      expect(m.isLow, isFalse);
      expect(m.isOut, isFalse);
    });

    test('低于预警阈值时标红', () {
      final m = make(remaining: 15); // 5 天 < 7 天阈值
      expect(m.daysLeft, closeTo(5, 0.001));
      expect(m.isLow, isTrue);
    });

    test('库存耗尽', () {
      final m = make(remaining: 0);
      expect(m.isOut, isTrue);
      expect(m.stockRatio, 0);
    });

    test('未设置用量时无法计算', () {
      final m = make(doses: 0);
      expect(m.daysLeft, isNull);
      expect(m.estimatedFinishDate, isNull);
      expect(m.isLow, isFalse);
      expect(m.stockRatio, 1);
    });

    test('半片用量', () {
      final m = make(remaining: 28, perBox: 28, doses: 1, amount: 0.5);
      expect(m.daysLeft, closeTo(56, 0.001));
    });

    test('stockRatio 按预警窗口 2 倍封顶', () {
      expect(make(remaining: 21).stockRatio, closeTo(0.5, 0.001)); // 7/14 天
      expect(make(remaining: 300).stockRatio, 1); // 100 天 → clamp 1
    });
  });

  group('服药时间点', () {
    test('times 为空时按次数自动生成', () {
      expect(make(doses: 1).scheduleMinutes, [8 * 60]);
      final three = make(doses: 3).scheduleMinutes;
      expect(three.length, 3);
      expect(three.first, 7 * 60 + 30);
      expect(three.last, 21 * 60);
      expect(three, orderedEquals(three.toList()..sort()));
    });

    test('times 解析并按时间排序，容忍中文分隔符', () {
      final m = make(times: '20:00，08:00; 14:00');
      expect(m.scheduleMinutes, [8 * 60, 14 * 60, 20 * 60]);
    });

    test('非法时间点忽略后回退自动生成', () {
      expect(make(times: '99:99').scheduleMinutes, make().scheduleMinutes);
    });

    test('未设置用量时不生成时间点', () {
      expect(make(doses: 0).scheduleMinutes, isEmpty);
    });

    test('formatMinutes 补零', () {
      expect(formatMinutes(0), '00:00');
      expect(formatMinutes(8 * 60 + 5), '08:05');
      expect(formatMinutes(21 * 60), '21:00');
    });
  });

  group('槽位与打卡就近匹配', () {
    const base = 1759276800000; // 2026-10-01 00:00 UTC+8 之类的整天起点，值本身无关
    final slots = [8 * 60, 12 * 60, 20 * 60];
    int at(int hour, [int minute = 0]) => base + (hour * 60 + minute) * 60000;

    test('只打了晚上的卡，点亮的是 20:00 而不是 08:00', () {
      final m = matchSlots(slots, [at(20, 1)], base);
      expect(m[0], isNull);
      expect(m[1], isNull);
      expect(m[2], at(20, 1));
    });

    test('迟到的 08:30 仍算早间那一格', () {
      final m = matchSlots(slots, [at(8, 30)], base);
      expect(m[0], at(8, 30));
      expect(m.sublist(1), [null, null]);
    });

    test('三格都打过则全部点亮', () {
      final m = matchSlots(slots, [at(8), at(12), at(20)], base);
      expect(m.every((e) => e != null), isTrue);
    });

    test('两次打卡按就近占据两格，剩下最远那格算漏', () {
      final m = matchSlots(slots, [at(9), at(13)], base);
      expect(m[0], at(9));
      expect(m[1], at(13));
      expect(m[2], isNull);
    });

    test('空槽位或没有打卡', () {
      expect(matchSlots(const [], [at(8)], base), isEmpty);
      expect(matchSlots(slots, const [], base), [null, null, null]);
    });
  });

  test('没吃标记（0 剂量）序列化往返并保持跳过语义', () {
    final skip = DoseLog(
      id: 's',
      medicineId: 'x',
      takenAt: 123,
      amount: 0,
      note: '没吃',
      updatedAt: 456,
    );
    final back = DoseLog.fromRow(skip.toRow());
    expect(back.amount, 0);
    expect(back.isSkipped, isTrue);
    expect(
      DoseLog(
        id: 't',
        medicineId: 'x',
        takenAt: 1,
        amount: 1,
        updatedAt: 1,
      ).isSkipped,
      isFalse,
    );
  });

  group('本周总结统计', () {
    // 固定「现在」为 10 月 3 日 21:30，窗口＝9 月 27 日～10 月 3 日，两天 4 格全到期
    final now = DateTime(2026, 10, 3, 21, 30);
    final med = make(doses: 2, amount: 1, times: '08:00,20:00');

    List<DoseLog> slotLogs(
      List<int> backs,
      List<int> hours, {
      double amount = 1,
    }) => [
      for (final back in backs)
        for (final h in hours)
          DoseLog(
            id: 'l$back$h$amount',
            medicineId: med.id,
            takenAt: DateTime(2026, 10, 3 - back, h).millisecondsSinceEpoch,
            amount: amount,
            note: amount == 0 ? '没吃' : '',
            updatedAt: 1,
          ),
    ];

    final all = [
      for (final b in [6, 5, 4, 3, 2, 1, 0]) ...slotLogs([b], [8, 20]),
    ];

    test('全部按时打卡＝满勤', () {
      final s = computeWeekStats([med], all, now);
      expect(s.owed, 14);
      expect(s.taken, 14);
      expect(s.missed, 0);
      expect(s.perfect, isTrue);
      expect(s.rate, 1.0);
      expect(s.headline, '本周至今一次没漏');
    });

    test('一次没打＝漏满一周', () {
      final s = computeWeekStats([med], const [], now);
      expect(s.owed, 14);
      expect(s.missed, 14);
      expect(s.perfect, isFalse);
      expect(s.rate, 0.0);
    });

    test('今天还没到的时间点不算欠', () {
      final s = computeWeekStats([med], const [], DateTime(2026, 10, 3, 9, 0));
      expect(s.owed, 13); // 6 天 × 2 格 + 今天只有 08:00 到期
    });

    test('早间实服＋晚间标记没吃＝那天不缺，仍算满勤', () {
      final logs = <DoseLog>[
        ...slotLogs([6, 5, 4, 3, 2, 1, 0], [8]),
        ...slotLogs([6, 5, 4, 3, 2, 1, 0], [20], amount: 0),
      ];
      final s = computeWeekStats([med], logs, now);
      expect(s.skipped, 7);
      expect(s.owed, 7);
      expect(s.taken, 7);
      expect(s.missed, 0);
      expect(s.perfect, isTrue);
    });

    test('药品添加之前的日子不计应服', () {
      final late = Medicine(
        id: med.id,
        name: med.name,
        perBox: 30,
        remaining: 60,
        dosesPerDay: 2,
        amountPerDose: 1,
        times: '08:00,20:00',
        createdAt: DateTime(2026, 10, 2, 7).millisecondsSinceEpoch,
        updatedAt: 1,
      );
      final s = computeWeekStats([late], const [], now);
      expect(s.owed, 4); // 只有 10 月 2、3 两天，各 2 格
    });

    test('同一格连点两次不虚增应服完成数', () {
      final s = computeWeekStats([med], [...all, ...all], now);
      expect(s.taken, 14); // 每天被时间点数量截断
      expect(s.owed, 14);
      expect(s.missed, 0);
    });
  });

  test('行序列化往返一致', () {
    final m = make(times: '08:00,20:00');
    final back = Medicine.fromRow(m.toRow());
    expect(back.id, m.id);
    expect(back.remaining, m.remaining);
    expect(back.boxesDisplay, closeTo(m.boxesDisplay, 0.001));
    expect(back.times, m.times);
    expect(back.daysLeft, closeTo(m.daysLeft!, 0.001));
  });

  test('旧行缺少 remaining 时按 盒数×每盒 回填', () {
    final row = make().toRow()..remove('remaining');
    final back = Medicine.fromRow(row);
    expect(back.remaining, 60);
  });

  test('打卡记录往返一致', () {
    final log = DoseLog(
      id: 'l',
      medicineId: 'x',
      takenAt: 123,
      amount: 1,
      updatedAt: 456,
    );
    final backLog = DoseLog.fromRow(log.toRow());
    expect(backLog.takenAt, 123);
    expect(backLog.deleted, isFalse);
  });
}
