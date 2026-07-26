import '../core/utils/format_utils.dart';

enum LoyaltyPointAction { earn, redeem, openCard, adjust, other }

class LoyaltyPointLog {
  const LoyaltyPointLog({
    required this.id,
    required this.customerId,
    required this.action,
    required this.pointsChange,
    required this.pointsBalanceAfter,
    required this.description,
    this.loyaltyCardId,
    this.orderId,
    this.orderAmount,
    this.actorUserId,
    this.actorName,
    this.createdAt,
  });

  final int id;
  final int customerId;
  final int? loyaltyCardId;
  final int? orderId;
  final LoyaltyPointAction action;
  final int pointsChange;
  final int pointsBalanceAfter;
  final double? orderAmount;
  final String description;
  final int? actorUserId;
  final String? actorName;
  final DateTime? createdAt;

  factory LoyaltyPointLog.fromJson(Map<String, dynamic> json) {
    final actionRaw = (json['action'] ?? '').toString().toLowerCase();
    final action = switch (actionRaw) {
      'earn' => LoyaltyPointAction.earn,
      'redeem' => LoyaltyPointAction.redeem,
      'open_card' => LoyaltyPointAction.openCard,
      'adjust' => LoyaltyPointAction.adjust,
      _ => LoyaltyPointAction.other,
    };

    return LoyaltyPointLog(
      id: toInt(json['id']),
      customerId: toInt(json['customer_id']),
      loyaltyCardId: json['loyalty_card_id'] == null
          ? null
          : toInt(json['loyalty_card_id']),
      orderId: json['order_id'] == null ? null : toInt(json['order_id']),
      action: action,
      pointsChange: toInt(json['points_change']),
      pointsBalanceAfter: toInt(json['points_balance_after']),
      orderAmount: json['order_amount'] == null
          ? null
          : toDouble(json['order_amount']),
      description: (json['description'] ?? '').toString(),
      actorUserId: json['actor_user_id'] == null
          ? null
          : toInt(json['actor_user_id']),
      actorName: json['actor_name']?.toString(),
      createdAt: DateTime.tryParse((json['created_at'] ?? '').toString()),
    );
  }

  bool get isCredit => pointsChange > 0;
  bool get isDebit => pointsChange < 0;

  String get actionLabel {
    switch (action) {
      case LoyaltyPointAction.earn:
        return 'Earned';
      case LoyaltyPointAction.redeem:
        return 'Redeemed';
      case LoyaltyPointAction.openCard:
        return 'Card Opened';
      case LoyaltyPointAction.adjust:
        return 'Adjusted';
      case LoyaltyPointAction.other:
        return 'Activity';
    }
  }
}
