import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:myfinalpos/features/receipt/receipt_printer.dart';
import 'package:myfinalpos/features/transactions/refund_dialog.dart';
import 'package:myfinalpos/features/transactions/transaction_model.dart';
import 'package:myfinalpos/features/transactions/transaction_service.dart';
import 'package:myfinalpos/features/transactions/transactions_screen.dart';
import 'package:myfinalpos/models/refund_item_request.dart';

Map<String, dynamic> _orderJson(
  int id, {
  String createdAt = '2026-10-23 10:00:00',
  double refundedQty = 0,
  double refunded = 0,
}) =>
    {
      'id': id,
      'customer_name': 'Juan Farmer',
      'payment_method': 'Cash',
      'created_at': createdAt,
      'subtotal': 500,
      'discount_amount': 0,
      'vat': 0,
      'total_amount': 500,
      'refunded_amount': refunded,
      'items': [
        {
          'id': id * 10,
          'product_name': 'RICE',
          'quantity': 2.5,
          'refunded_quantity': refundedQty,
          'price': 200,
          'total': 500,
        },
      ],
    };

class _FakeTransactionService extends TransactionService {
  _FakeTransactionService() : super('http://localhost');

  List<Map<String, dynamic>> recent = [];
  final Map<int, Map<String, dynamic>> byId = {};
  Completer<TransactionApiResult>? pendingRefund;
  int refundCalls = 0;

  @override
  Future<List<TransactionRecord>> fetchTransactions({
    DateTime? from,
    int? orderId,
  }) async {
    if (orderId != null) {
      final json = byId[orderId];
      return json == null ? [] : [TransactionRecord.fromJson(json)];
    }
    return recent.map(TransactionRecord.fromJson).toList();
  }

  @override
  Future<TransactionApiResult> processRefund({
    required int orderId,
    required String reason,
    required String refundType,
    required List<RefundItemRequest> items,
    int? actorUserId,
    String? refundPin,
  }) {
    refundCalls++;
    pendingRefund = Completer<TransactionApiResult>();
    return pendingRefund!.future;
  }
}

void main() {
  group('process_refund.php reply', () {
    test('success carries the give-back amount', () {
      final result = TransactionService.refundResultFromResponse(
        200,
        '{"success":true,"refund_amount":1080,"order_status":"partial_refund",'
            '"message":"Refund processed. Give back ₱1,080.00 to the '
            'customer. 1 unit(s) returned to inventory."}',
      );

      expect(result.success, isTrue);
      expect(result.refundAmount, 1080);
      expect(result.message, contains('Give back ₱1,080.00'));
    });

    test('success without a message still says how much to give back', () {
      final result = TransactionService.refundResultFromResponse(
        200,
        '{"success":true,"refund_amount":"540.5"}',
      );

      expect(result.refundAmount, 540.5);
      expect(result.message, contains('₱540.50'));
    });

    test('an HTML gateway error does not throw and warns to check the order',
        () {
      final result = TransactionService.refundResultFromResponse(
        504,
        '<html><body><h1>504 Gateway Time-out</h1></body></html>',
      );

      expect(result.success, isFalse);
      expect(result.refundAmount, isNull);
      expect(result.message, contains('HTTP 504'));
      expect(result.message, contains('check the order'));
    });

    test('a server validation error is shown as sent', () {
      final result = TransactionService.refundResultFromResponse(
        400,
        '{"success":false,"message":"Refund quantity exceeds remaining for '
            'item #30"}',
      );

      expect(result.success, isFalse);
      expect(result.message, 'Refund quantity exceeds remaining for item #30');
    });
  });

  group('refund quantity', () {
    test('defaults to one unit, or the remainder when under one', () {
      expect(defaultRefundQuantity(2.5), 1);
      expect(defaultRefundQuantity(12), 1);
      expect(defaultRefundQuantity(0.5), 0.5);
      expect(defaultRefundQuantity(0.4999999), 0.5);
      expect(defaultRefundQuantity(0), 0);
    });

    test('is clamped to (0, remaining] at 3 decimals', () {
      expect(clampRefundQuantity(0.75, 2.5), 0.75);
      expect(clampRefundQuantity(3, 2.5), 2.5);
      expect(clampRefundQuantity(0.12345, 2), 0.123);
      expect(clampRefundQuantity(0, 2.5), isNull);
      expect(clampRefundQuantity(-1, 2.5), isNull);
      expect(clampRefundQuantity(0.0001, 2.5), isNull);
      expect(clampRefundQuantity(null, 2.5), isNull);
      expect(clampRefundQuantity(1, 0), isNull);
    });

    test('typed decimals are accepted', () {
      expect(parseRefundQuantity('1.5', 2.5), 1.5);
      expect(parseRefundQuantity('.25', 1), 0.25);
      expect(parseRefundQuantity(' 2 ', 2.5), 2);
      expect(parseRefundQuantity('9', 2.5), 2.5);
      expect(parseRefundQuantity('', 2.5), isNull);
      expect(parseRefundQuantity('abc', 2.5), isNull);
    });
  });

  group('refundability goes by units, like the server', () {
    TransactionRecord order({
      required double paidRefunded,
      required double freeRefunded,
    }) =>
        TransactionRecord.fromJson({
          'id': 9,
          'created_at': '2026-10-23 10:00:00',
          'subtotal': 100,
          'total_amount': 100,
          'refunded_amount': paidRefunded > 0 ? 100 : 0,
          'items': [
            {
              'id': 1,
              'product_name': 'FEEDS',
              'quantity': 1,
              'refunded_quantity': paidRefunded,
              'price': 100,
              'total': 100,
            },
            {
              'id': 2,
              'product_name': 'FREE SCOOP',
              'quantity': 1,
              'refunded_quantity': freeRefunded,
              'price': 0,
              'total': 0,
            },
          ],
        });

    test('money fully refunded but a free unit left is still refundable', () {
      final o = order(paidRefunded: 1, freeRefunded: 0);
      expect(o.refundedAmount >= o.grandTotal, isTrue);
      expect(o.hasRefundableItems, isTrue);
      expect(o.isFullyRefunded, isFalse);
      expect(o.hasAnyRefund, isTrue);
    });

    test('every unit back means fully refunded', () {
      final o = order(paidRefunded: 1, freeRefunded: 1);
      expect(o.hasRefundableItems, isFalse);
      expect(o.isFullyRefunded, isTrue);
    });

    test('float noise does not leave a phantom refundable sliver', () {
      final item = TransactionItem.fromJson({
        'id': 1,
        'quantity': 2.5,
        'refunded_quantity': 2.4999999,
        'price': 100,
        'total': 250,
      });
      expect(item.hasRefundableQuantity, isFalse);
      expect(item.remainingQuantity, 0);
    });
  });

  group('reprint', () {
    Map<String, dynamic> splitOrder({List<Map<String, dynamic>>? payments}) => {
          'id': 4512,
          'customer_name': 'Juan Farmer',
          'payment_method': 'Split (Cash + GCash)',
          'created_at': '2026-10-23 10:00:00',
          'subtotal': 560,
          'discount_amount': 0,
          'vat': 0,
          'total_amount': 560,
          'items': [
            {
              'id': 1,
              'product_name': 'FEEDS',
              'quantity': 2,
              'price': 280,
              'total': 560,
            },
          ],
          'payments': payments ??
              [
                {'payment_method': 'Cash', 'amount': 300, 'reference': null},
                {
                  'payment_method': 'GCash',
                  'amount': 260,
                  'reference': 'GC-778899',
                },
              ],
        };

    test('split payments keep each method amount and reference', () {
      final receipt = TransactionService('http://localhost')
          .buildReceiptData(TransactionRecord.fromJson(splitOrder()));

      expect(receipt.hasSplitPayments, isTrue);
      expect(receipt.splitPayments!.length, 2);
      expect(receipt.splitPayments![1].paymentMethod, 'GCash');
      expect(receipt.splitPayments![1].amount, 260);
      expect(receipt.splitPayments![1].reference, 'GC-778899');

      final lines = ThermalReceiptLayout(receipt).buildLines();
      expect(
        lines.any((l) => l.startsWith('GCash') && l.contains('260.00')),
        isTrue,
      );
      expect(
        lines.any((l) => l.startsWith('Cash') && l.contains('300.00')),
        isTrue,
      );
      expect(lines.any((l) => l.contains('GC-778899')), isTrue);
    });

    test('a single-method sale is not printed as split', () {
      final json = splitOrder(
        payments: [
          {'payment_method': 'Cash', 'amount': 560},
        ],
      )..['payment_method'] = 'Cash';
      final receipt = TransactionService('http://localhost')
          .buildReceiptData(TransactionRecord.fromJson(json));

      expect(receipt.splitPayments, isNull);
    });
  });

  group('TransactionState', () {
    test('a second refund while one is in flight is refused', () async {
      final service = _FakeTransactionService()
        ..recent = [_orderJson(100)];
      final state = TransactionState(service: service, actorUserId: 1);
      await state.loadTransactions();

      final first = state.refundSelectedTransaction(
        orderId: 100,
        reason: 'Wrong item',
        refundType: 'items',
        items: const [RefundItemRequest(orderItemId: 1000, quantity: 1)],
      );
      expect(state.isRefunding, isTrue);

      final second = await state.refundSelectedTransaction(
        orderId: 100,
        reason: 'Wrong item',
        refundType: 'items',
        items: const [RefundItemRequest(orderItemId: 1000, quantity: 1)],
      );
      expect(second.success, isFalse);
      expect(service.refundCalls, 1);

      service.recent = [_orderJson(100, refundedQty: 1, refunded: 200)];
      service.pendingRefund!.complete(
        const TransactionApiResult(
          success: true,
          message: 'Refund processed.',
          refundAmount: 200,
        ),
      );
      final result = await first;

      expect(result.refundAmount, 200);
      // The order was reloaded before the next refund is allowed.
      expect(state.isRefunding, isFalse);
      expect(state.selectedTransaction!.items.single.refundedQuantity, 1);
    });

    test(
      'an older receipt found by search survives a refund and Refresh, '
      'and stays selected',
      () async {
        final service = _FakeTransactionService()
          ..recent = [_orderJson(100)]
          ..byId[5] = _orderJson(5, createdAt: '2026-01-04 08:00:00');
        final state = TransactionState(service: service, actorUserId: 1);
        await state.loadTransactions();

        state.setQuery('INV-000005');
        await Future<void>.delayed(const Duration(milliseconds: 750));
        expect(state.transactions.map((t) => t.id), contains(5));
        expect(state.selectedTransaction?.id, 5);

        final refund = state.refundSelectedTransaction(
          reason: 'Wrong item',
          refundType: 'items',
          items: const [RefundItemRequest(orderItemId: 50, quantity: 1)],
        );
        service.byId[5] =
            _orderJson(5, createdAt: '2026-01-04 08:00:00', refundedQty: 1);
        service.pendingRefund!.complete(
          const TransactionApiResult(success: true, message: 'ok'),
        );
        await refund;

        expect(state.transactions.map((t) => t.id), contains(5));
        expect(state.selectedTransaction?.id, 5);
        expect(state.selectedTransaction!.items.single.refundedQuantity, 1);

        await state.refresh();
        expect(state.transactions.map((t) => t.id), containsAll([100, 5]));
        expect(state.selectedTransaction?.id, 5);
      },
    );

    test('a failed load is reported, not shown as an empty list', () async {
      final state = TransactionState(
        service: _ThrowingService(),
        actorUserId: 1,
      );
      await state.loadTransactions();

      expect(state.transactions, isEmpty);
      expect(state.errorMessage, 'The server took too long to answer.');
    });
  });
}

class _ThrowingService extends TransactionService {
  _ThrowingService() : super('http://localhost');

  @override
  Future<List<TransactionRecord>> fetchTransactions({
    DateTime? from,
    int? orderId,
  }) async {
    throw TimeoutException('slow');
  }
}
