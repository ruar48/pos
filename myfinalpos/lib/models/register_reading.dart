/// An X or Z reading returned by the register-readings endpoint.
///
/// X is interim and changes nothing. Z closes the shift, increments the
/// terminal's Z counter and rolls the shift into the accumulated grand total
/// that must never reset.
class RegisterReading {
  const RegisterReading({
    required this.id,
    required this.terminalId,
    required this.type,
    required this.businessDate,
    required this.beginningGrandTotal,
    required this.endingGrandTotal,
    required this.grossSales,
    required this.netSales,
    required this.vatableSales,
    required this.vatAmount,
    required this.vatExemptSales,
    required this.zeroRatedSales,
    required this.discountTotal,
    required this.scDiscount,
    required this.pwdDiscount,
    required this.naacDiscount,
    required this.soloParentDiscount,
    required this.otherDiscount,
    required this.refundAmount,
    required this.refundCount,
    required this.voidAmount,
    required this.voidCount,
    required this.transactionCount,
    required this.paymentBreakdown,
    required this.uncapturedFields,
    this.zCounter,
    this.resetCounter = 0,
    this.beginningOr,
    this.endingOr,
    this.coversFrom,
    this.coversTo,
  });

  final int id;
  final String terminalId;

  /// 'x' or 'z'.
  final String type;
  final String businessDate;

  final int? zCounter;
  final int resetCounter;

  final String? beginningOr;
  final String? endingOr;
  final String? coversFrom;
  final String? coversTo;

  final double beginningGrandTotal;
  final double endingGrandTotal;

  final double grossSales;
  final double netSales;
  final double vatableSales;
  final double vatAmount;
  final double vatExemptSales;
  final double zeroRatedSales;

  final double discountTotal;
  final double scDiscount;
  final double pwdDiscount;
  final double naacDiscount;
  final double soloParentDiscount;
  final double otherDiscount;

  final double refundAmount;
  final int refundCount;
  final double voidAmount;
  final int voidCount;
  final int transactionCount;

  final Map<String, double> paymentBreakdown;

  /// BIR figures the point of sale cannot source yet. Anything listed here is
  /// shown as "not captured" rather than as 0.00 — printing zero would assert
  /// that no such sales happened, which is a different claim.
  final List<String> uncapturedFields;

  bool get isZ => type.toLowerCase() == 'z';

  bool isUncaptured(String field) => uncapturedFields.contains(field);

  static double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  static int _toInt(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  factory RegisterReading.fromJson(Map<String, dynamic> json) {
    final payments = <String, double>{};
    final rawPayments = json['payment_breakdown'];
    if (rawPayments is Map) {
      rawPayments.forEach((key, value) {
        payments[key.toString()] = _toDouble(value);
      });
    }

    final uncaptured = <String>[];
    final rawUncaptured = json['uncaptured_fields'];
    if (rawUncaptured is List) {
      for (final field in rawUncaptured) {
        uncaptured.add(field.toString());
      }
    }

    return RegisterReading(
      id: _toInt(json['id']),
      terminalId: json['terminal_id']?.toString() ?? '',
      type: json['type']?.toString() ?? 'x',
      businessDate: json['business_date']?.toString() ?? '',
      zCounter: json['z_counter'] == null ? null : _toInt(json['z_counter']),
      resetCounter: _toInt(json['reset_counter']),
      beginningOr: json['beginning_or']?.toString(),
      endingOr: json['ending_or']?.toString(),
      coversFrom: json['covers_from']?.toString(),
      coversTo: json['covers_to']?.toString(),
      beginningGrandTotal: _toDouble(json['beginning_grand_total']),
      endingGrandTotal: _toDouble(json['ending_grand_total']),
      grossSales: _toDouble(json['gross_sales']),
      netSales: _toDouble(json['net_sales']),
      vatableSales: _toDouble(json['vatable_sales']),
      vatAmount: _toDouble(json['vat_amount']),
      vatExemptSales: _toDouble(json['vat_exempt_sales']),
      zeroRatedSales: _toDouble(json['zero_rated_sales']),
      discountTotal: _toDouble(json['discount_total']),
      scDiscount: _toDouble(json['sc_discount']),
      pwdDiscount: _toDouble(json['pwd_discount']),
      naacDiscount: _toDouble(json['naac_discount']),
      soloParentDiscount: _toDouble(json['solo_parent_discount']),
      otherDiscount: _toDouble(json['other_discount']),
      refundAmount: _toDouble(json['refund_amount']),
      refundCount: _toInt(json['refund_count']),
      voidAmount: _toDouble(json['void_amount']),
      voidCount: _toInt(json['void_count']),
      transactionCount: _toInt(json['transaction_count']),
      paymentBreakdown: payments,
      uncapturedFields: uncaptured,
    );
  }
}

/// The open shift on a terminal, plus its BIR counters.
class RegisterSessionStatus {
  const RegisterSessionStatus({
    required this.terminalId,
    required this.isOpen,
    required this.grandTotalAccumulated,
    required this.zCounter,
    required this.resetCounter,
    this.sessionId,
    this.openedAt,
    this.businessDate,
    this.openingCash = 0,
  });

  final String terminalId;
  final bool isOpen;
  final int? sessionId;
  final String? openedAt;
  final String? businessDate;
  final double openingCash;

  final double grandTotalAccumulated;
  final int zCounter;
  final int resetCounter;

  factory RegisterSessionStatus.fromJson(Map<String, dynamic> json) {
    final session = json['session'] as Map<String, dynamic>?;
    final counters = (json['counters'] as Map<String, dynamic>?) ?? const {};

    return RegisterSessionStatus(
      terminalId: json['terminal_id']?.toString() ?? '',
      isOpen: session != null,
      sessionId: session == null
          ? null
          : RegisterReading._toInt(session['id']),
      openedAt: session?['opened_at']?.toString(),
      businessDate: session?['business_date']?.toString(),
      openingCash: RegisterReading._toDouble(session?['opening_cash']),
      grandTotalAccumulated:
          RegisterReading._toDouble(counters['grand_total_accumulated']),
      zCounter: RegisterReading._toInt(counters['z_counter']),
      resetCounter: RegisterReading._toInt(counters['reset_counter']),
    );
  }
}
