import 'package:flutter_test/flutter_test.dart';
import 'package:myfinalpos/features/management/widgets/frontend_dashboard_widgets.dart';
import 'package:myfinalpos/features/management/widgets/settings_management_widgets.dart';
import 'package:myfinalpos/models/app_settings.dart';
import 'package:myfinalpos/models/sales_history_record.dart';

const _current = AppSettingsModel(
  taxRate: 0.12,
  autoPrintReceipt: false,
  printerHost: '',
  allowNegativeStock: false,
  loyaltyEnabled: true,
  loyaltyPointsPerUnit: 50,
  loyaltySpendUnit: 1000,
  loyaltyRedeemPointsPerPeso: 10,
  currencySymbol: '₱',
);

({SettingsNumbers? values, String? error}) validate({
  String tax = '12.00',
  String points = '50',
  String spend = '1000',
  String redeem = '10',
  bool loyaltyEnabled = true,
}) {
  return validateSettingsNumbers(
    taxRatePercent: tax,
    loyaltyPointsPerUnit: points,
    loyaltySpendUnit: spend,
    loyaltyRedeemPointsPerPeso: redeem,
    loyaltyEnabled: loyaltyEnabled,
    current: _current,
  );
}

SalesHistoryRecord _sale(String createdAt, double total, {double refunded = 0}) {
  return SalesHistoryRecord.fromOrderJson({
    'id': createdAt.hashCode,
    'total_amount': total,
    'subtotal': total,
    'vat': 0,
    'refunded_amount': refunded,
    'created_at': createdAt,
    'items': const [],
  });
}

void main() {
  group('validateSettingsNumbers', () {
    test('valid input is parsed', () {
      final result = validate(tax: '12', points: '0', spend: '250.50', redeem: '1');
      expect(result.error, isNull);
      expect(result.values!.taxRate, closeTo(0.12, 1e-12));
      expect(result.values!.loyaltyPointsPerUnit, 0);
      expect(result.values!.loyaltySpendUnit, 250.5);
      expect(result.values!.loyaltyRedeemPointsPerPeso, 1);
    });

    test('0% tax is allowed when typed explicitly', () {
      expect(validate(tax: '0').values!.taxRate, 0);
    });

    test('blank or out-of-range tax blocks the save', () {
      for (final tax in ['', '  ', '100.01', 'abc', '.']) {
        final result = validate(tax: tax);
        expect(result.values, isNull, reason: 'tax "$tax"');
        expect(result.error!.toLowerCase(), contains('tax'));
      }
    });

    test('blank loyalty fields block the save instead of becoming 0', () {
      expect(validate(spend: '').values, isNull);
      expect(validate(spend: '0').values, isNull);
      expect(validate(spend: '0.00').values, isNull);
      expect(validate(points: '').values, isNull);
      expect(validate(redeem: '').values, isNull);
      expect(validate(redeem: '0').values, isNull);
      expect(validate(spend: '').error, contains('Spend amount'));
      expect(validate(redeem: '0').error, contains('₱1.00'));
    });

    test('with loyalty off, hidden unusable fields keep the saved values', () {
      final result = validate(
        spend: '',
        points: '',
        redeem: '0',
        loyaltyEnabled: false,
      );
      expect(result.error, isNull);
      expect(result.values!.loyaltySpendUnit, 1000);
      expect(result.values!.loyaltyPointsPerUnit, 50);
      expect(result.values!.loyaltyRedeemPointsPerPeso, 10);
    });
  });

  group('dashboard 7-day chart', () {
    test('days run oldest first and cross month/year boundaries', () {
      final days = recentDashboardDays(DateTime(2026, 1, 3, 15));
      expect(days.first, DateTime(2025, 12, 28));
      expect(days.last, DateTime(2026, 1, 3));
      expect(days, hasLength(7));
    });

    test('same MM/DD of an earlier year is not merged in, refunds are net', () {
      final days = recentDashboardDays(DateTime(2026, 10, 23, 9));
      final totals = recentDayNetTotals([
        _sale('2026-10-23 08:00:00', 500),
        _sale('2025-10-23 08:00:00', 9999),
        _sale('2026-10-22 08:00:00', 300, refunded: 100),
        _sale('2026-10-21 08:00:00', 300, refunded: 300),
      ], days);
      expect(totals.last, 500);
      expect(totals[5], 200);
      expect(totals[4], 0);
    });
  });
}
