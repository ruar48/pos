class PosMonitorItem {
  const PosMonitorItem({
    required this.name,
    required this.quantity,
    required this.price,
    required this.total,
  });

  final String name;
  final double quantity;
  final double price;
  final double total;

  factory PosMonitorItem.fromJson(Map<String, dynamic> json) {
    return PosMonitorItem(
      name: json['name']?.toString() ?? '',
      quantity: (json['quantity'] as num?)?.toDouble() ?? 0,
      price: (json['price'] as num?)?.toDouble() ?? 0,
      total: (json['total'] as num?)?.toDouble() ?? 0,
    );
  }
}

class PosMonitorSuccess {
  const PosMonitorSuccess({
    required this.invoiceNumber,
    required this.paymentMethod,
    required this.total,
    required this.customerName,
    required this.items,
    required this.completedAt,
  });

  final String invoiceNumber;
  final String paymentMethod;
  final double total;
  final String customerName;
  final List<PosMonitorItem> items;
  final String completedAt;

  factory PosMonitorSuccess.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    return PosMonitorSuccess(
      invoiceNumber: json['invoice_number']?.toString() ?? '',
      paymentMethod: json['payment_method']?.toString() ?? 'Cash',
      total: (json['total'] as num?)?.toDouble() ?? 0,
      customerName: json['customer_name']?.toString() ?? 'Walk-in',
      items: rawItems is List
          ? rawItems
              .whereType<Map>()
              .map((item) => PosMonitorItem.fromJson(Map<String, dynamic>.from(item)))
              .toList()
          : const [],
      completedAt: json['completed_at']?.toString() ?? '',
    );
  }
}

class PosMonitorState {
  const PosMonitorState({
    required this.terminalId,
    required this.terminalLabel,
    required this.branchName,
    required this.cashierName,
    required this.customerName,
    required this.status,
    required this.isPaymentMode,
    required this.items,
    required this.total,
    required this.updatedAt,
    this.registerCode,
    this.cashierUsername,
    this.success,
  });

  final String terminalId;
  final String terminalLabel;
  final String? registerCode;
  final String branchName;
  final String cashierName;
  final String? cashierUsername;
  final String customerName;
  final String status;
  final bool isPaymentMode;
  final List<PosMonitorItem> items;
  final double total;
  final String updatedAt;
  final PosMonitorSuccess? success;

  factory PosMonitorState.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    final rawSuccess = json['success'];
    return PosMonitorState(
      terminalId: json['terminal_id']?.toString() ?? '',
      terminalLabel: json['terminal_label']?.toString() ?? '',
      registerCode: json['register_code']?.toString(),
      branchName: json['branch_name']?.toString() ?? 'Main Branch',
      cashierName: json['cashier_name']?.toString() ?? 'Cashier',
      cashierUsername: json['cashier_username']?.toString(),
      customerName: json['customer_name']?.toString() ?? 'Walk-in',
      status: json['status']?.toString() ?? 'idle',
      isPaymentMode: json['is_payment_mode'] == true,
      items: rawItems is List
          ? rawItems
              .whereType<Map>()
              .map((item) => PosMonitorItem.fromJson(Map<String, dynamic>.from(item)))
              .toList()
          : const [],
      total: (json['total'] as num?)?.toDouble() ?? 0,
      updatedAt: json['updated_at']?.toString() ?? '',
      success: rawSuccess is Map
          ? PosMonitorSuccess.fromJson(Map<String, dynamic>.from(rawSuccess))
          : null,
    );
  }
}

class PosMonitorTerminal {
  const PosMonitorTerminal({
    required this.terminalId,
    required this.terminalLabel,
    required this.cashierName,
    required this.branchName,
    required this.status,
    required this.customerName,
    required this.total,
    required this.online,
    required this.updatedAt,
    this.registerCode,
    this.cashierUsername,
  });

  final String terminalId;
  final String terminalLabel;
  final String? registerCode;
  final String cashierName;
  final String? cashierUsername;
  final String branchName;
  final String status;
  final String customerName;
  final double total;
  final bool online;
  final String updatedAt;

  factory PosMonitorTerminal.fromJson(Map<String, dynamic> json) {
    return PosMonitorTerminal(
      terminalId: json['terminal_id']?.toString() ?? '',
      terminalLabel: json['terminal_label']?.toString() ?? '',
      registerCode: json['register_code']?.toString(),
      cashierName: json['cashier_name']?.toString() ?? 'Cashier',
      cashierUsername: json['cashier_username']?.toString(),
      branchName: json['branch_name']?.toString() ?? 'Main Branch',
      status: json['status']?.toString() ?? 'idle',
      customerName: json['customer_name']?.toString() ?? '',
      total: (json['total'] as num?)?.toDouble() ?? 0,
      online: json['online'] == true,
      updatedAt: json['updated_at']?.toString() ?? '',
    );
  }
}

class PosMonitorLive {
  const PosMonitorLive({
    required this.revision,
    required this.watching,
    required this.terminals,
    required this.terminalStates,
    required this.onlineCount,
    required this.activeCount,
    this.unchanged = false,
  });

  final String revision;
  final bool unchanged;
  final bool watching;
  final List<PosMonitorTerminal> terminals;
  final Map<String, PosMonitorState> terminalStates;
  final int onlineCount;
  final int activeCount;

  static int pollDelayMs({
    required PosMonitorLive? live,
    bool wallMode = false,
  }) {
    final activeCount = live?.activeCount ?? 0;
    final onlineCount = live?.onlineCount ?? 0;

    if (wallMode) {
      if (activeCount > 0) return 800;
      if (onlineCount > 0) return 2500;
      return 6000;
    }

    if (activeCount > 0) return 1000;
    if (onlineCount > 0) return 4000;
    return 8000;
  }

  PosMonitorLive mergeFrom(PosMonitorLiveResult result) {
    if (result.unchanged) {
      final live = result.live;
      final hasTerminalSnapshot = live.terminals.isNotEmpty ||
          live.terminalStates.isNotEmpty;

      final nextTerminals = hasTerminalSnapshot
          ? live.terminals.where((terminal) => terminal.online).toList()
          : terminals.where((terminal) => terminal.online).toList();
      final visibleIds = nextTerminals.map((terminal) => terminal.terminalId).toSet();
      final nextStates = hasTerminalSnapshot
          ? Map<String, PosMonitorState>.fromEntries(
              live.terminalStates.entries.where(
                (entry) => visibleIds.contains(entry.key),
              ),
            )
          : Map<String, PosMonitorState>.fromEntries(
              terminalStates.entries.where(
                (entry) => visibleIds.contains(entry.key),
              ),
            );

      return PosMonitorLive(
        revision: result.revision,
        watching: result.watching,
        terminals: nextTerminals,
        terminalStates: nextStates,
        onlineCount: result.onlineCount,
        activeCount: result.activeCount,
      );
    }

    return PosMonitorLive(
      revision: result.live.revision,
      watching: result.live.watching,
      terminals: result.live.terminals
          .where((terminal) => terminal.online)
          .toList(),
      terminalStates: Map<String, PosMonitorState>.fromEntries(
        result.live.terminalStates.entries.where(
          (entry) => result.live.terminals.any(
            (terminal) =>
                terminal.online && terminal.terminalId == entry.key,
          ),
        ),
      ),
      onlineCount: result.live.onlineCount,
      activeCount: result.live.activeCount,
    );
  }

  factory PosMonitorLive.fromJson(Map<String, dynamic> json) {
    final rawTerminals = json['terminals'];
    final rawStates = json['terminal_states'];
    final states = <String, PosMonitorState>{};

    if (rawStates is Map) {
      rawStates.forEach((key, value) {
        if (value is Map) {
          states[key.toString()] =
              PosMonitorState.fromJson(Map<String, dynamic>.from(value));
        }
      });
    }

    final terminals = rawTerminals is List
        ? rawTerminals
            .whereType<Map>()
            .map((item) =>
                PosMonitorTerminal.fromJson(Map<String, dynamic>.from(item)))
            .toList()
        : const <PosMonitorTerminal>[];

    if (json['unchanged'] == true) {
      return PosMonitorLive(
        revision: json['revision']?.toString() ?? '0',
        watching: json['watching'] == true,
        terminals: terminals,
        terminalStates: states,
        onlineCount: (json['online_count'] as num?)?.toInt() ?? 0,
        activeCount: (json['active_count'] as num?)?.toInt() ?? 0,
        unchanged: true,
      );
    }

    return PosMonitorLive(
      revision: json['revision']?.toString() ?? '0',
      watching: json['watching'] == true,
      terminals: terminals,
      terminalStates: states,
      onlineCount: (json['online_count'] as num?)?.toInt() ?? 0,
      activeCount: (json['active_count'] as num?)?.toInt() ?? 0,
    );
  }
}

class PosMonitorLiveResult {
  const PosMonitorLiveResult({
    required this.unchanged,
    required this.revision,
    required this.watching,
    required this.onlineCount,
    required this.activeCount,
    required this.live,
  });

  final bool unchanged;
  final String revision;
  final bool watching;
  final int onlineCount;
  final int activeCount;
  final PosMonitorLive live;

  factory PosMonitorLiveResult.fromJson(Map<String, dynamic> json) {
    final live = PosMonitorLive.fromJson(json);
    return PosMonitorLiveResult(
      unchanged: live.unchanged,
      revision: live.revision,
      watching: live.watching,
      onlineCount: live.onlineCount,
      activeCount: live.activeCount,
      live: live,
    );
  }
}

class PosMonitorWatchResult {
  const PosMonitorWatchResult({
    required this.changed,
    required this.revision,
  });

  final bool changed;
  final String revision;

  factory PosMonitorWatchResult.fromJson(Map<String, dynamic> json) {
    return PosMonitorWatchResult(
      changed: json['changed'] == true,
      revision: json['revision']?.toString() ?? '0',
    );
  }
}
