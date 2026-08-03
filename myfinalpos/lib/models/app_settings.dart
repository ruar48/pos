import '../core/utils/format_utils.dart';

class AppSettingsModel {
  const AppSettingsModel({
    required this.taxRate,
    required this.autoPrintReceipt,
    this.doublePrintReceipt = false,
    required this.printerHost,
    this.printerType = 'network',
    this.printerDevice = '',
    this.printerPort = 9100,
    required this.allowNegativeStock,
    this.lowStockEmailEnabled = true,
    this.lowStockEmailRecipients = '',
    required this.loyaltyEnabled,
    required this.loyaltyPointsPerUnit,
    required this.loyaltySpendUnit,
    required this.loyaltyRedeemPointsPerPeso,
    required this.currencySymbol,
    this.receiptStore,
    this.defaultBranchId,
    this.attendanceStartTime = '08:00',
    this.attendanceGraceMinutes = 15,
    this.attendanceLunchOutTime = '12:00',
    this.attendanceAfternoonInTime = '13:00',
    this.attendanceDayEndTime = '17:00',
    this.attendanceMorningAbsentAfterTime = '09:00',
    this.attendanceMorningAcceptStart = '06:30',
    this.attendanceMorningOfficialStart = '08:00',
    this.attendanceMorningGraceEnd = '08:15',
    this.attendanceMorningLateStart = '08:16',
    this.attendanceMorningCutoff = '09:00',
    this.attendanceBreakOutStart = '11:00',
    this.attendanceBreakOutEnd = '12:00',
    this.attendanceAfternoonAcceptStart = '12:50',
    this.attendanceAfternoonOnTimeEnd = '13:30',
    this.attendanceAfternoonLateStart = '13:31',
    this.attendanceAfternoonCutoff = '14:00',
    this.attendanceTimeoutStart = '16:30',
    this.settingsRevision = '0',
    this.hasCashDrawerPin = false,
    this.hasRefundPin = false,
  });

  final double taxRate;
  final bool autoPrintReceipt;
  final bool doublePrintReceipt;
  final String printerHost;
  final String printerType;
  final String printerDevice;
  final int printerPort;
  final bool allowNegativeStock;
  final bool lowStockEmailEnabled;
  final String lowStockEmailRecipients;
  final bool loyaltyEnabled;
  final int loyaltyPointsPerUnit;
  final double loyaltySpendUnit;
  final int loyaltyRedeemPointsPerPeso;
  final String currencySymbol;
  final Map<String, dynamic>? receiptStore;
  final int? defaultBranchId;
  final String attendanceStartTime;
  final int attendanceGraceMinutes;
  final String attendanceLunchOutTime;
  final String attendanceAfternoonInTime;
  final String attendanceDayEndTime;
  final String attendanceMorningAbsentAfterTime;
  final String attendanceMorningAcceptStart;
  final String attendanceMorningOfficialStart;
  final String attendanceMorningGraceEnd;
  final String attendanceMorningLateStart;
  final String attendanceMorningCutoff;
  final String attendanceBreakOutStart;
  final String attendanceBreakOutEnd;
  final String attendanceAfternoonAcceptStart;
  final String attendanceAfternoonOnTimeEnd;
  final String attendanceAfternoonLateStart;
  final String attendanceAfternoonCutoff;
  final String attendanceTimeoutStart;
  final String settingsRevision;
  final bool hasCashDrawerPin;
  final bool hasRefundPin;

  static String _timeField(
    Map<String, dynamic> json,
    String key,
    String fallback,
  ) {
    final value = json[key];
    if (value == null || value.toString().trim().isEmpty) {
      return fallback;
    }
    return value.toString();
  }

  factory AppSettingsModel.fromJson(Map<String, dynamic> json) {
    final pointsPerUnit = toInt(json['loyalty_points_per_unit']);
    final spendUnit = toDouble(json['loyalty_spend_unit']);
    final redeemPerPeso = toInt(json['loyalty_redeem_points_per_peso']);

    return AppSettingsModel(
      taxRate: toDouble(json['tax_rate']).clamp(0, 1),
      autoPrintReceipt: json['auto_print_receipt'] == true ||
          json['auto_print_receipt'].toString() == '1',
      doublePrintReceipt: json['double_print_receipt'] == true ||
          json['double_print_receipt'].toString() == '1',
      printerHost: (json['printer_host'] ?? '').toString().trim(),
      printerType: (json['printer_type'] ?? 'network').toString().trim(),
      printerDevice: (json['printer_device'] ?? '').toString().trim(),
      printerPort: json['printer_port'] == null
          ? 9100
          : toInt(json['printer_port']).clamp(1, 65535),
      allowNegativeStock: json['allow_negative_stock'] == true ||
          json['allow_negative_stock'].toString() == '1',
      lowStockEmailEnabled: json['low_stock_email_enabled'] != false &&
          json['low_stock_email_enabled'].toString() != '0',
      lowStockEmailRecipients:
          (json['low_stock_email_recipients'] ?? '').toString().trim(),
      loyaltyEnabled: json['loyalty_enabled'] == true ||
          json['loyalty_enabled'].toString() == '1',
      loyaltyPointsPerUnit: pointsPerUnit > 0 ? pointsPerUnit : 50,
      loyaltySpendUnit: spendUnit > 0 ? spendUnit : 1000,
      loyaltyRedeemPointsPerPeso: redeemPerPeso > 0 ? redeemPerPeso : 10,
      currencySymbol: (json['currency_symbol'] ?? 'PHP').toString(),
      receiptStore: json['receipt_store'] is Map<String, dynamic>
          ? Map<String, dynamic>.from(json['receipt_store'] as Map)
          : null,
      defaultBranchId: json['default_branch_id'] == null
          ? null
          : toInt(json['default_branch_id']),
      attendanceStartTime:
          (json['attendance_start_time'] ?? '08:00').toString(),
      attendanceGraceMinutes: toInt(json['attendance_grace_minutes']) > 0
          ? toInt(json['attendance_grace_minutes']).clamp(0, 120)
          : 15,
      attendanceLunchOutTime:
          (json['attendance_lunch_out_time'] ?? '12:00').toString(),
      attendanceAfternoonInTime:
          (json['attendance_afternoon_in_time'] ?? '13:00').toString(),
      attendanceDayEndTime:
          (json['attendance_day_end_time'] ?? '17:00').toString(),
      attendanceMorningAbsentAfterTime: _timeField(
        json,
        'attendance_morning_absent_after_time',
        '09:00',
      ),
      attendanceMorningAcceptStart: _timeField(
        json,
        'attendance_morning_accept_start',
        '06:30',
      ),
      attendanceMorningOfficialStart: _timeField(
        json,
        'attendance_morning_official_start',
        _timeField(json, 'attendance_start_time', '08:00'),
      ),
      attendanceMorningGraceEnd: _timeField(
        json,
        'attendance_morning_grace_end',
        '08:15',
      ),
      attendanceMorningLateStart: _timeField(
        json,
        'attendance_morning_late_start',
        '08:16',
      ),
      attendanceMorningCutoff: _timeField(
        json,
        'attendance_morning_cutoff',
        _timeField(json, 'attendance_morning_absent_after_time', '09:00'),
      ),
      attendanceBreakOutStart: _timeField(
        json,
        'attendance_break_out_start',
        '11:00',
      ),
      attendanceBreakOutEnd: _timeField(
        json,
        'attendance_break_out_end',
        _timeField(json, 'attendance_lunch_out_time', '12:00'),
      ),
      attendanceAfternoonAcceptStart: _timeField(
        json,
        'attendance_afternoon_accept_start',
        '12:50',
      ),
      attendanceAfternoonOnTimeEnd: _timeField(
        json,
        'attendance_afternoon_on_time_end',
        _timeField(json, 'attendance_afternoon_in_time', '13:30'),
      ),
      attendanceAfternoonLateStart: _timeField(
        json,
        'attendance_afternoon_late_start',
        '13:31',
      ),
      attendanceAfternoonCutoff: _timeField(
        json,
        'attendance_afternoon_cutoff',
        '14:00',
      ),
      attendanceTimeoutStart: _timeField(
        json,
        'attendance_timeout_start',
        _timeField(json, 'attendance_day_end_time', '16:30'),
      ),
      settingsRevision: (json['settings_revision'] ?? '0').toString(),
      hasCashDrawerPin: json['has_cash_drawer_pin'] == true ||
          json['has_cash_drawer_pin'].toString() == '1',
      hasRefundPin: json['has_refund_pin'] == true ||
          json['has_refund_pin'].toString() == '1',
    );
  }

  int pointsEarnedForAmount(double amount) {
    if (!loyaltyEnabled || loyaltySpendUnit <= 0 || loyaltyPointsPerUnit <= 0) {
      return 0;
    }
    if (amount <= 0) return 0;
    return (amount / loyaltySpendUnit * loyaltyPointsPerUnit).floor();
  }

  double pesoValueForPoints(int points) {
    if (loyaltyRedeemPointsPerPeso <= 0 || points <= 0) return 0;
    return points / loyaltyRedeemPointsPerPeso;
  }

  String loyaltyEarnSummary(String currencySymbol) {
    final spend = formatMoney(currencySymbol, loyaltySpendUnit);
    return '$loyaltyPointsPerUnit pts per $spend spent';
  }

  AppSettingsModel copyWith({
    double? taxRate,
    bool? autoPrintReceipt,
    bool? doublePrintReceipt,
    String? printerHost,
    String? printerType,
    String? printerDevice,
    int? printerPort,
    bool? allowNegativeStock,
    bool? lowStockEmailEnabled,
    String? lowStockEmailRecipients,
    bool? loyaltyEnabled,
    int? loyaltyPointsPerUnit,
    double? loyaltySpendUnit,
    int? loyaltyRedeemPointsPerPeso,
    String? currencySymbol,
    Map<String, dynamic>? receiptStore,
    int? defaultBranchId,
    String? attendanceStartTime,
    int? attendanceGraceMinutes,
    String? attendanceLunchOutTime,
    String? attendanceAfternoonInTime,
    String? attendanceDayEndTime,
    String? attendanceMorningAbsentAfterTime,
    String? attendanceMorningAcceptStart,
    String? attendanceMorningOfficialStart,
    String? attendanceMorningGraceEnd,
    String? attendanceMorningLateStart,
    String? attendanceMorningCutoff,
    String? attendanceBreakOutStart,
    String? attendanceBreakOutEnd,
    String? attendanceAfternoonAcceptStart,
    String? attendanceAfternoonOnTimeEnd,
    String? attendanceAfternoonLateStart,
    String? attendanceAfternoonCutoff,
    String? attendanceTimeoutStart,
    String? settingsRevision,
    bool? hasCashDrawerPin,
    bool? hasRefundPin,
  }) {
    return AppSettingsModel(
      taxRate: taxRate ?? this.taxRate,
      autoPrintReceipt: autoPrintReceipt ?? this.autoPrintReceipt,
      doublePrintReceipt: doublePrintReceipt ?? this.doublePrintReceipt,
      printerHost: printerHost ?? this.printerHost,
      printerType: printerType ?? this.printerType,
      printerDevice: printerDevice ?? this.printerDevice,
      printerPort: printerPort ?? this.printerPort,
      allowNegativeStock: allowNegativeStock ?? this.allowNegativeStock,
      lowStockEmailEnabled:
          lowStockEmailEnabled ?? this.lowStockEmailEnabled,
      lowStockEmailRecipients:
          lowStockEmailRecipients ?? this.lowStockEmailRecipients,
      loyaltyEnabled: loyaltyEnabled ?? this.loyaltyEnabled,
      loyaltyPointsPerUnit: loyaltyPointsPerUnit ?? this.loyaltyPointsPerUnit,
      loyaltySpendUnit: loyaltySpendUnit ?? this.loyaltySpendUnit,
      loyaltyRedeemPointsPerPeso:
          loyaltyRedeemPointsPerPeso ?? this.loyaltyRedeemPointsPerPeso,
      currencySymbol: currencySymbol ?? this.currencySymbol,
      receiptStore: receiptStore ?? this.receiptStore,
      defaultBranchId: defaultBranchId ?? this.defaultBranchId,
      attendanceStartTime: attendanceStartTime ?? this.attendanceStartTime,
      attendanceGraceMinutes:
          attendanceGraceMinutes ?? this.attendanceGraceMinutes,
      attendanceLunchOutTime:
          attendanceLunchOutTime ?? this.attendanceLunchOutTime,
      attendanceAfternoonInTime:
          attendanceAfternoonInTime ?? this.attendanceAfternoonInTime,
      attendanceDayEndTime: attendanceDayEndTime ?? this.attendanceDayEndTime,
      attendanceMorningAbsentAfterTime: attendanceMorningAbsentAfterTime ??
          this.attendanceMorningAbsentAfterTime,
      attendanceMorningAcceptStart:
          attendanceMorningAcceptStart ?? this.attendanceMorningAcceptStart,
      attendanceMorningOfficialStart: attendanceMorningOfficialStart ??
          this.attendanceMorningOfficialStart,
      attendanceMorningGraceEnd:
          attendanceMorningGraceEnd ?? this.attendanceMorningGraceEnd,
      attendanceMorningLateStart:
          attendanceMorningLateStart ?? this.attendanceMorningLateStart,
      attendanceMorningCutoff:
          attendanceMorningCutoff ?? this.attendanceMorningCutoff,
      attendanceBreakOutStart:
          attendanceBreakOutStart ?? this.attendanceBreakOutStart,
      attendanceBreakOutEnd:
          attendanceBreakOutEnd ?? this.attendanceBreakOutEnd,
      attendanceAfternoonAcceptStart: attendanceAfternoonAcceptStart ??
          this.attendanceAfternoonAcceptStart,
      attendanceAfternoonOnTimeEnd:
          attendanceAfternoonOnTimeEnd ?? this.attendanceAfternoonOnTimeEnd,
      attendanceAfternoonLateStart:
          attendanceAfternoonLateStart ?? this.attendanceAfternoonLateStart,
      attendanceAfternoonCutoff:
          attendanceAfternoonCutoff ?? this.attendanceAfternoonCutoff,
      attendanceTimeoutStart:
          attendanceTimeoutStart ?? this.attendanceTimeoutStart,
      settingsRevision: settingsRevision ?? this.settingsRevision,
      hasCashDrawerPin: hasCashDrawerPin ?? this.hasCashDrawerPin,
      hasRefundPin: hasRefundPin ?? this.hasRefundPin,
    );
  }
}
