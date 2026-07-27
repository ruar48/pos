import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/app_settings.dart';
import '../../models/app_user.dart';
import '../../models/branch.dart';
import '../../models/coupon.dart';
import '../../models/product.dart';

class OfflineCatalogSnapshot {
  const OfflineCatalogSnapshot({
    required this.savedAt,
    required this.categories,
    required this.products,
    required this.settings,
    required this.coupons,
    required this.branches,
  });

  final DateTime savedAt;
  final List<ProductCategory> categories;
  final List<Product> products;
  final AppSettingsModel settings;
  final List<Coupon> coupons;
  final List<Branch> branches;
}

class OfflineCatalogStore {
  static const _prefsKey = 'offline_catalog_saved_at';

  static Future<File> _catalogFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/offline_pos_catalog.json');
  }

  static Future<bool> hasCatalog() async {
    return (await _catalogFile()).exists();
  }

  static Future<DateTime?> lastSavedAt() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  static Future<void> save({
    required List<ProductCategory> categories,
    required List<Product> products,
    required AppSettingsModel settings,
    required List<Coupon> coupons,
    required List<Branch> branches,
  }) async {
    final savedAt = DateTime.now();
    final payload = {
      'saved_at': savedAt.toIso8601String(),
      'categories': categories.map(_categoryToJson).toList(),
      'products': products.map(_productToJson).toList(),
      'settings': _settingsToJson(settings),
      'coupons': coupons.map(_couponToJson).toList(),
      'branches': branches.map(_branchToJson).toList(),
    };

    final file = await _catalogFile();
    await file.writeAsString(jsonEncode(payload));

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, savedAt.toIso8601String());
  }

  static Future<OfflineCatalogSnapshot?> load() async {
    final file = await _catalogFile();
    if (!await file.exists()) return null;

    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) return null;

      final categories = (decoded['categories'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => ProductCategory.fromJson(Map<String, dynamic>.from(item)))
          .toList();
      final products = (decoded['products'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => Product.fromJson(Map<String, dynamic>.from(item)))
          .toList();
      final settings = AppSettingsModel.fromJson(
        Map<String, dynamic>.from(
          (decoded['settings'] as Map?) ?? const {},
        ),
      );
      final coupons = (decoded['coupons'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => Coupon.fromJson(Map<String, dynamic>.from(item)))
          .toList();
      final branches = (decoded['branches'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => Branch.fromJson(Map<String, dynamic>.from(item)))
          .toList();
      final savedAt = DateTime.tryParse(
            (decoded['saved_at'] ?? '').toString(),
          ) ??
          (await lastSavedAt()) ??
          DateTime.fromMillisecondsSinceEpoch(0);

      return OfflineCatalogSnapshot(
        savedAt: savedAt,
        categories: categories,
        products: products,
        settings: settings,
        coupons: coupons,
        branches: branches,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> updateProducts(List<Product> products) async {
    final existing = await load();
    if (existing == null) return;
    await save(
      categories: existing.categories,
      products: products,
      settings: existing.settings,
      coupons: existing.coupons,
      branches: existing.branches,
    );
  }

  static Map<String, dynamic> _categoryToJson(ProductCategory category) => {
        'id': category.id,
        'name': category.name,
        if (category.icon != null) 'icon': category.icon,
      };

  static Map<String, dynamic> _productToJson(Product product) => {
        'id': product.id,
        'category_id': product.categoryId,
        'name': product.name,
        'price': product.price,
        'category_name': product.category,
        if (product.description != null) 'description': product.description,
        if (product.option != null) 'option': product.option,
        if (product.unit != null) 'unit': product.unit,
        if (product.stock != null) 'stock': product.stock,
        'reorder_level': product.reorderLevel,
        if (product.costPrice != null) 'cost_price': product.costPrice,
        if (product.deal != null) 'deal': product.deal,
        if (product.imageUrl != null) 'image_url': product.imageUrl,
        if (product.updatedAt != null)
          'updated_at': product.updatedAt!.toIso8601String(),
        'varieties': product.varieties.map((v) => v.toJson()).toList(),
      };

  static Map<String, dynamic> _settingsToJson(AppSettingsModel settings) => {
        'tax_rate': settings.taxRate,
        'auto_print_receipt': settings.autoPrintReceipt,
        'double_print_receipt': settings.doublePrintReceipt,
        'printer_host': settings.printerHost,
        'printer_type': settings.printerType,
        'printer_device': settings.printerDevice,
        'printer_port': settings.printerPort,
        'allow_negative_stock': settings.allowNegativeStock,
        'low_stock_email_enabled': settings.lowStockEmailEnabled,
        'low_stock_email_recipients': settings.lowStockEmailRecipients,
        'loyalty_enabled': settings.loyaltyEnabled,
        'loyalty_points_per_unit': settings.loyaltyPointsPerUnit,
        'loyalty_spend_unit': settings.loyaltySpendUnit,
        'loyalty_redeem_points_per_peso': settings.loyaltyRedeemPointsPerPeso,
        'currency_symbol': settings.currencySymbol,
        if (settings.receiptStore != null) 'receipt_store': settings.receiptStore,
        if (settings.defaultBranchId != null)
          'default_branch_id': settings.defaultBranchId,
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
        'settings_revision': settings.settingsRevision,
        'has_cash_drawer_pin': settings.hasCashDrawerPin,
      };

  static Map<String, dynamic> _couponToJson(Coupon coupon) => {
        'id': coupon.id,
        'code': coupon.code,
        if (coupon.description != null) 'description': coupon.description,
        'discount_type':
            coupon.discountType == CouponDiscountType.percentage
                ? 'percentage'
                : 'fixed',
        'discount_value': coupon.discountValue,
        'min_order_amount': coupon.minOrderAmount,
        'start_date': coupon.startDate.toIso8601String(),
        'end_date': coupon.endDate.toIso8601String(),
        if (coupon.maxUses != null) 'max_uses': coupon.maxUses,
        'usage_count': coupon.usageCount,
        'status': coupon.isActive ? 1 : 0,
        if (coupon.createdAt != null)
          'created_at': coupon.createdAt!.toIso8601String(),
      };

  static Map<String, dynamic> _branchToJson(Branch branch) => {
        'id': branch.id,
        'name': branch.name,
        if (branch.location != null) 'location': branch.location,
        if (branch.code != null) 'code': branch.code,
      };
}

class OfflineSessionStore {
  static const _userKey = 'offline_pos_last_user';

  static Future<void> saveUser(AppUser user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _userKey,
      jsonEncode({
        'id': user.id,
        'full_name': user.fullName,
        'username': user.username,
        'email': user.email,
        'role': user.role,
        'saved_at': DateTime.now().toIso8601String(),
      }),
    );
  }

  static Future<AppUser?> loadUser() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_userKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return AppUser.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  static Future<void> clearUser() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_userKey);
  }
}
