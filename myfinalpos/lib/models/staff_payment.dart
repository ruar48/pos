import '../core/utils/format_utils.dart';

enum StaffPaymentType {
  salary,
  commission,
  bonus,
  allowance,
  unknown;

  static StaffPaymentType parse(String value) {
    return switch (value.toLowerCase().trim()) {
      'salary' => StaffPaymentType.salary,
      'commission' => StaffPaymentType.commission,
      'bonus' => StaffPaymentType.bonus,
      'allowance' => StaffPaymentType.allowance,
      _ => StaffPaymentType.unknown,
    };
  }

  String get label => switch (this) {
        StaffPaymentType.salary => 'Salary',
        StaffPaymentType.commission => 'Commission',
        StaffPaymentType.bonus => 'Bonus',
        StaffPaymentType.allowance => 'Allowance',
        StaffPaymentType.unknown => 'Payment',
      };

  String get apiValue => switch (this) {
        StaffPaymentType.salary => 'salary',
        StaffPaymentType.commission => 'commission',
        StaffPaymentType.bonus => 'bonus',
        StaffPaymentType.allowance => 'allowance',
        StaffPaymentType.unknown => 'salary',
      };
}

class StaffPayment {
  const StaffPayment({
    required this.id,
    required this.userId,
    required this.staffName,
    this.branchId,
    this.branchName,
    required this.amount,
    required this.paymentType,
    this.periodStart,
    this.periodEnd,
    this.notes,
    this.paidByUserId,
    this.paidByName,
    this.createdAt,
  });

  final int id;
  final int userId;
  final String staffName;
  final int? branchId;
  final String? branchName;
  final double amount;
  final String paymentType;
  final DateTime? periodStart;
  final DateTime? periodEnd;
  final String? notes;
  final int? paidByUserId;
  final String? paidByName;
  final DateTime? createdAt;

  StaffPaymentType get type => StaffPaymentType.parse(paymentType);

  String get typeLabel => type.label;

  factory StaffPayment.fromJson(Map<String, dynamic> json) {
    return StaffPayment(
      id: toInt(json['id']),
      userId: toInt(json['user_id']),
      staffName: (json['staff_name'] ?? '').toString(),
      branchId: json['branch_id'] == null ? null : toInt(json['branch_id']),
      branchName: json['branch_name']?.toString(),
      amount: toDouble(json['amount']),
      paymentType: (json['payment_type'] ?? 'salary').toString(),
      periodStart: json['period_start'] == null
          ? null
          : DateTime.tryParse(json['period_start'].toString()),
      periodEnd: json['period_end'] == null
          ? null
          : DateTime.tryParse(json['period_end'].toString()),
      notes: json['notes']?.toString(),
      paidByUserId: json['paid_by_user_id'] == null
          ? null
          : toInt(json['paid_by_user_id']),
      paidByName: json['paid_by_name']?.toString(),
      createdAt: json['created_at'] == null
          ? null
          : DateTime.tryParse(json['created_at'].toString()),
    );
  }
}
