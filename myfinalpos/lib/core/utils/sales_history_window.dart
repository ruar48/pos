/// How much order history the tablet keeps loaded by default, and the
/// get_orders.php query for a date range.
///
/// get_orders.php used to return every order ever made (11k+ rows with their
/// items) on startup and after every sale. The tablet now loads from the 1st
/// of last month - enough for every preset (today, this/last week, this/last
/// month) - and fetches older orders only when a report asks for them.
library;

/// First day of the previous month (local time).
DateTime defaultSalesHistoryStart([DateTime? now]) {
  final today = now ?? DateTime.now();
  return DateTime(today.year, today.month - 1, 1);
}

String apiDate(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

/// Query parameters for get_orders.php, or null when nothing is filtered.
Map<String, String>? ordersDateQuery({
  DateTime? from,
  DateTime? to,
  int? orderId,
}) {
  final query = <String, String>{
    if (from != null) 'from': apiDate(from),
    if (to != null) 'to': apiDate(to),
    if (orderId != null && orderId > 0) 'order_id': '$orderId',
  };
  return query.isEmpty ? null : query;
}
