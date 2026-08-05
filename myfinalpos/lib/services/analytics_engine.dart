import '../models/product.dart';
import '../models/sales_history_record.dart';

enum AnalyticsReportType {
  salesSummary,
  categoryComparison,
  bestSellers,
  salesTrend,
  periodComparison,
  branchComparison,
  paymentBreakdown,
  customerType,
}

enum AnalyticsPeriodPreset {
  today,
  yesterday,
  thisWeek,
  lastWeek,
  thisMonth,
  lastMonth,
  custom,
}

enum AnalyticsTrendGranularity { day, week, month }

class AnalyticsDateRange {
  const AnalyticsDateRange({required this.start, required this.end, this.label});

  final DateTime start;
  final DateTime end;
  final String? label;

  bool contains(DateTime value) {
    final instant = DateTime(value.year, value.month, value.day);
    final startDay = DateTime(start.year, start.month, start.day);
    final endDay = DateTime(end.year, end.month, end.day, 23, 59, 59, 999);
    return !instant.isBefore(startDay) && !value.isAfter(endDay);
  }

  int get daySpan {
    final startDay = DateTime(start.year, start.month, start.day);
    final endDay = DateTime(end.year, end.month, end.day);
    return endDay.difference(startDay).inDays + 1;
  }
}

class AnalyticsSummary {
  const AnalyticsSummary({
    required this.totalSales,
    required this.orderCount,
    required this.itemCount,
    required this.totalDiscount,
    required this.averageTicket,
    required this.walkInOrders,
    required this.registeredOrders,
  });

  final double totalSales;
  final int orderCount;
  final int itemCount;
  final double totalDiscount;
  final double averageTicket;
  final int walkInOrders;
  final int registeredOrders;
}

class AnalyticsNamedValue {
  const AnalyticsNamedValue({
    required this.label,
    required this.value,
    this.secondary,
  });

  final String label;
  final double value;
  final double? secondary;
}

class AnalyticsHourlyCell {
  const AnalyticsHourlyCell({
    required this.date,
    required this.hour,
    required this.units,
    required this.amount,
  });

  final DateTime date;
  final int hour;
  final double units;
  final double amount;
}

class AnalyticsHourlyGrid {
  const AnalyticsHourlyGrid({
    required this.days,
    required this.cells,
  });

  final List<DateTime> days;
  final List<AnalyticsHourlyCell> cells;
}

class AnalyticsComparisonResult {
  const AnalyticsComparisonResult({
    required this.labelA,
    required this.labelB,
    required this.summaryA,
    required this.summaryB,
    required this.changePercent,
  });

  final String labelA;
  final String labelB;
  final AnalyticsSummary summaryA;
  final AnalyticsSummary summaryB;
  final double changePercent;
}

class AnalyticsEngine {
  static AnalyticsDateRange rangeForPreset(
    AnalyticsPeriodPreset preset, {
    DateTime? customStart,
    DateTime? customEnd,
  }) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);

    switch (preset) {
      case AnalyticsPeriodPreset.today:
        return AnalyticsDateRange(
          start: todayStart,
          end: todayEnd,
          label: 'Today',
        );
      case AnalyticsPeriodPreset.yesterday:
        final start = todayStart.subtract(const Duration(days: 1));
        final end = todayStart.subtract(const Duration(seconds: 1));
        return AnalyticsDateRange(
          start: start,
          end: end,
          label: 'Yesterday',
        );
      case AnalyticsPeriodPreset.thisWeek:
        final weekday = now.weekday;
        final start = todayStart.subtract(Duration(days: weekday - 1));
        return AnalyticsDateRange(
          start: start,
          end: todayEnd,
          label: 'This Week',
        );
      case AnalyticsPeriodPreset.lastWeek:
        final weekday = now.weekday;
        final thisWeekStart = todayStart.subtract(Duration(days: weekday - 1));
        final start = thisWeekStart.subtract(const Duration(days: 7));
        final end = thisWeekStart.subtract(const Duration(seconds: 1));
        return AnalyticsDateRange(
          start: start,
          end: end,
          label: 'Last Week',
        );
      case AnalyticsPeriodPreset.thisMonth:
        final start = DateTime(now.year, now.month, 1);
        return AnalyticsDateRange(
          start: start,
          end: todayEnd,
          label: 'This Month',
        );
      case AnalyticsPeriodPreset.lastMonth:
        final firstThisMonth = DateTime(now.year, now.month, 1);
        final end = firstThisMonth.subtract(const Duration(seconds: 1));
        final start = DateTime(end.year, end.month, 1);
        return AnalyticsDateRange(
          start: start,
          end: end,
          label: 'Last Month',
        );
      case AnalyticsPeriodPreset.custom:
        final start = customStart ?? todayStart;
        final end = customEnd ?? todayEnd;
        return AnalyticsDateRange(
          start: DateTime(start.year, start.month, start.day),
          end: DateTime(end.year, end.month, end.day, 23, 59, 59, 999),
          label: 'Custom Range',
        );
    }
  }

  static List<SalesHistoryRecord> filterRecords({
    required List<SalesHistoryRecord> records,
    required AnalyticsDateRange range,
    Set<int>? branchIds,
  }) {
    return records.where((record) {
      final inRange = range.contains(record.createdAt);
      final branchId = record.branchId ?? 1;
      final inBranch = branchIds == null ||
          branchIds.isEmpty ||
          branchIds.contains(branchId);
      return inRange && inBranch;
    }).toList();
  }

  static AnalyticsSummary summarize(List<SalesHistoryRecord> records) {
    if (records.isEmpty) {
      return const AnalyticsSummary(
        totalSales: 0,
        orderCount: 0,
        itemCount: 0,
        totalDiscount: 0,
        averageTicket: 0,
        walkInOrders: 0,
        registeredOrders: 0,
      );
    }

    final totalSales =
        records.fold<double>(0, (sum, record) => sum + record.total);
    final itemCount =
        records.fold<int>(0, (sum, record) => sum + record.itemCount);
    final totalDiscount =
        records.fold<double>(0, (sum, record) => sum + record.totalDiscount);
    final walkInOrders = records.where((record) => record.isWalkIn).length;

    return AnalyticsSummary(
      totalSales: totalSales,
      orderCount: records.length,
      itemCount: itemCount,
      totalDiscount: totalDiscount,
      averageTicket: totalSales / records.length,
      walkInOrders: walkInOrders,
      registeredOrders: records.length - walkInOrders,
    );
  }

  static List<AnalyticsNamedValue> salesByCategory({
    required List<SalesHistoryRecord> records,
    required List<Product> products,
    int limit = 8,
  }) {
    final productCategory = {
      for (final product in products) product.id: product.category,
    };
    final totals = <String, double>{};

    for (final record in records) {
      for (final item in record.items) {
        final category = productCategory[item.productId] ?? 'Other';
        totals[category] = (totals[category] ?? 0) + item.total;
      }
    }

    final sorted = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted
        .take(limit)
        .map(
          (entry) => AnalyticsNamedValue(label: entry.key, value: entry.value),
        )
        .toList();
  }

  static List<AnalyticsNamedValue> bestSellers({
    required List<SalesHistoryRecord> records,
    int limit = 10,
    bool byRevenue = false,
  }) {
    final qty = <String, double>{};
    final revenue = <String, double>{};

    for (final record in records) {
      for (final item in record.items) {
        qty[item.productName] = (qty[item.productName] ?? 0) + item.quantity;
        revenue[item.productName] =
            (revenue[item.productName] ?? 0) + item.total;
      }
    }

    final names = qty.keys.toList()
      ..sort((a, b) {
        if (byRevenue) {
          return (revenue[b] ?? 0).compareTo(revenue[a] ?? 0);
        }
        return (qty[b] ?? 0).compareTo(qty[a] ?? 0);
      });

    return names
        .take(limit)
        .map(
          (name) => AnalyticsNamedValue(
            label: name,
            value: byRevenue ? (revenue[name] ?? 0) : (qty[name] ?? 0).toDouble(),
            secondary: qty[name],
          ),
        )
        .toList();
  }

  static List<AnalyticsNamedValue> salesTrend({
    required List<SalesHistoryRecord> records,
    required AnalyticsTrendGranularity granularity,
    required AnalyticsDateRange range,
  }) {
    final buckets = <String, double>{};

    for (final record in records) {
      final key = _bucketKey(record.createdAt, granularity);
      buckets[key] = (buckets[key] ?? 0) + record.total;
    }

    final keys = _bucketKeysForRange(range, granularity);
    return keys
        .map(
          (key) => AnalyticsNamedValue(
            label: key,
            value: buckets[key] ?? 0,
          ),
        )
        .toList();
  }

  static List<AnalyticsNamedValue> salesByBranch({
    required List<SalesHistoryRecord> records,
    required Map<int, String> branchNames,
  }) {
    final totals = <String, double>{};

    for (final record in records) {
      final branchId = record.branchId ?? 1;
      final label = branchNames[branchId] ?? record.branchName ?? 'Branch $branchId';
      totals[label] = (totals[label] ?? 0) + record.total;
    }

    final sorted = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted
        .map(
          (entry) => AnalyticsNamedValue(label: entry.key, value: entry.value),
        )
        .toList();
  }

  static List<AnalyticsNamedValue> paymentBreakdown(
    List<SalesHistoryRecord> records,
  ) {
    final totals = <String, double>{};
    for (final record in records) {
      final method = record.paymentMethod.trim().isEmpty
          ? 'Cash'
          : record.paymentMethod.trim();
      totals[method] = (totals[method] ?? 0) + record.total;
    }

    final sorted = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted
        .map(
          (entry) => AnalyticsNamedValue(label: entry.key, value: entry.value),
        )
        .toList();
  }

  static List<AnalyticsNamedValue> salesByCashier(
    List<SalesHistoryRecord> records,
  ) {
    final totals = <String, double>{};
    for (final record in records) {
      final name = record.cashierName?.trim();
      final label = name == null || name.isEmpty ? 'Staff' : name;
      totals[label] = (totals[label] ?? 0) + record.total;
    }

    final sorted = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted
        .map(
          (entry) => AnalyticsNamedValue(label: entry.key, value: entry.value),
        )
        .toList();
  }

  static AnalyticsHourlyGrid hourlySalesGrid({
    required List<SalesHistoryRecord> records,
    required AnalyticsDateRange range,
  }) {
    final days = <DateTime>[];
    var cursor = DateTime(range.start.year, range.start.month, range.start.day);
    final last = DateTime(range.end.year, range.end.month, range.end.day);
    while (!cursor.isAfter(last)) {
      days.add(cursor);
      cursor = cursor.add(const Duration(days: 1));
    }

    final cells = <AnalyticsHourlyCell>[];
    for (final day in days) {
      for (var hour = 0; hour < 24; hour++) {
        cells.add(
          AnalyticsHourlyCell(
            date: day,
            hour: hour,
            units: 0,
            amount: 0,
          ),
        );
      }
    }

    final index = <String, int>{};
    for (var i = 0; i < cells.length; i++) {
      final cell = cells[i];
      index['${_dateKey(cell.date)}|${cell.hour}'] = i;
    }

    for (final record in records) {
      final created = record.createdAt;
      final day = DateTime(created.year, created.month, created.day);
      final key = '${_dateKey(day)}|${created.hour}';
      final cellIndex = index[key];
      if (cellIndex == null) continue;

      var units = 0.0;
      var amount = 0.0;
      for (final item in record.items) {
        units += item.quantity;
        amount += item.total;
      }
      final existing = cells[cellIndex];
      cells[cellIndex] = AnalyticsHourlyCell(
        date: existing.date,
        hour: existing.hour,
        units: existing.units + units,
        amount: existing.amount + amount,
      );
    }

    return AnalyticsHourlyGrid(days: days, cells: cells);
  }

  static String _dateKey(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';

  static String hourLabel(int hour) {
    if (hour == 0) return '12am';
    if (hour < 12) return '${hour}am';
    if (hour == 12) return '12pm';
    return '${hour - 12}pm';
  }

  static String dayLabel(DateTime day) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[day.month - 1]} ${day.day}';
  }

  static List<AnalyticsNamedValue> customerTypeBreakdown(
    List<SalesHistoryRecord> records,
  ) {
    double walkIn = 0;
    double registered = 0;
    for (final record in records) {
      if (record.isWalkIn) {
        walkIn += record.total;
      } else {
        registered += record.total;
      }
    }
    return [
      AnalyticsNamedValue(label: 'Walk-In', value: walkIn),
      AnalyticsNamedValue(label: 'Registered', value: registered),
    ];
  }

  static AnalyticsComparisonResult comparePeriods({
    required List<SalesHistoryRecord> records,
    required AnalyticsDateRange rangeA,
    required AnalyticsDateRange rangeB,
    Set<int>? branchIds,
  }) {
    final filteredA = filterRecords(
      records: records,
      range: rangeA,
      branchIds: branchIds,
    );
    final filteredB = filterRecords(
      records: records,
      range: rangeB,
      branchIds: branchIds,
    );
    return compareSummaries(
      labelA: rangeA.label ?? 'Period A',
      labelB: rangeB.label ?? 'Period B',
      summaryA: summarize(filteredA),
      summaryB: summarize(filteredB),
    );
  }

  static AnalyticsComparisonResult compareSummaries({
    required String labelA,
    required String labelB,
    required AnalyticsSummary summaryA,
    required AnalyticsSummary summaryB,
  }) {
    final changePercent = summaryB.totalSales == 0
        ? (summaryA.totalSales > 0 ? 100.0 : 0.0)
        : ((summaryA.totalSales - summaryB.totalSales) / summaryB.totalSales) *
            100.0;

    return AnalyticsComparisonResult(
      labelA: labelA,
      labelB: labelB,
      summaryA: summaryA,
      summaryB: summaryB,
      changePercent: changePercent,
    );
  }

  /// Chart granularity is one step finer than the report period:
  /// - week-level report → daily chart
  /// - month-level report → weekly chart
  /// - longer spans → monthly chart
  static AnalyticsTrendGranularity granularityForRange(
    AnalyticsDateRange range, {
    AnalyticsPeriodPreset? preset,
  }) {
    if (preset != null && preset != AnalyticsPeriodPreset.custom) {
      switch (preset) {
        case AnalyticsPeriodPreset.today:
        case AnalyticsPeriodPreset.yesterday:
        case AnalyticsPeriodPreset.thisWeek:
        case AnalyticsPeriodPreset.lastWeek:
          return AnalyticsTrendGranularity.day;
        case AnalyticsPeriodPreset.thisMonth:
        case AnalyticsPeriodPreset.lastMonth:
          return AnalyticsTrendGranularity.week;
        case AnalyticsPeriodPreset.custom:
          break;
      }
    }

    final days = range.daySpan;
    if (days <= 14) return AnalyticsTrendGranularity.day;
    if (days <= 90) return AnalyticsTrendGranularity.week;
    return AnalyticsTrendGranularity.month;
  }

  static String chartTitleForGranularity(AnalyticsTrendGranularity granularity) {
    switch (granularity) {
      case AnalyticsTrendGranularity.day:
        return 'Daily Sales';
      case AnalyticsTrendGranularity.week:
        return 'Weekly Sales';
      case AnalyticsTrendGranularity.month:
        return 'Monthly Sales';
    }
  }

  static String rangeDescription(AnalyticsDateRange range) {
    final days = range.daySpan;
    final label = range.label ?? 'Selected range';
    if (days <= 1) return '$label (1 day)';
    if (days <= 14) return '$label ($days days)';
    if (days <= 90) return '$label (${(days / 7).ceil()} weeks)';
    final months = (days / 30).ceil();
    return '$label (~$months months)';
  }

  static AnalyticsComparisonResult compareBranches({
    required List<SalesHistoryRecord> records,
    required AnalyticsDateRange range,
    required int branchIdA,
    required int branchIdB,
    required String branchNameA,
    required String branchNameB,
  }) {
    final filteredA = filterRecords(
      records: records,
      range: range,
      branchIds: {branchIdA},
    );
    final filteredB = filterRecords(
      records: records,
      range: range,
      branchIds: {branchIdB},
    );

    return compareSummaries(
      labelA: branchNameA,
      labelB: branchNameB,
      summaryA: summarize(filteredA),
      summaryB: summarize(filteredB),
    );
  }

  static String _bucketKey(DateTime date, AnalyticsTrendGranularity granularity) {
    switch (granularity) {
      case AnalyticsTrendGranularity.day:
        return '${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';
      case AnalyticsTrendGranularity.week:
        final monday = date.subtract(Duration(days: date.weekday - 1));
        return 'Wk ${monday.month}/${monday.day}';
      case AnalyticsTrendGranularity.month:
        const months = [
          'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
          'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
        ];
        return '${months[date.month - 1]} ${date.year}';
    }
  }

  static List<String> _bucketKeysForRange(
    AnalyticsDateRange range,
    AnalyticsTrendGranularity granularity,
  ) {
    final keys = <String>[];
    var cursor = DateTime(range.start.year, range.start.month, range.start.day);
    final end = DateTime(range.end.year, range.end.month, range.end.day);

    while (!cursor.isAfter(end)) {
      final key = _bucketKey(cursor, granularity);
      if (!keys.contains(key)) keys.add(key);
      switch (granularity) {
        case AnalyticsTrendGranularity.day:
          cursor = cursor.add(const Duration(days: 1));
        case AnalyticsTrendGranularity.week:
          cursor = cursor.add(const Duration(days: 7));
        case AnalyticsTrendGranularity.month:
          cursor = DateTime(cursor.year, cursor.month + 1, 1);
      }
    }

    return keys;
  }
}
