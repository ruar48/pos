import '../core/utils/format_utils.dart';

class AuditLogEntry {
  const AuditLogEntry({
    required this.id,
    required this.action,
    required this.module,
    required this.entityType,
    required this.description,
    this.userId,
    this.userName,
    this.userEmail,
    this.entityId,
    this.payloadJson,
    this.createdAt,
  });

  final int id;
  final int? userId;
  final String? userName;
  final String? userEmail;
  final String action;
  final String module;
  final String entityType;
  final int? entityId;
  final String description;
  final String? payloadJson;
  final DateTime? createdAt;

  String get actorLabel {
    if (userName != null && userName!.trim().isNotEmpty) return userName!;
    if (userEmail != null && userEmail!.trim().isNotEmpty) return userEmail!;
    return 'System';
  }

  factory AuditLogEntry.fromJson(Map<String, dynamic> json) {
    return AuditLogEntry(
      id: toInt(json['id']),
      userId: json['user_id'] == null ? null : toInt(json['user_id']),
      userName: json['user_name']?.toString(),
      userEmail: json['user_email']?.toString(),
      action: (json['action'] ?? '').toString(),
      module: (json['module'] ?? '').toString(),
      entityType: (json['entity_type'] ?? '').toString(),
      entityId: json['entity_id'] == null ? null : toInt(json['entity_id']),
      description: (json['description'] ?? '').toString(),
      payloadJson: json['payload_json']?.toString(),
      createdAt: json['created_at'] == null
          ? null
          : DateTime.tryParse(json['created_at'].toString()),
    );
  }
}
