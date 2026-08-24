import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/utils/layout_utils.dart';
import '../../../core/utils/format_utils.dart';
import '../../../core/utils/top_toast.dart';
import '../../../models/checkout_completion.dart';
import '../../../models/app_settings.dart';
import '../../../models/audit_log_entry.dart';
import '../../../models/branch.dart';
import '../../../models/app_user.dart';
import '../../../models/staff_payment.dart';
import '../../../models/staff_user.dart';
import '../../../models/cart_item.dart';
import '../../../models/coupon.dart';
import '../../../models/customer.dart';
import '../../../models/held_transaction.dart';
import '../../../models/loyalty_card.dart';
import '../../../models/product.dart';
import '../../../models/product_variety.dart';
import '../../../models/nfc_customer_lookup.dart';
import '../../../models/device_printer_settings.dart';
import '../../../models/printer_settings.dart';
import '../../../models/sales_history_record.dart';
import '../../../services/offline/offline_catalog_store.dart';
import '../../../services/offline/offline_order_queue.dart';
import '../../../services/offline/offline_stock.dart';
import '../../../services/offline/pos_connectivity.dart';
import '../../../services/pos_api.dart';
import '../../receipt/receipt_printer.dart';
import '../widgets/app_drawer.dart';
import '../widgets/app_drawer_section.dart';
import '../widgets/cart_section.dart';
import '../widgets/charge_payment_section.dart';
import '../widgets/offline_status_banner.dart';
import '../widgets/product_section.dart';
import '../widgets/receipt_panel.dart';
import '../widgets/size_picker_sheet.dart';
import '../widgets/variety_picker_sheet.dart';

class PosHomePage extends StatefulWidget {
  const PosHomePage({
    super.key,
    required this.currentUser,
  });

  final AppUser currentUser;

  @override
  State<PosHomePage> createState() => PosHomePageState();
}

class PosHomePageState extends State<PosHomePage> with WidgetsBindingObserver {
  final api = const PosApi();
  String selectedCategory = 'All';
  String orderType = 'Retail';
  Customer? selectedCustomer;
  bool isLoadingProducts = true;
  String? loadError;
  List<ProductCategory> categories = [];
  List<Product> products = [];
  final customers = <Customer>[];
  final loyaltyCards = <LoyaltyCard>[];
  final heldTransactions = <HeldTransaction>[];
  final salesHistory = <SalesHistoryRecord>[];
  final branches = <Branch>[Branch.mainBranch];
  final coupons = <Coupon>[];
  final staffUsers = <StaffUser>[];
  final staffPayments = <StaffPayment>[];
  final auditLogs = <AuditLogEntry>[];
  int activeBranchId = 1;
  static const int allBranchesMonitorId = 0;
  int dashboardMonitorBranchId = allBranchesMonitorId;
  final searchController = TextEditingController();
  final cart = <CartItem>[];
  bool isPaymentMode = false;
  ReceiptData? completedReceipt;
  double manualDiscount = 0;
  String appliedCouponCode = '';
  double appliedCouponDiscount = 0;
  int loyaltyPointsRedeemed = 0;
  int _nextHoldId = 1;
  AppSettingsModel settings = const AppSettingsModel(
    taxRate: 0.12,
    autoPrintReceipt: true,
    printerHost: '',
    allowNegativeStock: false,
    loyaltyEnabled: true,
    loyaltyPointsPerUnit: 50,
    loyaltySpendUnit: 1000,
    loyaltyRedeemPointsPerPeso: 10,
    currencySymbol: '\u20B1',
  );
  String printerHost = '';
  PrinterConfig devicePrinter = const PrinterConfig();
  bool devicePrinterConfigured = false;
  ReceiptStoreConfig receiptStore = const ReceiptStoreConfig();
  final catalogRevision = ValueNotifier<int>(0);
  Timer? _monitorSuccessResetTimer;
  Timer? _monitorPresenceTimer;
  int _monitorPublishSeq = 0;
  bool _monitorPublishRunning = false;
  bool _monitorPublishAgain = false;
  String? _forcedMonitorStatus;
  String _stockSyncRevision = '0';
  bool _stockSyncInFlight = false;
  String _settingsSyncRevision = '0';
  bool _settingsSyncInFlight = false;
  bool _catalogSyncInFlight = false;
  bool _catalogWatchLoopActive = false;
  bool _productTapInFlight = false;
  bool _offlineSyncInFlight = false;
  int pendingOfflineCount = 0;
  DateTime? offlineCatalogSavedAt;
  VoidCallback? _connectivityListener;

  bool get isOfflineMode => PosConnectivity.instance.isOffline;

  bool get isSyncingCatalog => _catalogSyncInFlight;

  PrinterConfig get resolvedPrinter {
    if (devicePrinterConfigured) return devicePrinter;
    return PrinterConfig.fromSettings(settings);
  }

  String get resolvedPrinterHost {
    final fromDevice = resolvedPrinter.host.trim();
    if (fromDevice.isNotEmpty) return fromDevice;
    return printerHost.trim();
  }

  bool get isPrinterConfigured => resolvedPrinter.isConfigured;

  String missingPrinterMessage({required bool canManageSettings}) {
    return 'Configure this tablet\'s printer in the menu → My Printer.';
  }

  List<Product> get filteredProducts {
    final query = searchController.text.trim().toLowerCase();
    return products.where((product) {
      final matchesCategory =
          selectedCategory == 'All' || product.category == selectedCategory;
      final matchesSearch = query.isEmpty ||
          product.name.toLowerCase().contains(query) ||
          product.category.toLowerCase().contains(query);
      return matchesCategory && matchesSearch;
    }).toList();
  }

  double get subtotal => cart.fold(0, (sum, item) => sum + item.total);
  double get couponDiscount {
    if (appliedCouponCode.isEmpty) return 0;
    final coupon = _findCouponByCode(appliedCouponCode);
    if (coupon != null) {
      return coupon.discountForSubtotal(subtotal);
    }
    return appliedCouponDiscount.clamp(0, subtotal).toDouble();
  }

  double get totalDiscount =>
      (manualDiscount + couponDiscount + loyaltyDiscountAmount)
          .clamp(0, subtotal)
          .toDouble();
  double get netSubtotal => (subtotal - totalDiscount).clamp(0, subtotal);
  double get vatAmount => netSubtotal * settings.taxRate;
  double get grandTotal => netSubtotal + vatAmount;
  double get loyaltyDiscountAmount => settings
      .pesoValueForPoints(loyaltyPointsRedeemed)
      .clamp(0, subtotal)
      .toDouble();

  bool get isMonitoringAllBranches =>
      dashboardMonitorBranchId == allBranchesMonitorId;

  int? get dashboardBranchFilter =>
      isMonitoringAllBranches ? null : dashboardMonitorBranchId;

  Branch? get activeBranch {
    for (final branch in branches) {
      if (branch.id == activeBranchId) return branch;
    }
    return branches.isNotEmpty ? branches.first : Branch.mainBranch;
  }

  Branch? get monitoredBranch {
    if (isMonitoringAllBranches) return null;
    for (final branch in branches) {
      if (branch.id == dashboardMonitorBranchId) return branch;
    }
    return activeBranch;
  }

  String get monitoredBranchLabel {
    if (!widget.currentUser.canMonitorAllBranches) {
      return activeBranch?.name ?? 'Main Branch';
    }
    if (isMonitoringAllBranches) return 'All Branches';
    return monitoredBranch?.name ?? 'Main Branch';
  }

  List<SalesHistoryRecord> salesHistoryForDashboard() {
    return List<SalesHistoryRecord>.from(salesHistory);
  }

  void selectCategory(String category) {
    setState(() => selectedCategory = category);
  }

  void refreshView() {
    setState(() {});
  }

  void _scheduleMonitorPublish() {
    _queueMonitorPublish();
  }

  void _publishMonitorNow({String? status}) {
    if (status != null) {
      _forcedMonitorStatus = status;
    }
    _queueMonitorPublish();
  }

  void _queueMonitorPublish() {
    _monitorPublishAgain = true;
    if (_monitorPublishRunning) {
      return;
    }
    unawaited(_drainMonitorPublishQueue());
  }

  Future<void> _drainMonitorPublishQueue() async {
    _monitorPublishRunning = true;
    while (_monitorPublishAgain) {
      _monitorPublishAgain = false;
      final seq = ++_monitorPublishSeq;
      final forcedStatus = _forcedMonitorStatus;
      _forcedMonitorStatus = null;
      await _publishMonitorStateIfWatched(
        status: forcedStatus,
        publishSeq: seq,
      );
    }
    _monitorPublishRunning = false;
  }

  void publishMonitorPaymentProcessing() {
    _publishMonitorNow(status: 'payment');
  }

  Map<String, dynamic>? _monitorSuccessFromReceipt(ReceiptData receipt) {
    final items = receipt.items
        .map(
          (item) => {
            'name': item.name,
            'quantity': item.quantity,
            'price': item.unitPrice,
            'total': item.total,
          },
        )
        .toList();

    return {
      'invoice_number': receipt.invoiceNumber,
      'payment_method': receipt.paymentMethod,
      'total': receipt.total,
      'customer_name': receipt.customerName,
      'items': items,
      'completed_at': receipt.dateTime.toIso8601String(),
    };
  }

  String _monitorStatus() {
    if (completedReceipt != null) return 'success';
    if (isPaymentMode) return 'payment';
    if (cart.isNotEmpty) return 'cart';
    return 'idle';
  }

  String get _monitorRegisterId {
    final base = receiptStore.posTerminalId.trim().isEmpty
        ? 'POS'
        : receiptStore.posTerminalId.trim();
    return '$base-u${widget.currentUser.id}';
  }

  String get _monitorRegisterLabel => widget.currentUser.fullName;

  String get _monitorRegisterCode {
    final code = receiptStore.posTerminalId.trim();
    return code.isEmpty ? 'POS' : code;
  }

  List<Map<String, dynamic>> _monitorItemsFromCart() {
    return cart
        .map(
          (item) => {
            'name': item.displayName,
            'quantity': item.quantity,
            'price': item.unitPrice,
            'total': item.total,
          },
        )
        .toList();
  }

  Map<String, dynamic> _monitorPayload({
    String? status,
    Map<String, dynamic>? success,
    List<Map<String, dynamic>>? items,
    double? subtotalValue,
    double? discountValue,
    double? vatValue,
    double? totalValue,
    String? customerName,
    bool monitorReset = false,
    int? publishSeq,
  }) {
    final receipt = completedReceipt;
    final resolvedStatus = status ?? _monitorStatus();
    final successPayload = success ??
        (receipt != null && resolvedStatus == 'success'
            ? _monitorSuccessFromReceipt(receipt)
            : null);
    final itemRows = items ??
        (receipt != null && resolvedStatus == 'success'
            ? receipt.items
                .map(
                  (item) => {
                    'name': item.name,
                    'quantity': item.quantity,
                    'price': item.unitPrice,
                    'total': item.total,
                  },
                )
                .toList()
            : _monitorItemsFromCart());
    final itemCount = itemRows.fold<double>(
      0,
      (sum, item) => sum + (item['quantity'] as num).toDouble(),
    );

    return {
      'terminal_id': _monitorRegisterId,
      'terminal_label': _monitorRegisterLabel,
      'register_code': _monitorRegisterCode,
      'branch_id': activeBranchId,
      'branch_name': activeBranch?.name ?? 'Main Branch',
      'cashier_id': widget.currentUser.id,
      'cashier_name': widget.currentUser.fullName,
      'cashier_username': widget.currentUser.username,
      'customer_name': customerName ??
          receipt?.customerName ??
          selectedCustomer?.customerName ??
          'Walk-in',
      'order_type': orderType,
      'status': resolvedStatus,
      'is_payment_mode': isPaymentMode,
      'items': itemRows,
      'item_count': itemCount,
      'subtotal': subtotalValue ?? receipt?.subtotal ?? subtotal,
      'discount': discountValue ?? receipt?.discount ?? totalDiscount,
      'vat': vatValue ?? receipt?.vat ?? vatAmount,
      'total': totalValue ?? receipt?.total ?? grandTotal,
      if (successPayload != null) 'success': successPayload,
      if (monitorReset) 'monitor_reset': true,
      if (publishSeq != null) 'publish_seq': publishSeq,
    };
  }

  Future<void> _publishMonitorPresence() async {
    try {
      await api.publishMonitorPresence({
        'terminal_id': _monitorRegisterId,
        'terminal_label': _monitorRegisterLabel,
        'register_code': _monitorRegisterCode,
        'branch_id': activeBranchId,
        'branch_name': activeBranch?.name ?? 'Main Branch',
        'cashier_id': widget.currentUser.id,
        'cashier_name': widget.currentUser.fullName,
        'cashier_username': widget.currentUser.username,
        'customer_name':
            selectedCustomer?.displayName ?? 'Walk-in',
        'order_type': orderType,
        'status': _monitorStatus(),
        'total': grandTotal,
      });
    } catch (_) {
      // Best-effort heartbeat for the live wall.
    }
  }

  void _startMonitorPresenceHeartbeat() {
    _monitorPresenceTimer?.cancel();
    unawaited(_publishMonitorPresence());
    _monitorPresenceTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (!mounted) return;
      unawaited(_publishMonitorPresence());
    });
  }

  Future<void> _publishMonitorDisconnect() async {
    final payload = {
      'terminal_id': _monitorRegisterId,
      'terminal_label': _monitorRegisterLabel,
      'register_code': _monitorRegisterCode,
      'cashier_id': widget.currentUser.id,
    };
    api.publishMonitorDisconnectBeacon(payload);
    try {
      await api.publishMonitorDisconnect(payload);
    } catch (_) {
      // Best-effort cleanup for the live wall.
    }
  }

  Future<void> _publishMonitorStateIfWatched({
    String? status,
    Map<String, dynamic>? success,
    List<Map<String, dynamic>>? items,
    double? subtotalValue,
    double? discountValue,
    double? vatValue,
    double? totalValue,
    String? customerName,
    bool monitorReset = false,
    int? publishSeq,
  }) async {
    try {
      await api.publishMonitorState(
        _monitorPayload(
          status: status,
          success: success,
          items: items,
          subtotalValue: subtotalValue,
          discountValue: discountValue,
          vatValue: vatValue,
          totalValue: totalValue,
          customerName: customerName,
          monitorReset: monitorReset,
          publishSeq: publishSeq,
        ),
      );
    } catch (_) {
      // Monitor is best-effort; never block checkout.
    }
  }

  Future<void> _publishMonitorSuccess(ReceiptData receipt) async {
    final items = receipt.items
        .map(
          (item) => {
            'name': item.name,
            'quantity': item.quantity,
            'price': item.unitPrice,
            'total': item.total,
          },
        )
        .toList();
    final success = _monitorSuccessFromReceipt(receipt)!;

    await _publishMonitorStateIfWatched(
      status: 'success',
      items: items,
      subtotalValue: receipt.subtotal,
      discountValue: receipt.discount,
      vatValue: receipt.vat,
      totalValue: receipt.total,
      customerName: receipt.customerName,
      success: success,
      publishSeq: ++_monitorPublishSeq,
    );

    _monitorSuccessResetTimer?.cancel();
    _monitorSuccessResetTimer = Timer(const Duration(seconds: 12), () {
      if (!mounted) return;
      unawaited(
        _publishMonitorStateIfWatched(
          status: 'idle',
          monitorReset: true,
        ),
      );
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    searchController.addListener(refreshView);
    _connectivityListener = () {
      if (!mounted) return;
      setState(() {});
      if (PosConnectivity.instance.isOnline) {
        unawaited(_syncPendingOfflineOrders());
      }
    };
    PosConnectivity.instance.addListener(_connectivityListener!);
    unawaited(PosConnectivity.instance.start());
    loadInitialData();
  }

  @override
  void dispose() {
    _monitorSuccessResetTimer?.cancel();
    _monitorPresenceTimer?.cancel();
    unawaited(_publishMonitorDisconnect());
    if (_connectivityListener != null) {
      PosConnectivity.instance.removeListener(_connectivityListener!);
    }
    unawaited(PosConnectivity.instance.disposeListener());
    WidgetsBinding.instance.removeObserver(this);
    catalogRevision.dispose();
    searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(PosConnectivity.instance.refresh(force: true));
      unawaited(_syncPendingOfflineOrders());
      unawaited(_syncProductStock());
      unawaited(_syncAppSettings());
      unawaited(_publishMonitorPresence());
    }
  }

  /// Latest catalog row for [id], or null if not loaded.
  Product? productById(int id) => _productById(id);

  Future<void> loadInitialData() async {
    setState(() {
      isLoadingProducts = true;
      loadError = null;
    });

    unawaited(PosConnectivity.instance.refresh(force: true));

    final prefs = await SharedPreferences.getInstance();
    final savedPrinterHost = prefs.getString('printer_host') ?? '';
    final savedDevicePrinter = await DevicePrinterSettings.load();
    final savedBranchId = prefs.getInt('active_branch_id') ?? 1;
    final savedMonitorBranchId = prefs.getInt('dashboard_monitor_branch_id');
    var loadedReceiptStore = await ReceiptStoreConfig.loadFromPrefs();

    String? catalogError;
    var loadedCategories = <ProductCategory>[];
    var loadedProducts = <Product>[];
    var loadedSettings = settings;
    var loadedBranches = <Branch>[];
    var loadedCoupons = <Coupon>[];

    final cachedCatalog = await OfflineCatalogStore.load();
    if (cachedCatalog != null && cachedCatalog.products.isNotEmpty) {
      loadedCategories = cachedCatalog.categories;
      loadedProducts = cachedCatalog.products;
      loadedSettings = cachedCatalog.settings;
      loadedCoupons = cachedCatalog.coupons;
      if (cachedCatalog.branches.isNotEmpty) {
        loadedBranches = cachedCatalog.branches;
      }
      offlineCatalogSavedAt = cachedCatalog.savedAt;
      if (mounted) {
        _applyInitialCatalogState(
          savedPrinterHost: savedPrinterHost,
          savedDevicePrinter: savedDevicePrinter,
          savedBranchId: savedBranchId,
          savedMonitorBranchId: savedMonitorBranchId,
          loadedReceiptStore: loadedReceiptStore,
          loadedCategories: loadedCategories,
          loadedProducts: loadedProducts,
          loadedSettings: loadedSettings,
          loadedBranches: loadedBranches,
          loadedCoupons: loadedCoupons,
          catalogError: null,
        );
      }
    }

    try {
      final catalogResults = await Future.wait<dynamic>([
        api.fetchCategories(),
        api.fetchItems(),
      ]).timeout(
        PosApi.catalogLoadTimeout,
        onTimeout: () => throw TimeoutException('Catalog load timed out'),
      );
      loadedCategories = catalogResults[0] as List<ProductCategory>;
      loadedProducts = catalogResults[1] as List<Product>;
      catalogError = null;
      PosConnectivity.instance.noteApiReachable();
    } catch (_) {
      if (loadedProducts.isEmpty) {
        catalogError =
            'Could not load products. Connect to the internet once, then you can sell offline.';
      }
    }

    pendingOfflineCount = await OfflineOrderQueue.pendingCount();

    if (mounted) {
      _applyInitialCatalogState(
        savedPrinterHost: savedPrinterHost,
        savedDevicePrinter: savedDevicePrinter,
        savedBranchId: savedBranchId,
        savedMonitorBranchId: savedMonitorBranchId,
        loadedReceiptStore: loadedReceiptStore,
        loadedCategories: loadedCategories,
        loadedProducts: loadedProducts,
        loadedSettings: loadedSettings,
        loadedBranches: loadedBranches,
        loadedCoupons: loadedCoupons,
        catalogError: catalogError,
      );
    }

    unawaited(
      _loadSecondaryPosData(
        savedPrinterHost: savedPrinterHost,
        savedBranchId: savedBranchId,
        savedMonitorBranchId: savedMonitorBranchId,
        initialSettings: loadedSettings,
        initialReceiptStore: loadedReceiptStore,
        loadedCategories: loadedCategories,
        loadedProducts: loadedProducts,
        initialBranches: loadedBranches,
        initialCoupons: loadedCoupons,
      ),
    );
  }

  void _applyInitialCatalogState({
    required String savedPrinterHost,
    required DevicePrinterSettings savedDevicePrinter,
    required int savedBranchId,
    required int? savedMonitorBranchId,
    required ReceiptStoreConfig loadedReceiptStore,
    required List<ProductCategory> loadedCategories,
    required List<Product> loadedProducts,
    required AppSettingsModel loadedSettings,
    required List<Branch> loadedBranches,
    required List<Coupon> loadedCoupons,
    required String? catalogError,
  }) {
    setState(() {
      devicePrinter = savedDevicePrinter.config;
      devicePrinterConfigured = savedDevicePrinter.hasLocalConfig;
      printerHost = loadedSettings.printerHost.isNotEmpty
          ? loadedSettings.printerHost
          : savedPrinterHost;
      receiptStore = loadedReceiptStore;
      categories = loadedCategories;
      products = loadedProducts;
      loadError = loadedProducts.isEmpty ? catalogError : null;
      settings = loadedSettings;
      branches
        ..clear()
        ..addAll(loadedBranches);
      if (branches.isEmpty) branches.add(Branch.mainBranch);
      activeBranchId = savedBranchId;
      if (loadedSettings.defaultBranchId != null &&
          loadedSettings.defaultBranchId! > 0 &&
          branches.any((branch) => branch.id == loadedSettings.defaultBranchId)) {
        activeBranchId = loadedSettings.defaultBranchId!;
      }
      if (!branches.any((branch) => branch.id == activeBranchId)) {
        activeBranchId = branches.first.id;
      }
      if (widget.currentUser.canMonitorAllBranches) {
        dashboardMonitorBranchId = savedMonitorBranchId ?? allBranchesMonitorId;
      } else {
        dashboardMonitorBranchId = activeBranchId;
      }
      coupons
        ..clear()
        ..addAll(loadedCoupons);
      isLoadingProducts = false;
      catalogRevision.value++;
    });
  }

  Future<void> _loadSecondaryPosData({
    required String savedPrinterHost,
    required int savedBranchId,
    required int? savedMonitorBranchId,
    required AppSettingsModel initialSettings,
    required ReceiptStoreConfig initialReceiptStore,
    required List<ProductCategory> loadedCategories,
    required List<Product> loadedProducts,
    required List<Branch> initialBranches,
    required List<Coupon> initialCoupons,
  }) async {
    var loadedCustomers = <Customer>[];
    var loadedLoyaltyCards = <LoyaltyCard>[];
    var loadedSalesHistory = <SalesHistoryRecord>[];
    var loadedSettings = initialSettings;
    var loadedReceiptStore = initialReceiptStore;
    var loadedBranches = List<Branch>.from(initialBranches);
    var loadedCoupons = List<Coupon>.from(initialCoupons);

    try {
      loadedCustomers = await api.fetchCustomers();
    } catch (_) {}
    try {
      loadedLoyaltyCards = await api.fetchLoyaltyCards();
    } catch (_) {}
    try {
      loadedSalesHistory = await api.fetchSalesHistory();
    } catch (_) {}
    try {
      loadedSettings = await api.fetchSettings();
      if (loadedSettings.receiptStore != null &&
          loadedSettings.receiptStore!.isNotEmpty) {
        loadedReceiptStore = await ReceiptStoreConfig.applyApiPayload(
          loadedSettings.receiptStore,
        );
      }
    } catch (_) {}
    try {
      loadedBranches = await api.fetchBranches();
    } catch (_) {}
    try {
      loadedCoupons = await api.fetchCoupons();
    } catch (_) {}

    if (loadedProducts.isNotEmpty) {
      try {
        await OfflineCatalogStore.save(
          categories: loadedCategories,
          products: loadedProducts,
          settings: loadedSettings,
          coupons: loadedCoupons,
          branches: loadedBranches.isNotEmpty
              ? loadedBranches
              : [Branch.mainBranch],
        );
        offlineCatalogSavedAt = DateTime.now();
      } catch (_) {}
    }

    if (!mounted) return;
    setState(() {
      printerHost = loadedSettings.printerHost.isNotEmpty
          ? loadedSettings.printerHost
          : savedPrinterHost;
      receiptStore = loadedReceiptStore;
      customers
        ..clear()
        ..addAll(loadedCustomers.where((customer) => !customer.isWalkIn));
      loyaltyCards
        ..clear()
        ..addAll(loadedLoyaltyCards);
      salesHistory
        ..clear()
        ..addAll(loadedSalesHistory);
      settings = loadedSettings;
      branches
        ..clear()
        ..addAll(loadedBranches);
      if (branches.isEmpty) branches.add(Branch.mainBranch);
      activeBranchId = savedBranchId;
      if (loadedSettings.defaultBranchId != null &&
          loadedSettings.defaultBranchId! > 0 &&
          branches.any((branch) => branch.id == loadedSettings.defaultBranchId)) {
        activeBranchId = loadedSettings.defaultBranchId!;
      }
      if (!branches.any((branch) => branch.id == activeBranchId)) {
        activeBranchId = branches.first.id;
      }
      if (widget.currentUser.canMonitorAllBranches) {
        dashboardMonitorBranchId = savedMonitorBranchId ?? allBranchesMonitorId;
      } else {
        dashboardMonitorBranchId = activeBranchId;
      }
      coupons
        ..clear()
        ..addAll(loadedCoupons);
      _settingsSyncRevision = loadedSettings.settingsRevision;
    });
    _startMonitorPresenceHeartbeat();
    unawaited(_refreshStockSyncRevision());
    _startCatalogWatchLoop();
    if (PosConnectivity.instance.isOnline) {
      unawaited(_syncPendingOfflineOrders());
    }
  }

  void _startCatalogWatchLoop() {
    if (_catalogWatchLoopActive) return;
    _catalogWatchLoopActive = true;
    unawaited(_runCatalogWatchLoop());
  }

  Future<void> _runCatalogWatchLoop() async {
    while (mounted) {
      if (isOfflineMode) {
        await Future<void>.delayed(const Duration(seconds: 5));
        continue;
      }

      try {
        final result = await api.watchCatalogSync(
          stockRevision: _stockSyncRevision,
          settingsRevision: _settingsSyncRevision,
        );
        if (!mounted) return;

        if (result.stockChanged) {
          unawaited(_syncProductStock());
        }
        if (result.settingsChanged) {
          unawaited(_syncAppSettings());
        }
      } catch (_) {
        // Best-effort live catalog watch; retry after a short backoff.
        await Future<void>.delayed(const Duration(seconds: 3));
      }
    }
  }

  Future<void> promptAddProductToCart(
    BuildContext context,
    Product product,
  ) async {
    if (_productTapInFlight) return;
    _productTapInFlight = true;
    try {
      await _addProductToCart(context, product);
    } finally {
      _productTapInFlight = false;
    }
  }

  /// Shared by [promptAddProductToCart] and [promptAddProductGroupToCart] -
  /// doesn't touch `_productTapInFlight` itself, so the group picker can
  /// call this directly with the chosen size once its sheet closes instead
  /// of going back through [promptAddProductToCart], which would just bail
  /// out immediately since the group picker is still holding that guard.
  Future<void> _addProductToCart(BuildContext context, Product product) async {
    unawaited(_syncProductStock());

    if (completedReceipt != null) {
      dismissCompletedReceipt();
    }
    if (isPaymentMode) {
      exitPaymentMode();
    }

    final live = productById(product.id) ?? product;
    if (!live.hasVarieties) {
      addToCart(live);
      return;
    }

    unawaited(_syncProductStock());

    if (!context.mounted) return;
    await showProductVarietyPicker(context, this, live);
  }

  /// Entry point used by the product grid, which groups catalog entries
  /// that share the same name (e.g. the same chemical listed separately
  /// per bottle size) so the cashier picks the size before it's added.
  Future<void> promptAddProductGroupToCart(
    BuildContext context,
    List<Product> group,
  ) async {
    if (group.length <= 1) {
      return promptAddProductToCart(context, group.first);
    }
    if (_productTapInFlight) return;
    _productTapInFlight = true;
    try {
      unawaited(_syncProductStock());

      if (completedReceipt != null) {
        dismissCompletedReceipt();
      }
      if (isPaymentMode) {
        exitPaymentMode();
      }

      if (!context.mounted) return;
      final selected = await showProductSizePicker(context, this, group);
      if (selected != null && context.mounted) {
        await _addProductToCart(context, selected);
      }
    } finally {
      _productTapInFlight = false;
    }
  }

  void addToCart(Product product, {ProductVariety? variety}) {
    setCartQuantity(product, quantityInCart(product, variety: variety) + 1,
        variety: variety);
  }

  double quantityInCart(Product product, {ProductVariety? variety}) {
    final liveProduct = _productById(product.id) ?? product;
    final liveVariety = variety == null
        ? null
        : (_varietyById(liveProduct, variety.id) ?? variety);
    final index = cart.indexWhere(
      (item) =>
          item.product.id == liveProduct.id &&
          item.variety?.id == liveVariety?.id,
    );
    return index == -1 ? 0 : cart[index].quantity;
  }

  double? maxCartQuantity(Product product, {ProductVariety? variety}) {
    if (settings.allowNegativeStock) return null;
    final liveProduct = _productById(product.id) ?? product;
    if (variety != null) {
      final liveVariety = _varietyById(liveProduct, variety.id) ?? variety;
      return liveVariety.stock;
    }
    return liveProduct.stock;
  }

  void setCartQuantity(
    Product product,
    double quantity, {
    ProductVariety? variety,
  }) {
    if (completedReceipt != null) {
      dismissCompletedReceipt();
    }
    if (isPaymentMode) {
      exitPaymentMode();
    }

    final liveProduct = _productById(product.id) ?? product;

    if (variety == null && liveProduct.hasVarieties) {
      return;
    }

    final liveVariety = variety == null
        ? null
        : (_varietyById(liveProduct, variety.id) ?? variety);

    final index = cart.indexWhere(
      (item) =>
          item.product.id == liveProduct.id &&
          item.variety?.id == liveVariety?.id,
    );

    if (quantity <= 0) {
      if (index != -1) {
        setState(() => cart.removeAt(index));
        _publishMonitorNow();
      }
      return;
    }

    final stockMessage =
        _stockLimitMessage(liveProduct, quantity, variety: liveVariety);
    if (stockMessage != null) {
      showAppTopWarning(stockMessage);
      return;
    }

    setState(() {
      if (index == -1) {
        cart.insert(
          0,
          CartItem(
            product: liveProduct,
            variety: liveVariety,
            quantity: quantity,
          ),
        );
      } else {
        final item = cart.removeAt(index);
        item.quantity = quantity;
        cart.insert(0, item);
      }
    });
    _publishMonitorNow();
  }

  void updateQuantity(CartItem item, double delta) {
    final liveProduct = _productById(item.product.id) ?? item.product;
    final nextQty = item.quantity + delta;
    if (delta > 0) {
      final stockMessage =
          _stockLimitMessage(liveProduct, nextQty, variety: item.variety);
      if (stockMessage != null) {
        showAppTopWarning(stockMessage);
        return;
      }
    }

    setState(() {
      item.quantity += delta;
      if (item.quantity <= 0) cart.remove(item);
    });
    _publishMonitorNow();
  }

  void setQuantity(CartItem item, double quantity) {
    final liveProduct = _productById(item.product.id) ?? item.product;
    if (quantity > 0) {
      final stockMessage =
          _stockLimitMessage(liveProduct, quantity, variety: item.variety);
      if (stockMessage != null) {
        showAppTopWarning(stockMessage);
        return;
      }
    }

    setState(() {
      if (quantity <= 0) {
        cart.remove(item);
      } else {
        item.quantity = quantity;
      }
    });
    _publishMonitorNow();
  }

  bool canIncreaseCartQuantity(CartItem item) {
    if (settings.allowNegativeStock) return true;
    final liveProduct = _productById(item.product.id) ?? item.product;
    if (item.variety != null) {
      final liveVariety =
          _varietyById(liveProduct, item.variety!.id) ?? item.variety!;
      final stock = liveVariety.stock;
      if (stock == null) return true;
      return item.quantity < stock;
    }
    final stock = liveProduct.stock;
    if (stock == null) return true;
    return item.quantity < stock;
  }

  Product? _productById(int id) {
    for (final product in products) {
      if (product.id == id) return product;
    }
    return null;
  }

  ProductVariety? _varietyById(Product product, int id) {
    for (final variety in product.varieties) {
      if (variety.id == id) return variety;
    }
    return null;
  }

  String? _stockLimitMessage(
    Product product,
    double requestedQty, {
    ProductVariety? variety,
  }) {
    if (settings.allowNegativeStock) return null;

    final live = _productById(product.id) ?? product;

    if (variety != null) {
      final liveVariety = _varietyById(live, variety.id) ?? variety;
      final stock = liveVariety.stock;
      if (stock == null) return null;
      if (requestedQty <= stock) return null;
      final label = '${live.name} - ${liveVariety.name}';
      if (stock <= 0) return '$label is out of stock';
      return 'Only ${formatQuantity(stock)} in stock for $label';
    }

    final stock = live.stock;
    if (stock == null) return null;

    if (requestedQty <= stock) return null;
    if (stock <= 0) return '${live.name} is out of stock';
    return 'Only ${formatQuantity(stock)} in stock for ${live.name}';
  }

  void removeItem(CartItem item) {
    setState(() => cart.remove(item));
    _scheduleMonitorPublish();
  }

  void clearCart({bool publishMonitor = true}) {
    setState(() {
      cart.clear();
      _resetAdjustments();
    });
    if (publishMonitor && completedReceipt == null) {
      _scheduleMonitorPublish();
    }
  }

  void resetCustomer() {
    setState(() {
      selectedCustomer = null;
      loyaltyPointsRedeemed = 0;
    });
  }

  void setOrderType(String value) {
    setState(() {
      orderType = value;
    });
    _scheduleMonitorPublish();
  }

  LoyaltyCard? loyaltyCardFor(Customer customer) {
    for (final card in loyaltyCards) {
      if (card.customerId == customer.id) return card;
    }
    return null;
  }

  bool canUseLoyalty(Customer? customer) {
    if (customer == null || customer.isWalkIn || !settings.loyaltyEnabled) {
      return false;
    }
    return loyaltyCardFor(customer) != null;
  }

  bool customerEarnsLoyalty(Customer? customer) {
    if (customer == null || customer.isWalkIn || !settings.loyaltyEnabled) {
      return false;
    }
    return true;
  }

  void selectExistingCustomer(Customer customer) {
    setState(() {
      selectedCustomer = customer;
      orderType = customer.orderType;
      loyaltyPointsRedeemed = 0;
    });
    _scheduleMonitorPublish();
  }

  Future<bool> selectCustomerByRfidUid(String rawUid) async {
    final uid = normalizeNfcUid(rawUid);
    if (uid.length < 4) {
      showAppTopWarning('Invalid RFID card UID');
      return false;
    }

    NfcCustomerLookup? lookup;
    for (final card in loyaltyCards) {
      if (card.nfcUid != null && card.nfcUid!.toUpperCase() == uid) {
        Customer? customer;
        for (final item in customers) {
          if (item.id == card.customerId) {
            customer = item;
            break;
          }
        }
        lookup = NfcCustomerLookup(
          customer: customer ??
              Customer(
                id: card.customerId,
                customerName: card.customerName,
                tableName: '',
                orderType: 'Retail',
              ),
          loyaltyCard: card,
        );
        break;
      }
    }

    lookup ??= await (() async {
      if (isOfflineMode) return null;
      try {
        return await api.lookupCustomerByNfcUid(uid);
      } catch (error) {
        showAppTopWarning(
          error.toString().replaceFirst('Exception: ', ''),
        );
        return null;
      }
    })();

    if (lookup == null) {
      if (isOfflineMode) {
        showAppTopWarning(
          'RFID card not found on this tablet. Connect to the internet to look up new cards.',
        );
      }
      return false;
    }

    final customer = lookup.customer;
    final card = lookup.loyaltyCard;

    if (!mounted) return false;
    setState(() {
      customers.removeWhere((item) => item.id == customer.id);
      customers.insert(0, customer);
      loyaltyCards.removeWhere((item) => item.customerId == card.customerId);
      loyaltyCards.insert(0, card);
      selectedCustomer = customer;
      orderType = customer.orderType;
      loyaltyPointsRedeemed = 0;
    });
    _scheduleMonitorPublish();
    showAppTopSuccess('${customer.displayName} selected via RFID');
    return true;
  }

  Future<bool> selectCustomerByNfcUid(String rawUid) =>
      selectCustomerByRfidUid(rawUid);

  int pointsEarnedForCurrentOrder() =>
      settings.pointsEarnedForAmount(grandTotal);

  Future<void> saveCustomer({
    required String customerName,
    required String tableName,
    bool createLoyaltyCard = false,
  }) async {
    if (customerName.trim().isEmpty) {
      resetCustomer();
      return;
    }

    if (isOfflineMode) {
      throw Exception(
        'Cannot add new customers while offline. Select an existing customer or use Walk In.',
      );
    }

    final customer = await api.saveCustomer(
      customerName: customerName,
      tableName: tableName,
      orderType: orderType,
      actorUserId: widget.currentUser.id,
      createLoyaltyCard: createLoyaltyCard,
    );

    if (!mounted) return;
    setState(() {
      selectedCustomer = customer;
      customers.removeWhere((item) => item.id == customer.id);
      customers.insert(0, customer);
      if (customer.isWalkIn) {
        loyaltyPointsRedeemed = 0;
      }
    });
    await _reloadServerLists();
  }

  void enterPaymentMode() {
    if (!_validateCartStock()) return;
    setState(() => isPaymentMode = true);
    _publishMonitorNow(status: 'payment');
    unawaited(_syncProductStock());
  }

  bool _validateCartStock() {
    if (settings.allowNegativeStock) return true;
    for (final item in cart) {
      final message = _stockLimitMessage(
        item.product,
        item.quantity,
        variety: item.variety,
      );
      if (message != null) {
        showAppTopWarning(message);
        return false;
      }
    }
    return true;
  }

  void exitPaymentMode() {
    setState(() => isPaymentMode = false);
    _publishMonitorNow();
  }

  Future<void> completePayment({
    required int orderId,
    required String paymentMethod,
  }) async {
    clearCart();
    resetCustomer();
    exitPaymentMode();
    await Future.wait([
      _reloadServerLists(),
      refreshProductCatalog(),
    ]);
  }

  Future<void> finishOrderAndShowReceipt(ReceiptData receipt) async {
    setState(() {
      completedReceipt = receipt;
      isPaymentMode = false;
    });
    clearCart(publishMonitor: false);
    resetCustomer();
    unawaited(_publishMonitorSuccess(receipt));
    unawaited(_refreshAfterOrder());
  }

  Future<void> _refreshAfterOrder() async {
    if (isOfflineMode) {
      await OfflineCatalogStore.updateProducts(products);
      return;
    }
    await Future.wait([
      _reloadServerLists(),
      refreshProductCatalog(),
      _syncProductStock(),
      _syncAppSettings(),
    ]);
  }

  Future<CheckoutCompletion> completeCheckout({
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
    List<Map<String, dynamic>>? payments,
    String receiptNote = '',
  }) async {
    final soldAt = DateTime.now();
    final payload = api.buildOrderPayload(
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
      actorUserId: widget.currentUser.id,
      branchId: activeBranchId,
      payments: payments,
      receiptNote: receiptNote,
      soldAt: soldAt,
    );

    await PosConnectivity.instance.refresh(force: true);

    if (PosConnectivity.instance.isOnline) {
      try {
        final orderId = await api.saveOrderPayload(payload);
        PosConnectivity.instance.noteApiReachable();
        return CheckoutCompletion(
          orderId: orderId,
          invoiceNumber: 'INV-${orderId.toString().padLeft(6, '0')}',
        );
      } on SocketException catch (_) {
        await PosConnectivity.instance.refresh(force: true);
      } on TimeoutException catch (_) {
        await PosConnectivity.instance.refresh(force: true);
      } on http.ClientException catch (_) {
        await PosConnectivity.instance.refresh(force: true);
      } catch (error) {
        throw Exception(
          error is Exception ? error.toString().replaceFirst('Exception: ', '') : '$error',
        );
      }
    }

    if (products.isEmpty) {
      throw Exception(
        'Cannot complete sale offline without a saved product list. '
        'Connect to the internet once, open the register, then try again.',
      );
    }

    final pending = await OfflineOrderQueue.enqueue(payload);
    final nextProducts = applyLocalStockDeduction(products, cartItems);
    products = nextProducts;
    await OfflineCatalogStore.updateProducts(nextProducts);
    pendingOfflineCount = await OfflineOrderQueue.pendingCount();
    if (mounted) setState(() {});

    return CheckoutCompletion(
      orderId: -pending.displayNumber,
      invoiceNumber: 'OFF-${pending.displayNumber.toString().padLeft(6, '0')}',
      isOfflinePending: true,
    );
  }

  Future<void> _syncPendingOfflineOrders() async {
    if (_offlineSyncInFlight || !PosConnectivity.instance.isOnline) return;

    _offlineSyncInFlight = true;
    try {
      final pending = await OfflineOrderQueue.loadAll();
      if (pending.isEmpty) {
        if (mounted) setState(() => pendingOfflineCount = 0);
        return;
      }

      var synced = 0;
      for (final order in pending) {
        try {
          await api.saveOrderPayload(order.payload);
          await OfflineOrderQueue.remove(order.localId);
          synced++;
        } catch (_) {
          break;
        }
      }

      pendingOfflineCount = await OfflineOrderQueue.pendingCount();
      if (mounted) setState(() {});

      if (synced > 0) {
        showAppTopSuccess(
          synced == 1
              ? '1 offline sale synced to the server.'
              : '$synced offline sales synced to the server.',
        );
        await Future.wait([
          _reloadServerLists(),
          refreshProductCatalog(),
          _syncProductStock(),
        ]);
      }
    } finally {
      _offlineSyncInFlight = false;
    }
  }

  void dismissCompletedReceipt() {
    if (completedReceipt == null) return;
    setState(() => completedReceipt = null);
    if (cart.isEmpty && !isPaymentMode) {
      unawaited(
        _publishMonitorStateIfWatched(
          status: 'idle',
          monitorReset: true,
        ),
      );
    } else {
      _scheduleMonitorPublish();
    }
  }

  Future<void> savePrinterHost(String host) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('printer_host', host.trim());
    if (!mounted) return;
    setState(() => printerHost = host.trim());
  }

  Future<void> saveDevicePrinter(PrinterConfig config) async {
    await DevicePrinterSettings.save(config);
    if (!mounted) return;
    setState(() {
      devicePrinter = config;
      devicePrinterConfigured = true;
    });
  }

  Future<void> saveReceiptStore(ReceiptStoreConfig value) async {
    await value.saveToPrefs();
    if (!mounted) return;
    setState(() => receiptStore = value);
  }

  void applyManualDiscount(double value) {
    setState(() {
      manualDiscount = value.clamp(0, subtotal).toDouble();
    });
    _scheduleMonitorPublish();
  }

  void applyItemDiscount(CartItem item, double value) {
    setState(() {
      item.discountPerUnit = value.clamp(0, item.unitPrice).toDouble();
    });
    _scheduleMonitorPublish();
  }

  Future<String?> applyCoupon(String code) async {
    final normalized = code.trim().toUpperCase();
    if (normalized.isEmpty) return 'Enter a coupon code';

    if (isOfflineMode) {
      return _applyCachedCoupon(normalized);
    }

    try {
      final result = await api.validateCoupon(
        code: normalized,
        subtotal: subtotal,
      );
      if (!mounted) return 'Could not apply coupon';
      setState(() {
        appliedCouponCode = result.coupon.code;
        appliedCouponDiscount = result.discountAmount;
        _upsertCoupon(result.coupon);
      });
      _scheduleMonitorPublish();
      return null;
    } catch (error) {
      return _applyCachedCoupon(normalized) ??
          error.toString().replaceFirst('Exception: ', '');
    }
  }

  String? _applyCachedCoupon(String normalized) {
    final localCoupon = _findCouponByCode(normalized);
    if (localCoupon == null) {
      return isOfflineMode
          ? 'Coupon $normalized is not in the offline cache.'
          : null;
    }
    if (!localCoupon.isCurrentlyValid) {
      return _couponUnavailableMessage(localCoupon);
    }
    if (!localCoupon.meetsMinimumOrder(subtotal)) {
      return _couponMinimumOrderMessage(localCoupon);
    }
    if (!mounted) return 'Could not apply coupon';
    setState(() {
      appliedCouponCode = localCoupon.code;
      appliedCouponDiscount = localCoupon.discountForSubtotal(subtotal);
    });
    _scheduleMonitorPublish();
    return null;
  }

  String _couponMinimumOrderMessage(Coupon coupon) {
    final currency = settings.currencySymbol;
    final minimum = formatMoney(currency, coupon.minOrderAmount);
    final current = formatMoney(currency, subtotal);
    return 'Order total must be at least $minimum for ${coupon.code}. Current total: $current.';
  }

  String _couponUnavailableMessage(Coupon coupon) {
    switch (coupon.statusLabel) {
      case 'Inactive':
        return 'Coupon ${coupon.code} is inactive.';
      case 'Scheduled':
        return 'Coupon ${coupon.code} is not active yet.';
      case 'Expired':
        return 'Coupon ${coupon.code} has expired.';
      default:
        return 'Coupon ${coupon.code} is not available.';
    }
  }

  void clearCoupon() {
    setState(() {
      appliedCouponCode = '';
      appliedCouponDiscount = 0;
    });
    _scheduleMonitorPublish();
  }

  String? redeemLoyaltyPoints(int points) {
    final customer = selectedCustomer;
    if (!canUseLoyalty(customer)) {
      return 'Loyalty redemption is not available for this customer';
    }

    final cardIndex =
        loyaltyCards.indexWhere((card) => card.customerId == customer!.id);
    if (cardIndex == -1) {
      return 'No loyalty card found for this customer';
    }

    if (points <= 0) {
      return 'Enter points to redeem';
    }

    final card = loyaltyCards[cardIndex];
    if (points > card.points) {
      return 'Only ${card.points} points available on this card';
    }

    final usablePoints = points.clamp(0, card.points);
    final usableDiscount = settings.pesoValueForPoints(usablePoints);
    if (usableDiscount <= 0) {
      return 'Enter a valid number of points';
    }

    if (usableDiscount > subtotal) {
      final currency = settings.currencySymbol;
      final maxDiscount = settings.pesoValueForPoints(card.points).clamp(0, subtotal);
      final maxPoints = settings.loyaltyRedeemPointsPerPeso <= 0
          ? 0
          : (maxDiscount * settings.loyaltyRedeemPointsPerPeso).floor();
      return 'Discount cannot exceed order subtotal (${formatMoney(currency, subtotal)}). '
          'Try up to $maxPoints points.';
    }

    setState(() {
      loyaltyPointsRedeemed = usablePoints;
    });
    _scheduleMonitorPublish();
    return null;
  }

  void clearLoyaltyRedemption() {
    setState(() {
      loyaltyPointsRedeemed = 0;
    });
    _scheduleMonitorPublish();
  }

  void holdCurrentTransaction() {
    if (cart.isEmpty) return;
    final holdId = _nextHoldId++;
    setState(() {
      heldTransactions.insert(
        0,
        HeldTransaction(
          id: holdId,
          label:
              'Hold #$holdId • ${selectedCustomer?.displayName ?? 'Walk In Farmer'}',
          customer: selectedCustomer,
          orderType: orderType,
          items: cart
              .map((item) =>
                  CartItem(product: item.product, quantity: item.quantity))
              .toList(),
          discountAmount: manualDiscount,
          couponCode: appliedCouponCode,
          loyaltyPointsRedeemed: loyaltyPointsRedeemed,
          createdAt: DateTime.now(),
        ),
      );
      cart.clear();
      selectedCustomer = null;
      orderType = 'Retail';
      _resetAdjustments();
      isPaymentMode = false;
    });
  }

  void resumeHeldTransaction(HeldTransaction transaction) {
    setState(() {
      cart
        ..clear()
        ..addAll(
          transaction.items
              .map((item) =>
                  CartItem(product: item.product, quantity: item.quantity))
              .toList(),
        );
      selectedCustomer = transaction.customer;
      orderType = transaction.orderType;
      manualDiscount = transaction.discountAmount;
      appliedCouponCode = transaction.couponCode;
      loyaltyPointsRedeemed = transaction.loyaltyPointsRedeemed;
      heldTransactions.removeWhere((item) => item.id == transaction.id);
      isPaymentMode = false;
    });
  }

  Future<void> addManagedProduct({
    required String name,
    required String category,
    required double price,
    String? option,
    String? sku,
    String? barcode,
    String? description,
    double? costPrice,
    double? stock,
    int? reorderLevel,
    String? unit,
    String? imageUrl,
    List<int>? imageBytes,
    String? imageFilename,
    String? imageMimeType,
    List<Map<String, dynamic>>? varieties,
  }) async {
    await api.saveProduct(
      name: name,
      category: category,
      price: price,
      option: option,
      sku: sku,
      barcode: barcode,
      description: description,
      costPrice: costPrice,
      stock: stock,
      reorderLevel: reorderLevel,
      unit: unit,
      imageUrl: imageUrl,
      imageBytes: imageBytes,
      imageFilename: imageFilename,
      imageMimeType: imageMimeType,
      varieties: varieties,
      actorUserId: widget.currentUser.id,
    );
    await _reloadProductCatalog();
  }

  Future<void> updateManagedProduct({
    required int id,
    required String name,
    required String category,
    required double price,
    String? option,
    String? sku,
    String? barcode,
    String? description,
    double? costPrice,
    double? stock,
    int? reorderLevel,
    String? unit,
    String? imageUrl,
    List<int>? imageBytes,
    String? imageFilename,
    String? imageMimeType,
    List<Map<String, dynamic>>? varieties,
  }) async {
    await api.updateProduct(
      id: id,
      name: name,
      category: category,
      price: price,
      option: option,
      sku: sku,
      barcode: barcode,
      description: description,
      costPrice: costPrice,
      stock: stock,
      reorderLevel: reorderLevel,
      unit: unit,
      imageUrl: imageUrl,
      imageBytes: imageBytes,
      imageFilename: imageFilename,
      imageMimeType: imageMimeType,
      varieties: varieties,
      actorUserId: widget.currentUser.id,
    );
    await _reloadProductCatalog();
  }

  Future<void> updateManagedStock({
    required int productId,
    int? varietyId,
    double? stock,
    double? delta,
  }) async {
    await api.updateProductStock(
      productId: productId,
      varietyId: varietyId,
      stock: stock,
      delta: delta,
      actorUserId: widget.currentUser.id,
    );
    await _reloadProductCatalog();
  }

  Future<void> addManagedCategory({
    required String name,
    String? description,
    String? icon,
  }) async {
    await api.saveCategory(
      name: name,
      description: description,
      icon: icon,
      actorUserId: widget.currentUser.id,
    );
    await _reloadProductCatalog();
  }

  Future<String> uploadManagedProductImage({
    required List<int> bytes,
    required String filename,
    String? mimeType,
  }) async {
    return api.uploadProductImage(
      bytes: bytes,
      filename: filename,
      mimeType: mimeType,
      actorUserId: widget.currentUser.id,
    );
  }

  Future<void> updateSettings(
    AppSettingsModel value, {
    ReceiptStoreConfig? receiptStore,
    int? defaultBranchId,
    String? cashDrawerPin,
    String? refundPin,
  }) async {
    final receiptPayload =
        receiptStore != null ? await receiptStore.toJson() : null;
    final saved = await api.saveSettings(
      settings: value,
      receiptStore: receiptPayload,
      defaultBranchId: defaultBranchId,
      actorUserId: widget.currentUser.id,
      cashDrawerPin: cashDrawerPin,
      refundPin: refundPin,
    );
    if (!mounted) return;
    final host = saved.printerHost.trim();
    if (host.isNotEmpty) {
      await savePrinterHost(host);
    }
    if (saved.receiptStore != null && saved.receiptStore!.isNotEmpty) {
      final synced =
          await ReceiptStoreConfig.applyApiPayload(saved.receiptStore);
      await saveReceiptStore(synced);
    } else if (receiptStore != null) {
      await saveReceiptStore(receiptStore);
    }
    if (defaultBranchId != null && defaultBranchId > 0) {
      await setActiveBranch(defaultBranchId);
    } else if (saved.defaultBranchId != null && saved.defaultBranchId! > 0) {
      await setActiveBranch(saved.defaultBranchId!);
    }
    setState(() => settings = saved);
    _settingsSyncRevision = saved.settingsRevision;
  }

  void _resetAdjustments() {
    manualDiscount = 0;
    appliedCouponCode = '';
    appliedCouponDiscount = 0;
    loyaltyPointsRedeemed = 0;
  }

  Coupon? _findCouponByCode(String code) {
    final normalized = code.trim().toUpperCase();
    for (final coupon in coupons) {
      if (coupon.code == normalized) return coupon;
    }
    return null;
  }

  void _upsertCoupon(Coupon coupon) {
    final index = coupons.indexWhere((item) => item.id == coupon.id);
    if (index >= 0) {
      coupons[index] = coupon;
    } else {
      coupons.add(coupon);
    }
  }

  Future<void> reloadCoupons({bool includeInactive = false}) async {
    final loaded = await api.fetchCoupons(includeInactive: includeInactive);
    if (!mounted) return;
    setState(() {
      coupons
        ..clear()
        ..addAll(loaded);
    });
  }

  Future<void> addManagedCoupon({
    required String code,
    required String description,
    required CouponDiscountType discountType,
    required double discountValue,
    double minOrderAmount = 0,
    required String startDate,
    required String endDate,
    int? maxUses,
  }) async {
    await api.saveCoupon(
      code: code,
      description: description,
      discountType:
          discountType == CouponDiscountType.percentage ? 'percentage' : 'fixed',
      discountValue: discountValue,
      minOrderAmount: minOrderAmount,
      startDate: startDate,
      endDate: endDate,
      maxUses: maxUses,
      actorUserId: widget.currentUser.id,
    );
    await reloadCoupons(includeInactive: true);
  }

  Future<void> updateManagedCoupon({
    required int id,
    required String code,
    required String description,
    required CouponDiscountType discountType,
    required double discountValue,
    double minOrderAmount = 0,
    required String startDate,
    required String endDate,
    int? maxUses,
  }) async {
    await api.updateCoupon(
      id: id,
      code: code,
      description: description,
      discountType:
          discountType == CouponDiscountType.percentage ? 'percentage' : 'fixed',
      discountValue: discountValue,
      minOrderAmount: minOrderAmount,
      startDate: startDate,
      endDate: endDate,
      maxUses: maxUses,
      actorUserId: widget.currentUser.id,
    );
    await reloadCoupons(includeInactive: true);
  }

  Future<void> toggleManagedCoupon(int id) async {
    await api.toggleCoupon(
      id: id,
      actorUserId: widget.currentUser.id,
    );
    await reloadCoupons(includeInactive: true);
  }

  Future<void> reloadStaffUsers() async {
    if (!widget.currentUser.canAccessSuperAdmin) return;
    final loaded = await api.fetchUsers(
      actorUserId: widget.currentUser.id,
    );
    if (!mounted) return;
    setState(() {
      staffUsers
        ..clear()
        ..addAll(loaded);
    });
  }

  Future<void> reloadAuditLogs({String? module, int limit = 100}) async {
    if (!widget.currentUser.canAccessSuperAdmin) return;
    final loaded = await api.fetchAuditLogs(
      actorUserId: widget.currentUser.id,
      module: module,
      limit: limit,
    );
    if (!mounted) return;
    setState(() {
      auditLogs
        ..clear()
        ..addAll(loaded);
    });
  }

  Future<void> addManagedUser({
    required String fullName,
    required UserRole role,
    String? username,
    String? email,
    String? password,
    int? branchId,
  }) async {
    await api.saveUser(
      fullName: fullName,
      username: username,
      email: email,
      password: password,
      role: role.apiValue,
      actorUserId: widget.currentUser.id,
      branchId: branchId,
    );
    await reloadStaffUsers();
    await reloadAuditLogs();
  }

  Future<void> updateManagedUser({
    required int id,
    required String fullName,
    required String username,
    required String email,
    required UserRole role,
    int? branchId,
  }) async {
    await api.updateUser(
      id: id,
      fullName: fullName,
      username: username,
      email: email,
      role: role.apiValue,
      actorUserId: widget.currentUser.id,
      branchId: branchId,
    );
    await reloadStaffUsers();
    await reloadAuditLogs();
  }

  Future<void> toggleManagedUserStatus(int id) async {
    await api.toggleUserStatus(
      id: id,
      actorUserId: widget.currentUser.id,
    );
    await reloadStaffUsers();
    await reloadAuditLogs();
  }

  Future<void> resetManagedUserPassword({
    required int id,
    required String password,
  }) async {
    await api.resetUserPassword(
      id: id,
      password: password,
      actorUserId: widget.currentUser.id,
    );
    await reloadAuditLogs();
  }

  Future<void> changeOwnPassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    await api.changeOwnPassword(
      actorUserId: widget.currentUser.id,
      currentPassword: currentPassword,
      newPassword: newPassword,
    );
  }

  Future<void> refreshProductCatalog() => _reloadProductCatalog();

  /// Pull latest store settings from the server (cash drawer PIN, loyalty, etc.).
  Future<void> refreshAppSettings() async {
    if (isOfflineMode) return;
    try {
      final remote = await api.fetchSettings();
      if (!mounted) return;
      await _applyRemoteSettings(remote);
      _settingsSyncRevision = remote.settingsRevision;
    } catch (_) {
      // Best-effort; cash drawer still validates PIN on the server.
    }
  }

  Future<void> syncProductCatalog(BuildContext context) async {
    if (_catalogSyncInFlight || isLoadingProducts) {
      return;
    }

    _catalogSyncInFlight = true;
    if (mounted) {
      setState(() {});
    }

    try {
      await _reloadProductCatalog();
      if (!context.mounted) {
        return;
      }

      if (loadError != null) {
        showTopError(context, loadError!);
      } else {
        showTopSuccess(
          context,
          'Products synced',
          icon: Icons.sync,
        );
      }
    } finally {
      _catalogSyncInFlight = false;
      if (mounted) {
        setState(() {});
      }
    }
  }

  Future<void> _refreshStockSyncRevision() async {
    try {
      final result = await api.fetchStockSync();
      _stockSyncRevision = result.revision;
    } catch (_) {
      // Best-effort revision sync after full catalog reload.
    }
  }

  Future<void> _syncAppSettings() async {
    if (_settingsSyncInFlight || isLoadingProducts || isOfflineMode) return;

    _settingsSyncInFlight = true;
    try {
      final result =
          await api.fetchSettingsSync(revision: _settingsSyncRevision);
      if (!mounted) return;

      _settingsSyncRevision = result.revision;
      if (result.unchanged || result.settings == null) return;

      await _applyRemoteSettings(result.settings!);
    } catch (_) {
      // Best-effort live settings sync across registers.
    } finally {
      _settingsSyncInFlight = false;
    }
  }

  Future<void> _applyRemoteSettings(AppSettingsModel remote) async {
    var nextReceiptStore = receiptStore;
    if (remote.receiptStore != null && remote.receiptStore!.isNotEmpty) {
      nextReceiptStore =
          await ReceiptStoreConfig.applyApiPayload(remote.receiptStore);
      await saveReceiptStore(nextReceiptStore);
    }

    if (!mounted) return;
    setState(() {
      settings = remote;
      receiptStore = nextReceiptStore;
    });
  }

  Future<void> _syncProductStock() async {
    if (_stockSyncInFlight ||
        isLoadingProducts ||
        products.isEmpty ||
        isOfflineMode) {
      return;
    }

    _stockSyncInFlight = true;
    try {
      final result = await api.fetchStockSync(revision: _stockSyncRevision);
      if (!mounted) return;

      _stockSyncRevision = result.revision;
      if (result.unchanged) return;

      final changed = _applyRemoteStockLevels(
        result.products,
        result.varieties,
      );
      if (changed) {
        setState(() {});
        catalogRevision.value++;
      }
    } catch (_) {
      // Best-effort live stock sync across registers.
    } finally {
      _stockSyncInFlight = false;
    }
  }

  bool _applyRemoteStockLevels(
    Map<String, double> productStock,
    Map<String, double> varietyStock,
  ) {
    var changed = false;
    final updatedProducts = <Product>[];

    for (final product in products) {
      final nextVarieties = <ProductVariety>[];
      var varietiesChanged = false;

      for (final variety in product.varieties) {
        final remoteVarietyStock = varietyStock[variety.id.toString()];
        if (remoteVarietyStock != null && remoteVarietyStock != variety.stock) {
          varietiesChanged = true;
          nextVarieties.add(
            ProductVariety(
              id: variety.id,
              productId: variety.productId,
              name: variety.name,
              price: variety.price,
              sku: variety.sku,
              barcode: variety.barcode,
              costPrice: variety.costPrice,
              deal: variety.deal,
              stock: remoteVarietyStock,
              reorderLevel: variety.reorderLevel,
              imageUrl: variety.imageUrl,
            ),
          );
        } else {
          nextVarieties.add(variety);
        }
      }

      final remoteProductStock = productStock[product.id.toString()];
      final productStockChanged =
          remoteProductStock != null && remoteProductStock != product.stock;

      if (productStockChanged || varietiesChanged) {
        changed = true;
        updatedProducts.add(
          Product(
            id: product.id,
            categoryId: product.categoryId,
            name: product.name,
            price: product.price,
            category: product.category,
            description: product.description,
            option: product.option,
            sku: product.sku,
            barcode: product.barcode,
            unit: product.unit,
            stock: remoteProductStock ?? product.stock,
            reorderLevel: product.reorderLevel,
            costPrice: product.costPrice,
            deal: product.deal,
            imageUrl: product.imageUrl,
            updatedAt: product.updatedAt,
            varieties: nextVarieties,
          ),
        );
      } else {
        updatedProducts.add(product);
      }
    }

    if (changed) {
      products = updatedProducts;
    }

    return changed;
  }

  Future<void> _reloadProductCatalog() async {
    try {
      final results = await Future.wait<dynamic>([
        api.fetchCategories(),
        api.fetchItems(),
      ]).timeout(
        PosApi.catalogLoadTimeout,
        onTimeout: () => throw TimeoutException('Catalog load timed out'),
      );

      if (!mounted) return;
      setState(() {
        categories = results[0] as List<ProductCategory>;
        products = results[1] as List<Product>;
        loadError = null;
        catalogRevision.value++;
      });
      await OfflineCatalogStore.save(
        categories: categories,
        products: products,
        settings: settings,
        coupons: coupons,
        branches: branches.isNotEmpty ? branches : [Branch.mainBranch],
      );
      offlineCatalogSavedAt = DateTime.now();
      await _refreshStockSyncRevision();
    } catch (_) {
      if (mounted && products.isEmpty) {
        setState(() {
          loadError =
              'Could not load products. Connect to the internet once, then you can sell offline.';
        });
      }
    }
  }

  Future<void> addManagedCustomer({
    required String customerName,
    String tableName = '',
    String orderType = 'Retail',
    bool createLoyaltyCard = false,
  }) async {
    await api.saveCustomer(
      customerName: customerName,
      tableName: tableName,
      orderType: orderType,
      actorUserId: widget.currentUser.id,
      createLoyaltyCard: createLoyaltyCard,
    );
    await _reloadCustomerLists();
  }

  Future<void> openLoyaltyCardForCustomer(int customerId) async {
    await api.openLoyaltyCard(
      customerId: customerId,
      actorUserId: widget.currentUser.id,
    );
    await _reloadCustomerLists();
  }

  Future<void> linkRfidCardForCustomer(int customerId, String rfidUid) async {
    await api.linkLoyaltyCardRfid(
      customerId: customerId,
      rfidUid: rfidUid,
      actorUserId: widget.currentUser.id,
    );
    await _reloadCustomerLists();
  }

  Future<void> reloadCustomers() async {
    await _reloadCustomerLists();
  }

  Future<void> _reloadCustomerLists() async {
    Object? firstError;

    try {
      final loadedCustomers = await api.fetchCustomers();
      customers
        ..clear()
        ..addAll(loadedCustomers.where((customer) => !customer.isWalkIn));
    } catch (e) {
      firstError = e;
    }

    try {
      final loadedLoyaltyCards = await api.fetchLoyaltyCards();
      loyaltyCards
        ..clear()
        ..addAll(loadedLoyaltyCards);
    } catch (e) {
      firstError ??= e;
    }

    if (mounted) setState(() {});

    if (firstError != null) {
      throw firstError;
    }
  }

  Future<void> reloadSalesHistory() async {
    final records = await api.fetchSalesHistory();
    salesHistory
      ..clear()
      ..addAll(records);
    if (mounted) setState(() {});
  }

  Future<void> setActiveBranch(int branchId) async {
    activeBranchId = branchId;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('active_branch_id', branchId);
    if (widget.currentUser.canMonitorAllBranches &&
        dashboardMonitorBranchId != allBranchesMonitorId) {
      dashboardMonitorBranchId = branchId;
      await prefs.setInt('dashboard_monitor_branch_id', branchId);
    }
    if (mounted) setState(() {});
  }

  Future<void> setDashboardMonitorBranch(
    int branchId, {
    bool syncPosBranch = true,
  }) async {
    dashboardMonitorBranchId = branchId;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('dashboard_monitor_branch_id', branchId);
    if (syncPosBranch &&
        branchId > 0 &&
        widget.currentUser.canMonitorAllBranches) {
      activeBranchId = branchId;
      await prefs.setInt('active_branch_id', branchId);
    }
    if (mounted) setState(() {});
  }

  Future<Branch> addBranch({
    required String name,
    String? code,
    String? location,
  }) async {
    final branch = await api.createBranch(
      name: name,
      code: code,
      location: location,
      actorUserId: widget.currentUser.id,
    );
    branches.add(branch);
    if (mounted) setState(() {});
    await reloadAuditLogs();
    return branch;
  }

  Future<void> reloadBranches({bool includeInactive = false}) async {
    final loaded = await api.fetchBranches(
      includeInactive: includeInactive,
      actorUserId: includeInactive ? widget.currentUser.id : null,
    );
    if (!mounted) return;
    setState(() {
      branches
        ..clear()
        ..addAll(loaded.isEmpty ? [Branch.mainBranch] : loaded);
      if (!branches.any((branch) => branch.id == activeBranchId)) {
        activeBranchId = branches.firstWhere(
          (branch) => branch.isActive,
          orElse: () => branches.first,
        ).id;
      }
    });
  }

  Future<void> updateManagedBranch({
    required int id,
    required String name,
    String? code,
    String? location,
  }) async {
    await api.updateBranch(
      id: id,
      name: name,
      code: code,
      location: location,
      actorUserId: widget.currentUser.id,
    );
    await reloadBranches(includeInactive: true);
    await reloadAuditLogs();
  }

  Future<void> toggleManagedBranchStatus(int id) async {
    await api.toggleBranchStatus(
      id: id,
      actorUserId: widget.currentUser.id,
    );
    await reloadBranches(includeInactive: true);
    await reloadAuditLogs();
  }

  Future<void> reloadStaffPayments({
    int? userId,
    int? branchId,
    int limit = 100,
  }) async {
    if (!widget.currentUser.canAccessSuperAdmin) return;
    final loaded = await api.fetchStaffPayments(
      actorUserId: widget.currentUser.id,
      userId: userId,
      branchId: branchId,
      limit: limit,
    );
    if (!mounted) return;
    setState(() {
      staffPayments
        ..clear()
        ..addAll(loaded);
    });
  }

  Future<void> addStaffPayment({
    required int userId,
    required double amount,
    required StaffPaymentType paymentType,
    int? branchId,
    String? periodStart,
    String? periodEnd,
    String? notes,
  }) async {
    await api.createStaffPayment(
      userId: userId,
      amount: amount,
      paymentType: paymentType.apiValue,
      actorUserId: widget.currentUser.id,
      branchId: branchId,
      periodStart: periodStart,
      periodEnd: periodEnd,
      notes: notes,
    );
    await reloadStaffPayments();
    await reloadAuditLogs();
  }

  double staffSalesTotal(int userId) {
    return salesHistory
        .where((sale) => sale.cashierUserId == userId)
        .fold<double>(0, (sum, sale) => sum + sale.total);
  }

  Future<void> reloadAnalyticsData() async {
    final results = await Future.wait<dynamic>([
      api.fetchSalesHistory(),
      api.fetchBranches(),
    ]);
    salesHistory
      ..clear()
      ..addAll(results[0] as List<SalesHistoryRecord>);
    final fetchedBranches = results[1] as List<Branch>;
    branches
      ..clear()
      ..addAll(fetchedBranches.isEmpty ? [Branch.mainBranch] : fetchedBranches);
    if (mounted) setState(() {});
  }

  Future<void> reloadDashboardData() async {
    final results = await Future.wait<dynamic>([
      api.fetchSalesHistory(),
      api.fetchItems(),
      widget.currentUser.canMonitorAllBranches
          ? api.fetchBranches()
          : Future<List<Branch>>.value(const []),
    ]);

    salesHistory
      ..clear()
      ..addAll(results[0] as List<SalesHistoryRecord>);
    final fetchedProducts = results[1] as List<Product>;
    if (fetchedProducts.isNotEmpty) {
      products
        ..clear()
        ..addAll(fetchedProducts);
    }
    if (widget.currentUser.canMonitorAllBranches) {
      final fetchedBranches = results[2] as List<Branch>;
      if (fetchedBranches.isNotEmpty) {
        branches
          ..clear()
          ..addAll(fetchedBranches);
      }
      if (!isMonitoringAllBranches &&
          !branches.any((branch) => branch.id == dashboardMonitorBranchId)) {
        dashboardMonitorBranchId = activeBranchId;
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _reloadServerLists() async {
    if (isOfflineMode) return;
    try {
      final results = await Future.wait<dynamic>([
        api.fetchCustomers(),
        api.fetchLoyaltyCards(),
        api.fetchSalesHistory(),
      ]);

      customers
        ..clear()
        ..addAll(
          (results[0] as List<Customer>).where((customer) => !customer.isWalkIn),
        );
      loyaltyCards
        ..clear()
        ..addAll(results[1] as List<LoyaltyCard>);
      salesHistory
        ..clear()
        ..addAll(results[2] as List<SalesHistoryRecord>);
      if (mounted) setState(() {});
    } catch (_) {
      // Keep cached lists when the server is unreachable.
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final splitView = screenWidth >= posSplitBreakpoint;
    final cartChild = completedReceipt != null
        ? ReceiptPanel(
            pageState: this,
            receipt: completedReceipt!,
          )
        : isPaymentMode
            ? ChargePaymentSection(
                pageState: this,
                subtotal: subtotal,
              )
            : CartSection(pageState: this);

    return Scaffold(
      drawer: AppDrawer(
        pageState: this,
        activeSection: AppDrawerSection.posRegister,
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (isOfflineMode)
              OfflineStatusBanner(
                pendingSyncCount: pendingOfflineCount,
                catalogSavedAt: offlineCatalogSavedAt,
              ),
            Expanded(
              child: splitView
                  ? Row(
                      children: [
                        Expanded(
                          child: ProductSection(
                            pageState: this,
                            showMenuButton: true,
                          ),
                        ),
                        SizedBox(
                          width: cartPanelWidth(screenWidth),
                          child: cartChild,
                        ),
                      ],
                    )
                  : Column(
                      children: [
                        Expanded(
                          child: ProductSection(
                            pageState: this,
                            showMenuButton: true,
                          ),
                        ),
                        SizedBox(
                          height: (screenWidth * 0.72).clamp(300, 420),
                          child: cartChild,
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
