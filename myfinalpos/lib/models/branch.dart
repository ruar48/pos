import '../core/utils/format_utils.dart';

class Branch {
  const Branch({
    required this.id,
    required this.name,
    this.code,
    this.location,
    this.isActive = true,
  });

  final int id;
  final String name;
  final String? code;
  final String? location;
  final bool isActive;

  factory Branch.fromJson(Map<String, dynamic> json) {
    return Branch(
      id: toInt(json['id']),
      name: (json['name'] ?? 'Branch').toString(),
      code: json['code']?.toString(),
      location: json['location']?.toString(),
      isActive: json['is_active'] == true || json['is_active'].toString() == '1',
    );
  }

  static const mainBranch = Branch(
    id: 1,
    name: 'Main Branch',
    code: 'MAIN',
    location: 'Head Office',
  );
}
