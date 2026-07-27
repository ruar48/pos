import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import 'monitor_disconnect_transport.dart';
import '../core/utils/format_utils.dart';
import '../core/utils/top_toast.dart';
import '../models/accounting_summary.dart';
import '../models/attendance_board.dart';
import '../models/attendance_status.dart';
import '../models/app_settings.dart';
import '../models/app_settings_sync.dart';
import '../models/audit_log_entry.dart';
import '../models/branch.dart';
import '../models/cart_item.dart';
import '../models/catalog_stock_sync.dart';
import '../models/catalog_sync_watch.dart';
import '../models/coupon.dart';
import '../models/customer.dart';
import '../models/face_profile.dart';
import '../models/staff_payment.dart';
import '../models/staff_user.dart';
import '../models/loyalty_card.dart';
import '../models/loyalty_point_log.dart';
import '../models/nfc_customer_lookup.dart';
import '../models/inventory_report.dart';
import '../models/live_wall_sales.dart';
import '../models/product.dart';
import '../models/pos_monitor.dart';
import '../models/refund_item_request.dart';
import '../models/sales_history_record.dart';

class PosApi {
  const PosApi();

  static const Duration catalogLoadTimeout = Duration(seconds: 12);
  static const Duration apiLoadTimeout = Duration(seconds: 10);

  Map<String, String> get _jsonHeaders => {
        'Content-Type': 'application/json',
      };

  Future<http.Response> _get(Uri uri, {Duration? timeout}) {
    return http.get(uri).timeout(
          timeout ?? apiLoadTimeout,
          onTimeout: () => throw TimeoutException(
            'The server took too long to respond.',
          ),
        );
  }

  Future<ProductCategory> saveCategory({
    required String name,
    String? description,
    String? icon,
    int? actorUserId,
  }) async {
    final uri = Uri.parse('$apiBaseUrl/categories.php');
    final trimmedIcon = icon?.trim();
    final response = await http.post(
      uri,
      headers: _jsonHeaders,
      body: jsonEncode({
        'name': name,
        if (description != null && description.trim().isNotEmpty)
          'description': description.trim(),
        if (trimmedIcon != null && trimmedIcon.isNotEmpty) 'icon': trimmedIcon,
        'actor_user_id': actorUserId,
      }),
    );
    final body = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode != 201 && response.statusCode != 200) {
      throw Exception(body['message'] ?? 'Failed to save category');
    }
    if (body['success'] != true) {
      throw Exception(body['message'] ?? 'Failed to save category');
    }

    return ProductCategory.fromJson(body['data'] as Map<String, dynamic>);
  }

  Future<List<ProductCategory>> fetchCategories() async {
    final uri = Uri.parse('$apiBaseUrl/categories.php');
    final response = await _get(uri, timeout: catalogLoadTimeout);
    final body = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode != 200 || body['success'] != true) {
      throw Exception(body['message'] ?? 'Failed to load categories');
    }

    final data = body['data'] as List<dynamic>;
    return data
        .map((item) => ProductCategory.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<List<Product>> fetchItems() async {
    final uri = Uri.parse('$apiBaseUrl/items.php');
    final response = await _get(uri, timeout: catalogLoadTimeout);
    final body = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode != 200 || body['success'] != true) {
      throw Exception(body['message'] ?? 'Failed to load items');
    }

    final data = body['data'] as List<dynamic>;
    return data
        .map((item) => Product.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<CatalogStockSyncResult> fetchStockSync({String? revision}) async {
    final uri = Uri.parse('$apiBaseUrl/items.php').replace(
      queryParameters: {
        'action': 'stock',
        if (revision != null && revision.isNotEmpty) 'revision': revision,
      },
    );
    final response = await http.get(uri);
    final body = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode != 200 || body['success'] != true) {
      throw Exception(body['message'] ?? 'Failed to sync stock');
    }

    final data = body['data'];
    if (data is! Map<String, dynamic>) {
      throw Exception('Invalid stock sync response');
    }

    return CatalogStockSyncResult.fromJson(data);
  }

  Future<CatalogSyncWatchResult> watchCatalogSync({
    String? stockRevision,
    String? settingsRevision,
  }) async {
    final uri = Uri.parse('$apiBaseUrl/items.php').replace(
      queryParameters: {
        'action': 'watch',
        if (stockRevision != null && stockRevision.isNotEmpty)
          'stock_revision': stockRevision,
        if (settingsRevision != null && settingsRevision.isNotEmpty)
          'settings_revision': settingsRevision,
      },
    );
    final response = await http
        .get(uri)
        .timeout(const Duration(seconds: 35));

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200 || body['success'] != true) {
      throw Exception(body['message'] ?? 'Failed to watch catalog sync');
    }

    final data = body['data'];
    if (data is! Map<String, dynamic>) {
      throw Exception('Invalid catalog watch response');
    }

    return CatalogSyncWatchResult.fromJson(data);
  }

  Future<List<Customer>> fetchCustomers() async {
    final uri = Uri.parse('$apiBaseUrl/customers.php');
    final response = await _get(uri);
    final body = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode != 200 || body['success'] != true) {
      throw Exception(body['message'] ?? 'Failed to load customers');
    }

    final data = body['data'] as List<dynamic>;
    return data
        .map((item) => Customer.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<List<LoyaltyCard>> fetchLoyaltyCards() async {
    final uri = Uri.parse('$apiBaseUrl/loyalty_cards.php');
    final response = await _get(uri);
    final body = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode != 200 || body['success'] != true) {
      throw Exception(body['message'] ?? 'Failed to load loyalty cards');
    }

    final data = body['data'] as List<dynamic>;
    return data
        .map((item) => LoyaltyCard.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<NfcCustomerLookup> lookupCustomerByNfcUid(String nfcUid) async {
    final normalized = normalizeNfcUid(nfcUid);
    final uri = Uri.parse('$apiBaseUrl/loyalty_cards.php').replace(
      queryParameters: {'nfc_uid': normalized},
    );
    final response = await http.get(uri);
    final body = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode != 200 || body['success'] != true) {
      throw Exception(body['message'] ?? 'No customer linked to this RFID card');
    }

    final data = body['data'];
    if (data is! Map<String, dynamic>) {
      throw Exception('Invalid RFID lookup response');
    }

    return NfcCustomerLookup.fromJson(data);
  }

  Future<List<Coupon>> fetchCoupons({bool includeInactive = false}) async {
    final uri = Uri.parse('$apiBaseUrl/coupons.php').replace(
      queryParameters: includeInactive ? {'include_inactive': '1'} : null,
    );
    final response = await _get(uri);
    final body = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode != 200 || body['success'] != true) {
      throw Exception(body['message'] ?? 'Failed to load coupons');
    }

    final data = body['data'] as List<dynamic>;
    return data
        .map((item) => Coupon.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<Coupon> saveCoupon({
    required String code,
    required String discountType,
    required double discountValue,
    String? description,
    double minOrderAmount = 0,
    required String startDate,
    required String endDate,
    int? maxUses,
    int? actorUserId,
  }) async {
    final uri = Uri.parse('$apiBaseUrl/coupons.php');
    final response = await http.post(
      uri,
      headers: _jsonHeaders,
      body: jsonEncode({
        'action': 'create',
        'code': code.trim().toUpperCase(),
        'description': description?.trim(),
        'discount_type': discountType,
        'discount_value': discountValue,
        'min_order_amount': minOrderAmount,
        'start_date': startDate,
        'end_date': endDate,
        if (maxUses != null) 'max_uses': maxUses,
        'actor_user_id': actorUserId,
      }),
    );
    final body = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode != 201 || body['success'] != true) {
      throw Exception(body['message'] ?? 'Failed to save coupon');
    }

    return Coupon.fromJson(body['data'] as Map<String, dynamic>);
  }

  Future<Coupon> updateCoupon({
    required int id,
    required String code,
    required String discountType,
    required double discountValue,
    String? description,
    double minOrderAmount = 0,
    required String startDate,
    required String endDate,
    int? maxUses,
    int? actorUserId,
  }) async {
    final uri = Uri.parse('$apiBaseUrl/coupons.php');
    final response = await http.post(
      uri,
      headers: _jsonHeaders,
      body: jsonEncode({
        'action': 'update',
        'id': id,
        'code': code.trim().toUpperCase(),
        'description': description?.trim(),
        'discount_type': discountType,
        'discount_value': discountValue,
        'min_order_amount': minOrderAmount,
        'start_date': startDate,
        'end_date': endDate,
        'max_uses': maxUses,
        'actor_user_id': actorUserId,
      }),
    );
    final body = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode != 200 || body['success'] != true) {
      throw Exception(body['message'] ?? 'Failed to update coupon');
    }

    return Coupon.fromJson(body['data'] as Map<String, dynamic>);
  }

  Future<Coupon> toggleCoupon({
    required int id,
    int? actorUserId,
  }) async {
    final uri = Uri.parse('$apiBaseUrl/coupons.php');
    final response = await http.post(
      uri,
      headers: _jsonHeaders,
      body: jsonEncode({
        'action': 'toggle',
        'id': id,
        'actor_user_id': actorUserId,
      }),
    );
    final body = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode != 200 || body['success'] != true) {
      throw Exception(body['message'] ?? 'Failed to update coupon status');
    }

    return Coupon.fromJson(body['data'] as Map<String, dynamic>);
  }

  Future<({Coupon coupon, double discountAmount})> validateCoupon({
    required String code,
    double subtotal = 0,
  }) async {
    final uri = Uri.parse('$apiBaseUrl/coupons.php');
    final response = await http.post(
      uri,
      headers: _jsonHeaders,
      body: jsonEncode({
        'action': 'validate',
        'code': code.trim().toUpperCase(),
        'subtotal': subtotal,
      }),
    );
    final body = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode != 200 || body['success'] != true) {
      throw Exception(body['message'] ?? 'Invalid coupon code');
    }

    return (
      coupon: Coupon.fromJson(body['data'] as Map<String, dynamic>),
      discountAmount: toDouble(body['discount_amount']),
    );
  }

  Future<List<StaffUser>> fetchUsers({required int actorUserId}) async {
    final uri = Uri.parse('$apiBaseUrl/users.php').replace(
      queryParameters: {'actor_user_id': '$actorUserId'},
    );
    final response = await http.get(uri);
    final body = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode != 200 || body['success'] != true) {
      throw Exception(body['message'] ?? 'Failed to load users');
    }

    final data = body['data'] as List<dynamic>;
    return data
        .map((item) => StaffUser.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<StaffUser> saveUser({
    required String fullName,
    required String role,
    required int actorUserId,
    String? username,
    String? email,
    String? password,
    int? branchId,
  }) async {
    final uri = Uri.parse('$apiBaseUrl/users.php');
    final response = await http.post(
      uri,
      headers: _jsonHeaders,
      body: jsonEncode({
        'action': 'create',
        'full_name': fullName,
        'role': role,
        'actor_user_id': actorUserId,
        if (username != null && username.isNotEmpty) 'username': username,
        if (email != null && email.isNotEmpty) 'email': email,
        if (password != null && password.isNotEmpty) 'password': password,
        if (branchId != null) 'branch_id': branchId,
      }),
    );
    final body = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode != 201 || body['success'] != true) {
      throw Exception(body['message'] ?? 'Failed to create user');
    }

    return StaffUser.fromJson(body['data'] as Map<String, dynamic>);
  }

  Future<StaffUser> updateUser({
    required int id,
    required String fullName,
    required String username,
    required String email,
    required String role,
    required int actorUserId,
    int? branchId,
  }) async {
    final uri = Uri.parse('$apiBaseUrl/users.php');
    final response = await http.post(
      uri,
      headers: _jsonHeaders,
      body: jsonEncode({
        'action': 'update',
        'id': id,
        'full_name': fullName,
        'username': username,
        'email': email,
        'role': role,
        'actor_user_id': actorUserId,
        'branch_id': branchId,
      }),
    );
    final body = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode != 200 || body['success'] != true) {
      throw Exception(body['message'] ?? 'Failed to update user');
    }

    return StaffUser.fromJson(body['data'] as Map<String, dynamic>);
  }

  Future<StaffUser> toggleUserStatus({
    required int id,
    required int actorUserId,
  }) async {
    final uri = Uri.parse('$apiBaseUrl/users.php');
    final response = await http.post(
      uri,
      headers: _jsonHeaders,
      body: jsonEncode({
        'action': 'toggle',
        'id': id,
        'actor_user_id': actorUserId,
      }),
    );
    final body = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode != 200 || body['success'] != true) {
      throw Exception(body['message'] ?? 'Failed to update user status');
    }

    return StaffUser.fromJson(body['data'] as Map<String, dynamic>);
  }

  Future<void> changeOwnPassword({
    required int actorUserId,
    required String currentPassword,
    required String newPassword,
  }) async {
    final uri = Uri.parse('$apiBaseUrl/change_password.php');
    final response = await http.post(
      uri,
      headers: _jsonHeaders,
      body: jsonEncode({
        'actor_user_id': actorUserId,
        'current_password': currentPassword,
        'password': newPassword,
      }),
    );
    final body = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode != 200 || body['success'] != true) {
      throw Exception(body['message'] ?? 'Failed to change password');
    }
  }

  Future<String> requestPasswordReset({required String email}) async {
    final uri = Uri.parse('$apiBaseUrl/forgot_password.php');
    final response = await http.post(
      uri,
      headers: _jsonHeaders,
      body: jsonEncode({'email': email.trim()}),
    );
    final body = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode != 200 || body['success'] != true) {
      throw Exception(body['message'] ?? 'Failed to send reset link');
    }

    return (body['message'] as String?)?.trim().isNotEmpty == true
        ? body['message'] as String
        : 'If that account exists, a reset link has been sent to its email.';
  }

  Future<void> resetUserPassword({
    required int id,
    required String password,
    required int actorUserId,
  }) async {
    final uri = Uri.parse('$apiBaseUrl/users.php');
    final response = await http.post(
      uri,
      headers: _jsonHeaders,
      body: jsonEncode({
        'action': 'reset_password',
        'id': id,
        'password': password,
        'actor_user_id': actorUserId,
      }),
    );
    final body = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode != 200 || body['success'] != true) {
      throw Exception(body['message'] ?? 'Failed to reset password');
    }
  }

  Future<List<AuditLogEntry>> fetchAuditLogs({
    required int actorUserId,
    int limit = 100,
    String? module,
  }) async {
    final uri = Uri.parse('$apiBaseUrl/audit_logs.php').replace(
      queryParameters: {
        'actor_user_id': '$actorUserId',
        'limit': '$limit',
        if (module != null && module.isNotEmpty) 'module': module,
      },
    );
    final response = await http.get(uri);
    final body = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode != 200 || body['success'] != true) {
      throw Exception(body['message'] ?? 'Failed to load audit logs');
    }

    final data = body['data'] as List<dynamic>;
    return data
        .map((item) => AuditLogEntry.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<List<Branch>> fetchBranches({
    bool includeInactive = false,
    int? actorUserId,
  }) async {
    final uri = Uri.parse('$apiBaseUrl/branches.php').replace(
      queryParameters: {
        if (includeInactive) 'include_inactive': '1',
        if (includeInactive && actorUserId != null)
          'actor_user_id': '$actorUserId',
      },
    );
    final response = await _get(uri);
    final body = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode != 200 || body['success'] != true) {
      throw Exception(body['message'] ?? 'Failed to load branches');
    }

    final data = body['data'] as List<dynamic>;
    if (data.isEmpty) return [Branch.mainBranch];

    return data
        .map((item) => Branch.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<Branch> createBranch({
    required String name,
    String? code,
    String? location,
    int? actorUserId,
  }) async {
    final uri = Uri.parse('$apiBaseUrl/branches.php');
    final response = await http.post(
      uri,
      headers: _jsonHeaders,
      body: jsonEncode({
        'name': name,
        'code': code,
        'location': location,
        'actor_user_id': actorUserId,
      }),
    );
    final body = jsonDecode(response.body) as Map<String, dynamic>;

    if ((response.statusCode != 201 && response.statusCode != 200) ||
        body['success'] != true) {
      throw Exception(body['message'] ?? 'Failed to create branch');
    }

    return Branch.fromJson(body['data'] as Map<String, dynamic>);
  }

  Future<Branch> updateBranch({
    required int id,
    required String name,
    String? code,
    String? location,
    required int actorUserId,
  }) async {
    final uri = Uri.parse('$apiBaseUrl/branches.php');
    final response = await http.post(
      uri,
      headers: _jsonHeaders,
      body: jsonEncode({
        'action': 'update',
        'id': id,
        'name': name,
        'code': code,
        'location': location,
        'actor_user_id': actorUserId,
      }),
    );
    final body = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode != 200 || body['success'] != true) {
      throw Exception(body['message'] ?? 'Failed to update branch');
    }

    return Branch.fromJson(body['data'] as Map<String, dynamic>);
  }

  Future<Branch> toggleBranchStatus({
    required int id,
    required int actorUserId,
  }) async {
    final uri = Uri.parse('$apiBaseUrl/branches.php');
    final response = await http.post(
      uri,
      headers: _jsonHeaders,
      body: jsonEncode({
        'action': 'toggle',
        'id': id,
        'actor_user_id': actorUserId,
      }),
    );
    final body = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode != 200 || body['success'] != true) {
      throw Exception(body['message'] ?? 'Failed to update branch status');
    }

    return Branch.fromJson(body['data'] as Map<String, dynamic>);
  }

  Future<List<StaffPayment>> fetchStaffPayments({
    required int actorUserId,
    int? userId,
    int? branchId,
    int limit = 100,
  }) async {
    final uri = Uri.parse('$apiBaseUrl/staff_payments.php').replace(
      queryParameters: {
        'actor_user_id': '$actorUserId',
        'limit': '$limit',
        if (userId != null) 'user_id': '$userId',
        if (branchId != null) 'branch_id': '$branchId',
      },
    );
    final response = await http.get(uri);
    final body = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode != 200 || body['success'] != true) {
      throw Exception(body['message'] ?? 'Failed to load staff payments');
    }

    final data = body['data'] as List<dynamic>;
    return data
        .map((item) => StaffPayment.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<StaffPayment> createStaffPayment({
    required int userId,
    required double amount,
    required String paymentType,
    required int actorUserId,
    int? branchId,
    String? periodStart,
    String? periodEnd,
    String? notes,
  }) async {
    final uri = Uri.parse('$apiBaseUrl/staff_payments.php');
    final response = await http.post(
      uri,
      headers: _jsonHeaders,
      body: jsonEncode({
        'user_id': userId,
        'amount': amount,
        'payment_type': paymentType,
        'actor_user_id': actorUserId,
        if (branchId != null) 'branch_id': branchId,
        if (periodStart != null && periodStart.isNotEmpty)
          'period_start': periodStart,
        if (periodEnd != null && periodEnd.isNotEmpty) 'period_end': periodEnd,
        if (notes != null && notes.isNotEmpty) 'notes': notes,
      }),
    );
    final body = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode != 201 || body['success'] != true) {
      throw Exception(body['message'] ?? 'Failed to record staff payment');
    }

    return StaffPayment.fromJson(body['data'] as Map<String, dynamic>);
  }

  Future<List<SalesHistoryRecord>> fetchSalesHistory() async {
    final uri = Uri.parse('$apiBaseUrl/get_orders.php');
    final response = await _get(uri);
    final body = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode != 200 || body['success'] != true) {
      throw Exception(body['message'] ?? 'Failed to load orders');
    }

    final data = body['data'] as List<dynamic>;
    return data
        .map(
          (item) =>
              SalesHistoryRecord.fromOrderJson(item as Map<String, dynamic>),
        )
        .toList();
  }

  Future<AccountingSummary> fetchAccountingSummary({
    String period = 'all',
  }) async {
    final uri = Uri.parse('$apiBaseUrl/accounting_summary.php').replace(
      queryParameters: {'period': period},
    );
    final response = await http.get(uri);
    final body = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode != 200 || body['success'] != true) {
      throw Exception(body['message'] ?? 'Failed to load accounting summary');
    }

    return AccountingSummary.fromJson(body['data'] as Map<String, dynamic>);
  }

  Future<AppSettingsModel> fetchSettings() async {
    final uri = Uri.parse('$apiBaseUrl/settings.php');
    final response = await _get(uri);
    final body = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode != 200 || body['success'] != true) {
      throw Exception(body['message'] ?? 'Failed to load settings');
    }

    return AppSettingsModel.fromJson(body['data'] as Map<String, dynamic>);
  }

  Future<AppSettingsSyncResult> fetchSettingsSync({String? revision}) async {
    final uri = Uri.parse('$apiBaseUrl/settings.php').replace(
      queryParameters: {
        if (revision != null && revision.isNotEmpty) 'revision': revision,
      },
    );
    final response = await http.get(uri);
    final body = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode != 200 || body['success'] != true) {
      throw Exception(body['message'] ?? 'Failed to sync settings');
    }

    final data = body['data'];
    if (data is! Map<String, dynamic>) {
      throw Exception('Invalid settings sync response');
    }

    return AppSettingsSyncResult.fromJson(data);
  }

  Future<Customer> saveCustomer({
    required String customerName,
    required String tableName,
    required String orderType,
    int? actorUserId,
    bool createLoyaltyCard = false,
  }) async {
    final uri = Uri.parse('$apiBaseUrl/customers.php');

    final finalCustomerName = customerName.trim();
    if (finalCustomerName.isEmpty) {
      throw Exception('Customer name is required');
    }

    final response = await http.post(
      uri,
      headers: _jsonHeaders,
      body: jsonEncode({
        'customer_name': finalCustomerName,
        'table_name': tableName,
        'order_type': orderType,
        'actor_user_id': actorUserId,
        'create_loyalty_card': createLoyaltyCard,
      }),
    );
    final body = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode != 201 || body['success'] != true) {
      throw Exception(body['message'] ?? 'Failed to save customer');
    }

    return Customer.fromJson(body['data'] as Map<String, dynamic>);
  }

  Future<LoyaltyCard> openLoyaltyCard({
    required int customerId,
    int? actorUserId,
  }) async {
    final uri = Uri.parse('$apiBaseUrl/loyalty_cards.php');
    final response = await http.post(
      uri,
      headers: _jsonHeaders,
      body: jsonEncode({
        'customer_id': customerId,
        'actor_user_id': actorUserId,
      }),
    );
    final body = jsonDecode(response.body) as Map<String, dynamic>;

    if ((response.statusCode != 201 && response.statusCode != 200) ||
        body['success'] != true) {
      throw Exception(body['message'] ?? 'Failed to open loyalty card');
    }

    return LoyaltyCard.fromJson(body['data'] as Map<String, dynamic>);
  }

  Future<LoyaltyCard> linkLoyaltyCardRfid({
    required int customerId,
    required String rfidUid,
    int? actorUserId,
  }) async {
    final uri = Uri.parse('$apiBaseUrl/loyalty_cards.php');
    final response = await http.post(
      uri,
      headers: _jsonHeaders,
      body: jsonEncode({
        'action': 'link_nfc',
        'customer_id': customerId,
        'nfc_uid': normalizeNfcUid(rfidUid),
        if (actorUserId != null) 'actor_user_id': actorUserId,
      }),
    );
    final body = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode != 200 || body['success'] != true) {
      throw Exception(body['message'] ?? 'Failed to link RFID card');
    }

    return LoyaltyCard.fromJson(body['data'] as Map<String, dynamic>);
  }

  Future<List<LoyaltyPointLog>> fetchLoyaltyPointLogs({
    required int customerId,
    int limit = 50,
  }) async {
    final uri = Uri.parse('$apiBaseUrl/loyalty_point_logs.php').replace(
      queryParameters: {
        'customer_id': '$customerId',
        'limit': '$limit',
      },
    );
    final response = await http.get(uri);
    final body = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode != 200 || body['success'] != true) {
      throw Exception(body['message'] ?? 'Failed to load loyalty point logs');
    }

    final data = body['data'] as List<dynamic>;
    return data
        .map(
          (item) => LoyaltyPointLog.fromJson(item as Map<String, dynamic>),
        )
        .toList();
  }

  Map<String, dynamic> buildOrderPayload({
    int? customerId,
    required List<CartItem> cartItems,
    required double subtotal,
    required double vat,
    required double totalAmount,
    required double clientChange,
    required String paymentMethod,
    required String reference,
    required double discountAmount,
    required double couponDiscount,
    String couponCode = '',
    required double loyaltyDiscount,
    required int loyaltyPointsRedeemed,
    int? actorUserId,
    int branchId = 1,
    List<Map<String, dynamic>>? payments,
    String receiptNote = '',
    DateTime? soldAt,
  }) {
    final orderItems = cartItems.map((item) => item.toJson()).toList();
    return {
      if (customerId != null && customerId > 0) 'customer_id': customerId,
      'is_walk_in': customerId == null || customerId <= 0,
      'items': orderItems,
      'subtotal': subtotal,
      'vat': vat,
      'total_amount': totalAmount,
      'client_change': clientChange,
      'payment_method': paymentMethod,
      'reference': reference,
      'discount_amount': discountAmount,
      'coupon_discount': couponDiscount,
      if (couponCode.trim().isNotEmpty)
        'coupon_code': couponCode.trim().toUpperCase(),
      'loyalty_discount': loyaltyDiscount,
      'loyalty_points_redeemed': loyaltyPointsRedeemed,
      'branch_id': branchId,
      'actor_user_id': actorUserId,
      if (payments != null && payments.isNotEmpty) 'payments': payments,
      if (receiptNote.trim().isNotEmpty) 'receipt_note': receiptNote.trim(),
    };
  }

  Future<int> saveOrderPayload(Map<String, dynamic> payload) async {
    final uri = Uri.parse('$apiBaseUrl/orders.php');
    final response = await http.post(
      uri,
      headers: _jsonHeaders,
      body: jsonEncode(payload),
    );

    final body = parseApiJsonBody(response.body);
    if (body == null) {
      throw Exception(uploadHttpErrorMessage(response.statusCode, response.body));
    }

    if (response.statusCode != 201 || body['success'] != true) {
      throw Exception(body['message'] ?? 'Failed to save order');
    }

    return toInt(body['order_id']);
  }

  Future<int> saveOrder({
    int? customerId,
    required List<CartItem> cartItems,
    required double subtotal,
    required double vat,
    required double totalAmount,
    required double clientChange,
    required String paymentMethod,
    required String reference,
    required double discountAmount,
    required double couponDiscount,
    String couponCode = '',
    required double loyaltyDiscount,
    required int loyaltyPointsRedeemed,
    int? actorUserId,
    int branchId = 1,
    List<Map<String, dynamic>>? payments,
    String receiptNote = '',
  }) {
    return saveOrderPayload(
      buildOrderPayload(
        customerId: customerId,
        cartItems: cartItems,
        subtotal: subtotal,
        vat: vat,
        totalAmount: totalAmount,
        clientChange: clientChange,
        paymentMethod: paymentMethod,
        reference: reference,
        discountAmount: discountAmount,
        couponDiscount: couponDiscount,
        couponCode: couponCode,
        loyaltyDiscount: loyaltyDiscount,
        loyaltyPointsRedeemed: loyaltyPointsRedeemed,
        actorUserId: actorUserId,
        branchId: branchId,
        payments: payments,
        receiptNote: receiptNote,
      ),
    );
  }

  Future<Map<String, dynamic>> refundOrderAll({
    required int orderId,
    required String reason,
    required String refundPin,
    int? actorUserId,
  }) async {
    return _postRefund(
      orderId: orderId,
      reason: reason,
      refundType: 'all',
      items: const [],
      refundPin: refundPin,
      actorUserId: actorUserId,
    );
  }

  Future<Map<String, dynamic>> refundOrderByItems({
    required int orderId,
    required String reason,
    required List<RefundItemRequest> items,
    required String refundPin,
    int? actorUserId,
  }) async {
    return _postRefund(
      orderId: orderId,
      reason: reason,
      refundType: 'items',
      items: items,
      refundPin: refundPin,
      actorUserId: actorUserId,
    );
  }

  Future<Map<String, dynamic>> _postRefund({
    required int orderId,
    required String reason,
    required String refundType,
    required List<RefundItemRequest> items,
    required String refundPin,
    int? actorUserId,
  }) async {
    final uri = Uri.parse('$apiBaseUrl/process_refund.php');
    final response = await http.post(
      uri,
      headers: _jsonHeaders,
      body: jsonEncode({
        'order_id': orderId,
        'refund_type': refundType,
        'reason': reason,
        'items': items.map((item) => item.toJson()).toList(),
        'refund_pin': refundPin,
        'actor_user_id': actorUserId,
      }),
    );

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200 || body['success'] != true) {
      throw Exception(body['message'] ?? 'Failed to process refund');
    }
    return body;
  }

  Future<Product> updateProductStock({
    required int productId,
    int? varietyId,
    int? stock,
    int? delta,
    int? actorUserId,
  }) async {
    final uri = Uri.parse('$apiBaseUrl/inventory.php');
    final response = await http.post(
      uri,
      headers: _jsonHeaders,
      body: jsonEncode({
        'product_id': productId,
        if (varietyId != null && varietyId > 0) 'variety_id': varietyId,
        if (stock != null) 'stock': stock,
        if (delta != null) 'delta': delta,
        'actor_user_id': actorUserId,
      }),
    );
    final body = parseApiJsonBody(response.body);

    if (response.statusCode != 200 || body == null || body['success'] != true) {
      final apiMessage = body?['message']?.toString().trim();
      throw Exception(
        (apiMessage != null && apiMessage.isNotEmpty)
            ? apiMessage
            : uploadHttpErrorMessage(response.statusCode, response.body),
      );
    }

    return Product.fromJson(body['data'] as Map<String, dynamic>);
  }

  Future<Product> saveProduct({
    required String name,
    required String category,
    required double price,
    String? option,
    String? sku,
    String? barcode,
    String? description,
    double? costPrice,
    int? stock,
    int? reorderLevel,
    String? unit,
    String? imageUrl,
    List<int>? imageBytes,
    String? imageFilename,
    String? imageMimeType,
    List<Map<String, dynamic>>? varieties,
    int? actorUserId,
  }) async {
    final uri = Uri.parse('$apiBaseUrl/items.php');
    final trimmedSku = sku?.trim();
    final trimmedBarcode = barcode?.trim();
    final trimmedDescription = description?.trim();
    final trimmedOption = option?.trim();
    final payload = <String, dynamic>{
      'name': name,
      'category': category,
      'price': price,
      if (trimmedOption != null && trimmedOption.isNotEmpty)
        'option': trimmedOption,
      if (trimmedSku != null && trimmedSku.isNotEmpty) 'sku': trimmedSku,
      if (trimmedBarcode != null && trimmedBarcode.isNotEmpty)
        'barcode': trimmedBarcode,
      if (trimmedDescription != null && trimmedDescription.isNotEmpty)
        'description': trimmedDescription,
      if (costPrice != null) 'cost_price': costPrice,
      if (stock != null) 'stock': stock,
      if (reorderLevel != null) 'reorder_level': reorderLevel,
      if (unit != null && unit.trim().isNotEmpty) 'unit': unit.trim(),
      if (varieties != null) 'varieties': varieties,
      'actor_user_id': actorUserId,
    };

    if (imageBytes != null && imageBytes.isNotEmpty) {
      payload['image_base64'] = base64Encode(imageBytes);
      payload['image_filename'] = _safeImageFilename(imageFilename);
      payload['image_mime_type'] =
          _resolvedMimeType(imageMimeType, payload['image_filename'] as String);
    } else if (imageUrl != null && imageUrl.trim().isNotEmpty) {
      payload['image_url'] = imageUrl.trim();
    }

    final response = await http.post(
      uri,
      headers: _jsonHeaders,
      body: jsonEncode(payload),
    );
    final body = parseApiJsonBody(response.body);

    if (response.statusCode != 201 || body == null || body['success'] != true) {
      final apiMessage = body?['message']?.toString().trim();
      throw Exception(
        (apiMessage != null && apiMessage.isNotEmpty)
            ? apiMessage
            : uploadHttpErrorMessage(response.statusCode, response.body),
      );
    }

    return Product.fromJson(body['data'] as Map<String, dynamic>);
  }

  Future<Product> updateProduct({
    required int id,
    required String name,
    required String category,
    required double price,
    String? option,
    String? sku,
    String? barcode,
    String? description,
    double? costPrice,
    int? stock,
    int? reorderLevel,
    String? unit,
    String? imageUrl,
    List<int>? imageBytes,
    String? imageFilename,
    String? imageMimeType,
    List<Map<String, dynamic>>? varieties,
    int? actorUserId,
  }) async {
    final uri = Uri.parse('$apiBaseUrl/items.php');
    final trimmedSku = sku?.trim();
    final trimmedBarcode = barcode?.trim();
    final trimmedDescription = description?.trim();
    final trimmedOption = option?.trim();
    final payload = <String, dynamic>{
      'id': id,
      'name': name,
      'category': category,
      'price': price,
      'option': trimmedOption == null || trimmedOption.isEmpty
          ? null
          : trimmedOption,
      if (trimmedSku != null && trimmedSku.isNotEmpty) 'sku': trimmedSku,
      if (trimmedBarcode != null && trimmedBarcode.isNotEmpty)
        'barcode': trimmedBarcode,
      if (trimmedDescription != null && trimmedDescription.isNotEmpty)
        'description': trimmedDescription,
      if (costPrice != null) 'cost_price': costPrice,
      if (stock != null) 'stock': stock,
      if (reorderLevel != null) 'reorder_level': reorderLevel,
      if (unit != null && unit.trim().isNotEmpty) 'unit': unit.trim(),
      if (varieties != null) 'varieties': varieties,
      'actor_user_id': actorUserId,
    };

    if (imageBytes != null && imageBytes.isNotEmpty) {
      payload['image_base64'] = base64Encode(imageBytes);
      payload['image_filename'] = _safeImageFilename(imageFilename);
      payload['image_mime_type'] =
          _resolvedMimeType(imageMimeType, payload['image_filename'] as String);
    } else if (imageUrl != null && imageUrl.trim().isNotEmpty) {
      payload['image_url'] = imageUrl.trim();
    }

    final response = await http.put(
      uri,
      headers: _jsonHeaders,
      body: jsonEncode(payload),
    );
    final body = parseApiJsonBody(response.body);

    if (response.statusCode != 200 || body == null || body['success'] != true) {
      final apiMessage = body?['message']?.toString().trim();
      throw Exception(
        (apiMessage != null && apiMessage.isNotEmpty)
            ? apiMessage
            : uploadHttpErrorMessage(response.statusCode, response.body),
      );
    }

    return Product.fromJson(body['data'] as Map<String, dynamic>);
  }

  Future<String> uploadProductImage({
    required List<int> bytes,
    required String filename,
    String? mimeType,
    int? actorUserId,
  }) async {
    if (bytes.isEmpty) {
      throw Exception('Selected image is empty. Try another photo.');
    }

    final uri = Uri.parse('$apiBaseUrl/upload_product_image.php');
    final safeName = filename.trim().isEmpty
        ? 'upload.jpg'
        : (filename.contains('.') ? filename : '$filename.jpg');
    final resolvedMime = _resolvedMimeType(mimeType, safeName);

    final response = await http.post(
      uri,
      headers: _jsonHeaders,
      body: jsonEncode({
        'image_base64': base64Encode(bytes),
        'filename': safeName,
        'mime_type': resolvedMime,
        if (actorUserId != null) 'actor_user_id': actorUserId,
      }),
    );
    final body = parseApiJsonBody(response.body);

    if (response.statusCode != 201 || body == null || body['success'] != true) {
      throw Exception(
        uploadHttpErrorMessage(response.statusCode, response.body),
      );
    }

    final data = body['data'] as Map<String, dynamic>;
    final imageUrl = (data['image_url'] ?? '').toString();
    if (imageUrl.isEmpty) {
      throw Exception('Upload succeeded but no image path was returned');
    }
    return imageUrl;
  }

  String _safeImageFilename(String? filename) {
    final trimmed = filename?.trim() ?? '';
    if (trimmed.isEmpty) {
      return 'upload.jpg';
    }
    return trimmed.contains('.') ? trimmed : '$trimmed.jpg';
  }

  String _resolvedMimeType(String? mimeType, String filename) {
    final normalized = mimeType?.toLowerCase().trim();
    if (normalized != null && normalized.startsWith('image/')) {
      return normalized;
    }

    final ext = filename.contains('.')
        ? filename.split('.').last.toLowerCase()
        : 'jpg';
    return switch (ext) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      'gif' => 'image/gif',
      _ => 'image/jpeg',
    };
  }

  Future<AppSettingsModel> saveSettings({
    required AppSettingsModel settings,
    int? actorUserId,
    Map<String, dynamic>? receiptStore,
    int? defaultBranchId,
    String? refundPin,
  }) async {
    final uri = Uri.parse('$apiBaseUrl/settings.php');
    final payload = <String, dynamic>{
      'tax_rate': settings.taxRate,
      'auto_print_receipt': settings.autoPrintReceipt,
      'double_print_receipt': settings.doublePrintReceipt,
      'allow_negative_stock': settings.allowNegativeStock,
      'low_stock_email_enabled': settings.lowStockEmailEnabled,
      'low_stock_email_recipients': settings.lowStockEmailRecipients,
      'loyalty_enabled': settings.loyaltyEnabled,
      'loyalty_points_per_unit': settings.loyaltyPointsPerUnit,
      'loyalty_spend_unit': settings.loyaltySpendUnit,
      'loyalty_redeem_points_per_peso': settings.loyaltyRedeemPointsPerPeso,
      'currency_symbol': settings.currencySymbol,
      'printer_host': settings.printerHost,
      'printer_type': settings.printerType,
      'printer_device': settings.printerDevice,
      'printer_port': settings.printerPort,
      'attendance_start_time': settings.attendanceMorningOfficialStart,
      'attendance_grace_minutes': settings.attendanceGraceMinutes,
      'attendance_lunch_out_time': settings.attendanceBreakOutEnd,
      'attendance_afternoon_in_time': settings.attendanceAfternoonOnTimeEnd,
      'attendance_day_end_time': settings.attendanceTimeoutStart,
      'attendance_morning_absent_after_time': settings.attendanceMorningCutoff,
      'attendance_morning_accept_start': settings.attendanceMorningAcceptStart,
      'attendance_morning_official_start':
          settings.attendanceMorningOfficialStart,
      'attendance_morning_grace_end': settings.attendanceMorningGraceEnd,
      'attendance_morning_late_start': settings.attendanceMorningLateStart,
      'attendance_morning_cutoff': settings.attendanceMorningCutoff,
      'attendance_break_out_start': settings.attendanceBreakOutStart,
      'attendance_break_out_end': settings.attendanceBreakOutEnd,
      'attendance_afternoon_accept_start':
          settings.attendanceAfternoonAcceptStart,
      'attendance_afternoon_on_time_end': settings.attendanceAfternoonOnTimeEnd,
      'attendance_afternoon_late_start': settings.attendanceAfternoonLateStart,
      'attendance_afternoon_cutoff': settings.attendanceAfternoonCutoff,
      'attendance_timeout_start': settings.attendanceTimeoutStart,
      'actor_user_id': actorUserId,
    };
    if (receiptStore != null) {
      payload['receipt_store'] = receiptStore;
    }
    if (defaultBranchId != null && defaultBranchId > 0) {
      payload['default_branch_id'] = defaultBranchId;
    }
    if (refundPin != null && refundPin.isNotEmpty) {
      payload['refund_pin'] = refundPin;
    }

    final response = await http.post(
      uri,
      headers: _jsonHeaders,
      body: jsonEncode(payload),
    );
    final body = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode != 200 || body['success'] != true) {
      throw Exception(body['message'] ?? 'Failed to save settings');
    }

    return AppSettingsModel.fromJson(body['data'] as Map<String, dynamic>);
  }

  Future<AttendanceBoardResult> fetchAttendanceBoard({
    required int actorUserId,
    required String date,
    int? branchId,
  }) async {
    final uri = Uri.parse('$apiBaseUrl/attendance.php').replace(
      queryParameters: {
        'date': date,
        'actor_user_id': '$actorUserId',
        if (branchId != null) 'branch_id': '$branchId',
      },
    );
    final response = await http.get(uri);
    final body = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode != 200 || body['success'] != true) {
      throw Exception(body['message'] ?? 'Failed to load attendance board');
    }

    return AttendanceBoardResult.fromJson(body);
  }

  Future<AttendanceStatus> fetchAttendanceStatus({
    required int userId,
    String? date,
  }) async {
    final uri = Uri.parse('$apiBaseUrl/attendance.php').replace(
      queryParameters: {
        'user_id': '$userId',
        if (date != null && date.isNotEmpty) 'date': date,
      },
    );
    final response = await http.get(uri);
    final body = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode != 200 || body['success'] != true) {
      throw Exception(body['message'] ?? 'Failed to load attendance status');
    }

    final status = body['status'] as Map<String, dynamic>? ?? {};
    return AttendanceStatus.fromJson(status);
  }

  Future<FaceEnrollmentStatus> fetchFaceEnrollmentStatus({
    required int userId,
  }) async {
    final uri = Uri.parse('$apiBaseUrl/face_profiles.php').replace(
      queryParameters: {'user_id': '$userId'},
    );
    final response = await http.get(uri);
    final body = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode != 200 || body['success'] != true) {
      throw Exception(body['message'] ?? 'Failed to load face enrollment status');
    }

    return FaceEnrollmentStatus.fromJson(
      body['data'] as Map<String, dynamic>,
    );
  }

  Future<List<FaceStaffDirectoryEntry>> fetchFaceStaffDirectory({
    required int actorUserId,
  }) async {
    final uri = Uri.parse('$apiBaseUrl/face_profiles.php').replace(
      queryParameters: {
        'staff': '1',
        'actor_user_id': '$actorUserId',
      },
    );
    final response = await http.get(uri);
    final body = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode != 200 || body['success'] != true) {
      throw Exception(body['message'] ?? 'Failed to load staff for face enrollment');
    }

    final rows = body['data'] as List<dynamic>? ?? [];
    return rows
        .map((row) => FaceStaffDirectoryEntry.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  Future<FaceEnrollmentStatus> enrollFace({
    required int userId,
    required List<double> descriptor,
    required int actorUserId,
    int confidence = 95,
  }) async {
    final uri = Uri.parse('$apiBaseUrl/face_profiles.php');
    final response = await http.post(
      uri,
      headers: _jsonHeaders,
      body: jsonEncode({
        'action': 'enroll',
        'user_id': userId,
        'descriptor': descriptor,
        'confidence': confidence,
        'actor_user_id': actorUserId,
      }),
    );
    final body = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode != 200 || body['success'] != true) {
      throw Exception(body['message'] ?? 'Face enrollment failed');
    }

    final data = body['data'] as Map<String, dynamic>;
    return FaceEnrollmentStatus(
      userId: (data['user_id'] as num?)?.toInt() ?? userId,
      enrolled: true,
      confidence: (data['confidence'] as num?)?.toInt() ?? confidence,
      enrolledAt: data['enrolled_at']?.toString(),
    );
  }

  Future<void> deleteFaceProfile({
    required int userId,
    required int actorUserId,
  }) async {
    final uri = Uri.parse('$apiBaseUrl/face_profiles.php');
    final response = await http.post(
      uri,
      headers: _jsonHeaders,
      body: jsonEncode({
        'action': 'delete',
        'user_id': userId,
        'actor_user_id': actorUserId,
      }),
    );
    final body = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode != 200 || body['success'] != true) {
      throw Exception(body['message'] ?? 'Could not remove face profile');
    }
  }

  Future<FaceVerifyResult> verifyFace({
    required List<double> descriptor,
    int? actorUserId,
  }) async {
    final uri = Uri.parse('$apiBaseUrl/face_profiles.php');
    final response = await http.post(
      uri,
      headers: _jsonHeaders,
      body: jsonEncode({
        'action': 'verify',
        'descriptor': descriptor,
        if (actorUserId != null) 'actor_user_id': actorUserId,
      }),
    );
    final body = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode != 200 || body['success'] != true) {
      throw Exception(body['message'] ?? 'Face verification failed');
    }

    return FaceVerifyResult.fromJson(body['data'] as Map<String, dynamic>);
  }

  Future<AttendanceClockResult> clockAttendance({
    required String action,
    required int userId,
    required int branchId,
    required double latitude,
    required double longitude,
    int? actorUserId,
    double? accuracyMeters,
    String? deviceInfo,
    bool? faceVerified,
    bool tabletManual = false,
    String? photoBase64,
    String? photoMime,
  }) async {
    final uri = Uri.parse('$apiBaseUrl/attendance.php');
    final response = await http.post(
      uri,
      headers: _jsonHeaders,
      body: jsonEncode({
        'action': action,
        'user_id': userId,
        'branch_id': branchId,
        'latitude': latitude,
        'longitude': longitude,
        if (accuracyMeters != null) 'accuracy_meters': accuracyMeters,
        if (deviceInfo != null && deviceInfo.isNotEmpty) 'device_info': deviceInfo,
        if (faceVerified != null) 'face_verified': faceVerified,
        if (tabletManual) 'tablet_manual': true,
        if (photoBase64 != null && photoBase64.isNotEmpty) 'photo_base64': photoBase64,
        if (photoMime != null && photoMime.isNotEmpty) 'photo_mime': photoMime,
        'actor_user_id': actorUserId ?? userId,
      }),
    );
    final body = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode != 200 || body['success'] != true) {
      throw Exception(body['message'] ?? 'Attendance request failed');
    }

    return AttendanceClockResult.fromJson(
      body['data'] as Map<String, dynamic>,
    );
  }

  /// Lightweight check — tablet calls this before publishing cart snapshots.
  Future<bool> fetchMonitorActive() async {
    final uri = Uri.parse('$apiBaseUrl/monitor.php?action=active');
    final response = await http
        .get(uri)
        .timeout(const Duration(seconds: 4));
    if (response.statusCode != 200) return false;

    final body = jsonDecode(response.body);
    if (body is! Map || body['success'] != true) return false;
    final data = body['data'];
    if (data is! Map) return false;
    return data['active'] == true;
  }

  Future<void> publishMonitorState(Map<String, dynamic> payload) async {
    final uri = Uri.parse('$apiBaseUrl/monitor.php');
    final response = await http
        .post(
          uri,
          headers: _jsonHeaders,
          body: jsonEncode({
            'action': 'publish',
            ...payload,
          }),
        )
        .timeout(const Duration(seconds: 5));

    if (response.statusCode != 200) return;
    final body = jsonDecode(response.body);
    if (body is! Map || body['success'] != true) return;
  }

  Future<void> publishMonitorPresence(Map<String, dynamic> payload) async {
    final uri = Uri.parse('$apiBaseUrl/monitor.php');
    final response = await http
        .post(
          uri,
          headers: _jsonHeaders,
          body: jsonEncode({
            'action': 'presence',
            ...payload,
          }),
        )
        .timeout(const Duration(seconds: 4));

    if (response.statusCode != 200) return;
    final body = jsonDecode(response.body);
    if (body is! Map || body['success'] != true) return;
  }

  Future<void> publishMonitorDisconnect(Map<String, dynamic> payload) async {
    final uri = Uri.parse('$apiBaseUrl/monitor.php');
    try {
      final response = await http
          .post(
            uri,
            headers: _jsonHeaders,
            body: jsonEncode({
              'action': 'disconnect',
              ...payload,
            }),
          )
          .timeout(const Duration(seconds: 3));

      if (response.statusCode != 200) return;
      final body = jsonDecode(response.body);
      if (body is! Map || body['success'] != true) return;
    } catch (_) {}
  }

  void publishMonitorDisconnectBeacon(Map<String, dynamic> payload) {
    sendMonitorDisconnectBeacon(
      '$apiBaseUrl/monitor.php',
      payload,
    );
  }

  Future<PosMonitorLiveResult> fetchMonitorLive({String? revision}) async {
    final query = <String, String>{'action': 'live'};
    if (revision != null && revision.isNotEmpty) {
      query['revision'] = revision;
    }
    final uri = Uri.parse('$apiBaseUrl/monitor.php').replace(queryParameters: query);
    final response = await http
        .get(uri)
        .timeout(const Duration(seconds: 6));
    final body = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode != 200 || body['success'] != true) {
      throw Exception(body['message'] ?? 'Failed to load live POS monitor');
    }

    return PosMonitorLiveResult.fromJson(body['data'] as Map<String, dynamic>);
  }

  Future<PosMonitorWatchResult> watchMonitorLive({
    String? revision,
    int? actorUserId,
  }) async {
    final query = <String, String>{'action': 'watch'};
    if (revision != null && revision.isNotEmpty) {
      query['revision'] = revision;
    }
    if (actorUserId != null && actorUserId > 0) {
      query['actor_user_id'] = actorUserId.toString();
    }
    final uri = Uri.parse('$apiBaseUrl/monitor.php').replace(queryParameters: query);
    final response = await http
        .get(uri)
        .timeout(const Duration(seconds: 35));
    final body = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode != 200 || body['success'] != true) {
      throw Exception(body['message'] ?? 'Failed to watch live POS monitor');
    }

    return PosMonitorWatchResult.fromJson(body['data'] as Map<String, dynamic>);
  }

  Future<PosMonitorLiveResult> subscribeMonitorLive({
    required int actorUserId,
    String? revision,
  }) async {
    final uri = Uri.parse('$apiBaseUrl/monitor.php');
    final response = await http
        .post(
          uri,
          headers: _jsonHeaders,
          body: jsonEncode({
            'action': 'subscribe',
            'actor_user_id': actorUserId,
            if (revision != null && revision.isNotEmpty) 'revision': revision,
          }),
        )
        .timeout(const Duration(seconds: 6));
    final body = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode != 200 || body['success'] != true) {
      throw Exception(body['message'] ?? 'Failed to subscribe to live monitor');
    }

    return PosMonitorLiveResult.fromJson(body['data'] as Map<String, dynamic>);
  }

  Future<void> unsubscribeMonitorLive({required int actorUserId}) async {
    final uri = Uri.parse('$apiBaseUrl/monitor.php');
    await http
        .post(
          uri,
          headers: _jsonHeaders,
          body: jsonEncode({
            'action': 'unsubscribe',
            'actor_user_id': actorUserId,
          }),
        )
        .timeout(const Duration(seconds: 4));
  }

  Future<LiveWallSalesReport> fetchMonitorSalesReport({
    String? start,
    String? end,
  }) async {
    final day = start ?? _isoDate(DateTime.now());
    final endDay = end ?? day;
    final uri = Uri.parse('$apiBaseUrl/monitor.php').replace(
      queryParameters: {
        'action': 'sales',
        'start': day,
        'end': endDay,
      },
    );
    final response = await http.get(uri).timeout(const Duration(seconds: 8));
    final body = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode != 200 || body['success'] != true) {
      throw Exception(body['message'] ?? 'Failed to load live sales report');
    }

    return LiveWallSalesReport.fromJson(
      body['data'] as Map<String, dynamic>? ?? const {},
    );
  }

  Future<InventoryReport> fetchInventoryReport({
    required String start,
    required String end,
  }) async {
    final uri = Uri.parse('$apiBaseUrl/inventory_report.php').replace(
      queryParameters: {'start': start, 'end': end},
    );
    final response = await http.get(uri).timeout(const Duration(seconds: 12));
    final body = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode != 200 || body['success'] != true) {
      throw Exception(body['message'] ?? 'Failed to load inventory report');
    }

    return InventoryReport.fromJson(body);
  }

  String _isoDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }
}
