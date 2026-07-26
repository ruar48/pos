import '../core/utils/format_utils.dart';
import 'staff_user.dart';

class AppUser {
  const AppUser({
    required this.id,
    required this.fullName,
    required this.username,
    required this.email,
    required this.role,
  });

  final int id;
  final String fullName;
  final String username;
  final String email;
  final String role;

  UserRole get userRole => UserRole.parse(role);

  String get roleLabel => userRole.label;

  bool get canAccessSuperAdmin => userRole == UserRole.admin;

  bool get canManageOperations => userRole == UserRole.admin;

  bool get canAccessReports => userRole == UserRole.admin;

  bool get canManageSettings => userRole == UserRole.admin;

  bool get canMonitorAllBranches => userRole == UserRole.admin;

  bool get isCashier => userRole == UserRole.cashier;

  bool get isLabor => userRole == UserRole.labor;

  bool get canLogin => userRole.requiresLoginAccount;

  factory AppUser.fromJson(Map<String, dynamic> json) {
    final email = (json['email'] ?? '').toString();
    final username = (json['username'] ?? '').toString().trim();
    return AppUser(
      id: toInt(json['id']),
      fullName: (json['full_name'] ?? '').toString(),
      username: username.isNotEmpty
          ? username
          : email.contains('@')
              ? email.split('@').first
              : email,
      email: email,
      role: (json['role'] ?? '').toString(),
    );
  }
}
