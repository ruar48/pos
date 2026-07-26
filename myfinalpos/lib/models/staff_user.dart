import '../core/utils/format_utils.dart';

enum UserRole {
  admin,
  cashier,
  labor,
  unknown;

  static UserRole parse(String role) {
    final normalized = role.toLowerCase().trim().replaceAll(' ', '_');
    if (normalized.contains('super') ||
        normalized.contains('admin') ||
        normalized.contains('manager')) {
      return UserRole.admin;
    }
    if (normalized.contains('labor') || normalized.contains('worker')) {
      return UserRole.labor;
    }
    if (normalized.contains('cashier')) return UserRole.cashier;
    return UserRole.unknown;
  }

  String get label => switch (this) {
        UserRole.admin => 'Admin',
        UserRole.cashier => 'Cashier',
        UserRole.labor => 'Labor',
        UserRole.unknown => 'Staff',
      };

  String get apiValue => switch (this) {
        UserRole.admin => 'admin',
        UserRole.cashier => 'cashier',
        UserRole.labor => 'labor',
        UserRole.unknown => 'cashier',
      };

  bool get requiresLoginAccount =>
      this == UserRole.admin || this == UserRole.cashier;
}

class StaffUser {
  const StaffUser({
    required this.id,
    required this.fullName,
    required this.username,
    required this.email,
    required this.role,
    this.branchId,
    this.branchName,
    this.isActive = true,
    this.createdAt,
  });

  final int id;
  final String fullName;
  final String username;
  final String email;
  final String role;
  final int? branchId;
  final String? branchName;
  final bool isActive;
  final DateTime? createdAt;

  UserRole get userRole => UserRole.parse(role);

  String get roleLabel => userRole.label;

  bool get isLabor => userRole == UserRole.labor;

  bool get canLogin => userRole.requiresLoginAccount;

  String get branchLabel =>
      branchName?.trim().isNotEmpty == true ? branchName! : 'Unassigned';

  factory StaffUser.fromJson(Map<String, dynamic> json) {
    return StaffUser(
      id: toInt(json['id']),
      fullName: (json['full_name'] ?? '').toString(),
      username: (json['username'] ?? '').toString(),
      email: (json['email'] ?? '').toString(),
      role: (json['role'] ?? '').toString(),
      branchId: json['branch_id'] == null ? null : toInt(json['branch_id']),
      branchName: json['branch_name']?.toString(),
      isActive: json['status'] == true || json['status'].toString() == '1',
      createdAt: json['created_at'] == null
          ? null
          : DateTime.tryParse(json['created_at'].toString()),
    );
  }
}
