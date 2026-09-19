/// 一条药品记录。
/// 库存以 [remaining]（单位个数）为唯一真相，盒数 = remaining / perBox 仅用于展示与录入。
class Medicine {
  final String id;
  String name;
  double perBox; // 每盒数量
  double remaining; // 当前剩余数量（单位）
  double dosesPerDay;
  double amountPerDose;
  String unit;
  int lowDays; // 剩余天数低于该值时预警
  String note;
  String times; // 每日服药时间点，逗号分隔 "08:00,14:00,20:00"；空=自动
  final int createdAt;
  int updatedAt;
  bool deleted;

  Medicine({
    required this.id,
    required this.name,
    required this.perBox,
    required this.remaining,
    required this.dosesPerDay,
    required this.amountPerDose,
    this.unit = '片',
    this.lowDays = 7,
    this.note = '',
    this.times = '',
    required this.createdAt,
    required this.updatedAt,
    this.deleted = false,
  });

  double get boxesDisplay => perBox > 0 ? remaining / perBox : 0;

  double get dailyUse => dosesPerDay * amountPerDose;

  /// 还能吃几天；null 表示未设置用量（无法计算）。
  double? get daysLeft {
    if (dailyUse <= 0) return null;
    return remaining / dailyUse;
  }

  DateTime? get estimatedFinishDate {
    final d = daysLeft;
    if (d == null) return null;
    return DateTime.now().add(Duration(days: d.ceil()));
  }

  /// 余量占预警窗口的比例（0~1），用于进度条。
  double get stockRatio {
    final d = daysLeft;
    if (d == null || lowDays <= 0) return 1;
    return (d / (lowDays * 2)).clamp(0.0, 1.0);
  }

  bool get isLow {
    final d = daysLeft;
    return d != null && d <= lowDays;
  }

  bool get isOut => remaining <= 0;

  String get dailyUseLabel =>
      '每天 $dosesPerDay 次 × 每次 ${_fmt(amountPerDose)} $unit';

  /// 服药时间点；times 为空时按次数在 7:30~21:00 均匀生成。
  List<int> get scheduleMinutes {
    final parsed =
        times
            .split(RegExp(r'[,，;；\s]+'))
            .where((s) => s.contains(':'))
            .map((s) {
              final parts = s.split(':');
              if (parts.length != 2) return null;
              final h = int.tryParse(parts[0]);
              final m = int.tryParse(parts[1]);
              if (h == null || m == null || h > 23 || m > 59) return null;
              return h * 60 + m;
            })
            .whereType<int>()
            .toList()
          ..sort();
    if (parsed.isNotEmpty) return parsed;
    final n = dosesPerDay.round();
    if (n <= 0) return const [];
    if (n == 1) return [8 * 60];
    const start = 7 * 60 + 30;
    const end = 21 * 60;
    return List.generate(
      n,
      (i) => (start + (end - start) * i / (n - 1)).round(),
    );
  }

  static String _fmt(num v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

  Map<String, Object?> toRow() => {
    'id': id,
    'name': name,
    'boxes': boxesDisplay,
    'per_box': perBox,
    'remaining': remaining,
    'doses_per_day': dosesPerDay,
    'amount_per_dose': amountPerDose,
    'unit': unit,
    'low_days': lowDays,
    'note': note,
    'times': times,
    'created_at': createdAt,
    'updated_at': updatedAt,
    'deleted': deleted ? 1 : 0,
  };

  factory Medicine.fromRow(Map<String, Object?> r) {
    final perBox = (r['per_box'] as num?)?.toDouble() ?? 0;
    final boxes = (r['boxes'] as num?)?.toDouble() ?? 0;
    return Medicine(
      id: r['id'] as String,
      name: r['name'] as String? ?? '',
      perBox: perBox,
      remaining: (r['remaining'] as num?)?.toDouble() ?? boxes * perBox,
      dosesPerDay: (r['doses_per_day'] as num?)?.toDouble() ?? 0,
      amountPerDose: (r['amount_per_dose'] as num?)?.toDouble() ?? 0,
      unit: r['unit'] as String? ?? '片',
      lowDays: (r['low_days'] as num?)?.toInt() ?? 7,
      note: r['note'] as String? ?? '',
      times: r['times'] as String? ?? '',
      createdAt: (r['created_at'] as num?)?.toInt() ?? 0,
      updatedAt: (r['updated_at'] as num?)?.toInt() ?? 0,
      deleted: (r['deleted'] as num? ?? 0) != 0,
    );
  }
}

/// 一次服药打卡。
class DoseLog {
  final String id;
  final String medicineId;
  final int takenAt; // epoch millis
  final double amount;
  String note;
  int updatedAt;
  bool deleted;

  DoseLog({
    required this.id,
    required this.medicineId,
    required this.takenAt,
    required this.amount,
    this.note = '',
    required this.updatedAt,
    this.deleted = false,
  });

  DateTime get takenDateTime => DateTime.fromMillisecondsSinceEpoch(takenAt);

  Map<String, Object?> toRow() => {
    'id': id,
    'medicine_id': medicineId,
    'taken_at': takenAt,
    'amount': amount,
    'note': note,
    'updated_at': updatedAt,
    'deleted': deleted ? 1 : 0,
  };

  factory DoseLog.fromRow(Map<String, Object?> r) => DoseLog(
    id: r['id'] as String,
    medicineId: r['medicine_id'] as String,
    takenAt: (r['taken_at'] as num?)?.toInt() ?? 0,
    amount: (r['amount'] as num?)?.toDouble() ?? 0,
    note: r['note'] as String? ?? '',
    updatedAt: (r['updated_at'] as num?)?.toInt() ?? 0,
    deleted: (r['deleted'] as num? ?? 0) != 0,
  );
}

String formatMinutes(int m) =>
    '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
