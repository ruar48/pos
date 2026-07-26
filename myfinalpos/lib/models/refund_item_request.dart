class RefundItemRequest {
  const RefundItemRequest({
    required this.orderItemId,
    required this.quantity,
  });

  final int orderItemId;
  final int quantity;

  Map<String, dynamic> toJson() => {
        'order_item_id': orderItemId,
        'quantity': quantity,
      };
}
