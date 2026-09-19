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
  }) =>
      Medicine(
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
      expect(make(times: '99:99').scheduleMinutes,
          make().scheduleMinutes);
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
        id: 'l', medicineId: 'x', takenAt: 123, amount: 1, updatedAt: 456);
    final backLog = DoseLog.fromRow(log.toRow());
    expect(backLog.takenAt, 123);
    expect(backLog.deleted, isFalse);
  });
}
