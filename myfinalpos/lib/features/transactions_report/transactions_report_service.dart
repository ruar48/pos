import 'dart:convert';

import 'package:http/http.dart' as http;

import 'transactions_report_models.dart';

class TransactionReportService {
  TransactionReportService(this.baseUrl);

  final String baseUrl;

  Future<TransactionReportResponse> fetch({
    required TransactionReportTab tab,
    required DateTime start,
    required DateTime end,
    int page = 1,
    int perPage = 25,
    String search = '',
  }) async {
    final query = <String, String>{
      'view': tab.apiView,
      'start': _formatDate(start),
      'end': _formatDate(end),
      'page': '$page',
      'per_page': '$perPage',
      if (search.trim().isNotEmpty) 'search': search.trim(),
    };

    final uri = Uri.parse('$baseUrl/transaction_reports.php')
        .replace(queryParameters: query);
    final response = await http.get(uri).timeout(const Duration(seconds: 20));

    final body = jsonDecode(response.body);
    if (response.statusCode != 200 || body is! Map || body['success'] != true) {
      final message = body is Map
          ? body['message']?.toString()
          : null;
      throw Exception(message ?? 'Failed to load transaction report');
    }

    final data = body['data'];
    if (data is! Map) {
      throw const FormatException('Invalid transaction report response');
    }

    return TransactionReportResponse.fromJson(Map<String, dynamic>.from(data));
  }

  String _formatDate(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}
