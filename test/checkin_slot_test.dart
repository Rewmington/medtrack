import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:medicine_tracker/app.dart';
import 'package:medicine_tracker/models.dart';

/// 打卡落在哪一格：直接跑 AppController + 临时库，复现「下午补点早上，晚上那格被顺手点亮」。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppController app;
  late Directory tmp;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('mt_checkin');
    app = AppController();
    await app.db.open(overridePath: '${tmp.path}\\t.db');
    await app.db.saveMedicine(
      Medicine(
        id: 'm1',
        name: '丁螺环酮',
        perBox: 30,
        remaining: 60,
        dosesPerDay: 2,
        amountPerDose: 1,
        times: '07:30,21:00',
        createdAt: 0,
        updatedAt: 0,
      ),
    );
    await app.refresh();
  });

  tearDown(() async {
    await app.db.close();
    tmp.deleteSync(recursive: true);
  });

  DayPlan planAt(int minute) =>
      app.todayPlan.firstWhere((p) => p.minute == minute);

  test('15:30 补点早上那一格，晚上那一格仍在「稍后」', () async {
    app.now = DateTime(2026, 10, 20, 15, 30);
    await app.refresh();

    await app.checkIn(app.medicines.first, 7 * 60 + 30);

    expect(app.todayPlan.length, 2);
    expect(planAt(7 * 60 + 30).taken, isTrue, reason: '点的那一格该亮');
    final evening = planAt(21 * 60);
    expect(evening.taken, isFalse, reason: '没点的格子不该被就近匹配带走');
    expect(evening.minute > 15 * 60 + 30, isTrue, reason: '仍归「稍后」段');
    expect(app.todayPlan.where((p) => p.taken).length, 1);
  });

  test('按下的钟点晚于格子时间时，记录写格子时刻', () async {
    app.now = DateTime(2026, 10, 20, 22, 5);
    await app.refresh();

    await app.checkIn(app.medicines.first, 21 * 60);

    final log = app.todayLogs.first;
    expect(log.takenAt, DateTime(2026, 10, 20, 21, 0).millisecondsSinceEpoch);
    expect(log.amount, 1, reason: '库存照常扣一次');
    expect(planAt(7 * 60 + 30).taken, isFalse, reason: '早上的格还没打，仍是漏');
  });

  test('标记没吃与打卡占的是同一格，互不串位', () async {
    app.now = DateTime(2026, 10, 20, 15, 30);
    await app.refresh();
    final m = app.medicines.first;

    await app.markSkipped(m, app.slotTimeOf(21 * 60), null);
    await app.checkIn(m, 7 * 60 + 30);

    expect(planAt(7 * 60 + 30).taken, isTrue);
    expect(planAt(21 * 60).skipped, isTrue);
    expect(app.todayPlan.where((p) => !p.skipped).where((p) => p.taken).length, 1);
  });
}
