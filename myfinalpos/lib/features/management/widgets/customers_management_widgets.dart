import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/format_utils.dart';
import '../../../core/utils/top_toast.dart';
import '../../../models/customer.dart';
import '../../../models/loyalty_card.dart';
import '../../../models/loyalty_point_log.dart';
import '../../pos/pages/pos_home_page.dart';
import '../../pos/widgets/rfid_link_card_dialog.dart';

Future<void> showAddCustomerDialog(
  BuildContext context,
  PosHomePageState pageState, {
  VoidCallback? onSaved,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _AddCustomerDialog(
      pageState: pageState,
      onSaved: onSaved,
    ),
  );
}

Future<void> showCustomerDetailsDialog(
  BuildContext context, {
  required Customer customer,
  required PosHomePageState pageState,
  LoyaltyCard? loyaltyCard,
  VoidCallback? onUpdated,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (_) => _CustomerDetailsDialog(
      customer: customer,
      pageState: pageState,
      loyaltyCard: loyaltyCard,
      onUpdated: onUpdated,
    ),
  );
}

class CustomersManagementContent extends StatefulWidget {
  const CustomersManagementContent({super.key, required this.pageState});

  final PosHomePageState pageState;

  @override
  State<CustomersManagementContent> createState() =>
      _CustomersManagementContentState();
}

class _CustomersManagementContentState extends State<CustomersManagementContent> {
  final searchController = TextEditingController();
  String selectedOrderType = 'All';
  bool refreshing = false;

  @override
  void initState() {
    super.initState();
    searchController.addListener(() => setState(() {}));
    _refreshCustomers();
  }

  Future<void> _refreshCustomers() async {
    setState(() => refreshing = true);
    try {
      await widget.pageState.reloadCustomers();
    } catch (_) {
      // Keep existing list on failure.
    } finally {
      if (mounted) setState(() => refreshing = false);
    }
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  LoyaltyCard? _loyaltyFor(Customer customer) {
    if (customer.isWalkIn) return null;
    for (final card in widget.pageState.loyaltyCards) {
      if (card.customerId == customer.id) return card;
    }
    return null;
  }

  List<Customer> get filteredCustomers {
    final query = searchController.text.trim().toLowerCase();
    return widget.pageState.customers.where((customer) {
      final matchesType = selectedOrderType == 'All' ||
          customer.orderType == selectedOrderType;
      final matchesSearch = query.isEmpty ||
          customer.displayName.toLowerCase().contains(query) ||
          customer.tableName.toLowerCase().contains(query) ||
          customer.orderType.toLowerCase().contains(query);
      return matchesType && matchesSearch;
    }).toList();
  }

  int get loyaltyMemberCount => widget.pageState.loyaltyCards.length;

  int get retailCount => widget.pageState.customers
      .where((c) => c.orderType.toLowerCase() == 'retail')
      .length;

  @override
  Widget build(BuildContext context) {
    final customers = filteredCustomers;
    final orderTypes = [
      'All',
      'Retail',
      'Wholesale',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 720;
            final cards = [
              _CustomerStatCard(
                label: 'Customers',
                value: '${widget.pageState.customers.length}',
                icon: Icons.people_outline,
                color: AppColors.green,
              ),
              _CustomerStatCard(
                label: 'Loyalty Members',
                value: '$loyaltyMemberCount',
                icon: Icons.card_giftcard,
                color: AppColors.amber,
              ),
              _CustomerStatCard(
                label: 'Retail Accounts',
                value: '$retailCount',
                icon: Icons.storefront_outlined,
                color: AppColors.darkGreen,
              ),
            ];

            if (isWide) {
              return Row(
                children: [
                  for (var i = 0; i < cards.length; i++) ...[
                    if (i > 0) const SizedBox(width: 12),
                    Expanded(child: cards[i]),
                  ],
                ],
              );
            }

            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final card in cards)
                  SizedBox(width: 220, child: card),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: searchController,
                decoration: InputDecoration(
                  hintText: 'Search by name, reference, or order type...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: searchController.text.isNotEmpty
                      ? IconButton(
                          onPressed: () => searchController.clear(),
                          icon: const Icon(Icons.close),
                        )
                      : null,
                  filled: true,
                  fillColor: AppColors.softSurface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final type in orderTypes)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          label: Text(type),
                          selected: selectedOrderType == type,
                          onSelected: (_) =>
                              setState(() => selectedOrderType = type),
                          selectedColor: AppColors.lightGreen,
                          checkmarkColor: AppColors.green,
                          side: BorderSide(
                            color: selectedOrderType == type
                                ? AppColors.green
                                : AppColors.border,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            const Text(
              'Customer Directory',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.text,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.lightGreen,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${customers.length} shown',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.green,
                ),
              ),
            ),
            const Spacer(),
            OutlinedButton.icon(
              onPressed: refreshing ? null : _refreshCustomers,
              icon: refreshing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh, size: 18),
              label: Text(refreshing ? 'Refreshing...' : 'Refresh'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: () => showAddCustomerDialog(
                context,
                widget.pageState,
                onSaved: () => setState(() {}),
              ),
              icon: const Icon(Icons.person_add_outlined, size: 18),
              label: const Text('Add Customer'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (customers.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                const Icon(Icons.people_outline, size: 48, color: AppColors.muted),
                const SizedBox(height: 12),
                const Text(
                  'No customers found.',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Add farmer accounts to track loyalty and checkout faster.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.muted),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => showAddCustomerDialog(
                    context,
                    widget.pageState,
                    onSaved: () => setState(() {}),
                  ),
                  icon: const Icon(Icons.person_add_outlined),
                  label: const Text('Add First Customer'),
                ),
              ],
            ),
          )
        else
          ...customers.map(
            (customer) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _CustomerDirectoryTile(
                customer: customer,
                loyaltyCard: _loyaltyFor(customer),
                onTap: () => showCustomerDetailsDialog(
                  context,
                  customer: customer,
                  pageState: widget.pageState,
                  loyaltyCard: _loyaltyFor(customer),
                  onUpdated: () => setState(() {}),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _AddCustomerDialog extends StatefulWidget {
  const _AddCustomerDialog({
    required this.pageState,
    this.onSaved,
  });

  final PosHomePageState pageState;
  final VoidCallback? onSaved;

  @override
  State<_AddCustomerDialog> createState() => _AddCustomerDialogState();
}

class _AddCustomerDialogState extends State<_AddCustomerDialog> {
  final nameController = TextEditingController();
  final referenceController = TextEditingController();
  String orderType = 'Retail';
  bool saving = false;
  bool openLoyaltyCard = false;

  @override
  void dispose() {
    nameController.dispose();
    referenceController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = nameController.text.trim();
    if (name.isEmpty) {
      showTopWarning(context, 'Enter a customer name.');
      return;
    }

    setState(() => saving = true);
    try {
      await widget.pageState.addManagedCustomer(
        customerName: name,
        tableName: referenceController.text.trim(),
        orderType: orderType,
        createLoyaltyCard: openLoyaltyCard,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onSaved?.call();
      showAppTopSuccess('Customer "$name" added');
    } catch (error) {
      if (!mounted) return;
      showTopError(context, error.toString());
      setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 20),
              decoration: const BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.person_add_outlined, color: Colors.white),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Add Customer',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Register a farmer or walk-in account',
                          style: TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: saving ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: nameController,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Customer Name *',
                      hintText: 'e.g. Juan Dela Cruz Farm',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: referenceController,
                    decoration: const InputDecoration(
                      labelText: 'Table / Reference (optional)',
                      hintText: 'Farm plot, phone, or note',
                      prefixIcon: Icon(Icons.tag_outlined),
                    ),
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    value: orderType,
                    decoration: const InputDecoration(
                      labelText: 'Order Type',
                      prefixIcon: Icon(Icons.storefront_outlined),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'Retail', child: Text('Retail')),
                      DropdownMenuItem(
                        value: 'Wholesale',
                        child: Text('Wholesale'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => orderType = value);
                    },
                  ),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    value: openLoyaltyCard,
                    onChanged: saving
                        ? null
                        : (value) => setState(() => openLoyaltyCard = value ?? false),
                    title: const Text('Open loyalty card'),
                    subtitle: const Text(
                      'Walk-in customers do not earn loyalty points',
                      style: TextStyle(fontSize: 12),
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: saving ? null : () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: saving ? null : _save,
                      icon: saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.check),
                      label: Text(saving ? 'Saving...' : 'Save Customer'),
                    ),
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

class _CustomerDetailsDialog extends StatefulWidget {
  const _CustomerDetailsDialog({
    required this.customer,
    required this.pageState,
    this.loyaltyCard,
    this.onUpdated,
  });

  final Customer customer;
  final PosHomePageState pageState;
  final LoyaltyCard? loyaltyCard;
  final VoidCallback? onUpdated;

  @override
  State<_CustomerDetailsDialog> createState() => _CustomerDetailsDialogState();
}

class _CustomerDetailsDialogState extends State<_CustomerDetailsDialog> {
  bool openingLoyaltyCard = false;
  bool linkingRfid = false;
  bool loadingLogs = false;
  List<LoyaltyPointLog> pointLogs = [];

  @override
  void initState() {
    super.initState();
    _loadPointLogs();
  }

  LoyaltyCard? get _loyaltyCard {
    if (widget.customer.isWalkIn) return null;
    if (widget.loyaltyCard != null) return widget.loyaltyCard;
    return widget.pageState.loyaltyCardFor(widget.customer);
  }

  Future<void> _loadPointLogs() async {
    if (widget.customer.isWalkIn) return;

    setState(() => loadingLogs = true);
    try {
      final logs = await widget.pageState.api.fetchLoyaltyPointLogs(
        customerId: widget.customer.id,
      );
      if (!mounted) return;
      setState(() => pointLogs = logs);
    } catch (_) {
      if (!mounted) return;
      setState(() => pointLogs = []);
    } finally {
      if (mounted) setState(() => loadingLogs = false);
    }
  }

  Future<void> _openLoyaltyCard() async {
    setState(() => openingLoyaltyCard = true);
    try {
      await widget.pageState.openLoyaltyCardForCustomer(widget.customer.id);
      if (!mounted) return;
      widget.onUpdated?.call();
      setState(() => openingLoyaltyCard = false);
      await _loadPointLogs();
      if (!mounted) return;
      showAppTopSuccess('Loyalty card opened');
    } catch (error) {
      if (!mounted) return;
      showTopError(context, error.toString());
      setState(() => openingLoyaltyCard = false);
    }
  }

  Future<void> _linkRfidCard() async {
    final card = _loyaltyCard;
    if (card == null) {
      setState(() => openingLoyaltyCard = true);
      try {
        await widget.pageState.openLoyaltyCardForCustomer(widget.customer.id);
      } catch (error) {
        if (!mounted) return;
        showTopError(context, error.toString());
        setState(() => openingLoyaltyCard = false);
        return;
      }
      if (!mounted) return;
      setState(() => openingLoyaltyCard = false);
      widget.onUpdated?.call();
    }

    final linked = await showRfidLinkCardDialog(
      context,
      pageState: widget.pageState,
      customerId: widget.customer.id,
      customerName: widget.customer.displayName,
      currentRfidUid: _loyaltyCard?.nfcUid,
    );
    if (!mounted || !linked) return;
    widget.onUpdated?.call();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final customer = widget.customer;
    final loyaltyCard = _loyaltyCard;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.88;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 520, maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.fromLTRB(24, 24, 16, 24),
                      decoration: const BoxDecoration(
                        gradient: AppColors.primaryGradient,
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(20),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Icon(
                              Icons.person,
                              color: Colors.white,
                              size: 30,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  customer.displayName,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 22,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Customer ID #${customer.id}',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close, color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              _CustomerInfoChip(
                                icon: Icons.storefront_outlined,
                                label: 'Order Type',
                                value: customer.orderType,
                              ),
                              _CustomerInfoChip(
                                icon: Icons.tag_outlined,
                                label: 'Reference',
                                value: customer.tableName.isEmpty
                                    ? '—'
                                    : customer.tableName,
                              ),
                            ],
                          ),
                          if (loyaltyCard != null) ...[
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: AppColors.lightGreen,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: AppColors.greenBorder),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Row(
                                    children: [
                                      Icon(
                                        Icons.card_giftcard,
                                        color: AppColors.green,
                                        size: 20,
                                      ),
                                      SizedBox(width: 8),
                                      Text(
                                        'Loyalty Card',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 15,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  _CustomerDetailRow(
                                    label: 'Card Number',
                                    value: loyaltyCard!.cardNumber,
                                  ),
                                  const SizedBox(height: 8),
                                  _CustomerDetailRow(
                                    label: 'Points',
                                    value: '${loyaltyCard!.points}',
                                    valueColor: AppColors.green,
                                  ),
                                  const SizedBox(height: 8),
                                  _CustomerDetailRow(
                                    label: 'Tier',
                                    value: loyaltyCard!.tier,
                                  ),
                                  const SizedBox(height: 8),
                                  _CustomerDetailRow(
                                    label: 'Status',
                                    value: loyaltyCard!.status,
                                  ),
                                  if (loyaltyCard!.nfcUid != null &&
                                      loyaltyCard!.nfcUid!.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    _CustomerDetailRow(
                                      label: 'RFID UID',
                                      value: loyaltyCard!.nfcUid!,
                                    ),
                                  ],
                                  const SizedBox(height: 12),
                                  OutlinedButton.icon(
                                    onPressed: linkingRfid || openingLoyaltyCard
                                        ? null
                                        : _linkRfidCard,
                                    icon: linkingRfid
                                        ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Icon(Icons.sensors),
                                    label: Text(
                                      loyaltyCard!.nfcUid != null &&
                                              loyaltyCard!.nfcUid!.isNotEmpty
                                          ? 'Update RFID card'
                                          : 'Link RFID card',
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: AppColors.green,
                                      side: const BorderSide(
                                        color: AppColors.greenBorder,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            _PointsHistorySection(
                              logs: pointLogs,
                              loading: loadingLogs,
                              onRefresh: _loadPointLogs,
                            ),
                          ] else if (customer.isWalkIn) ...[
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: AppColors.softSurface,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AppColors.border),
                              ),
                              child: const Text(
                                'Walk-in customers are not enrolled in the loyalty program.',
                                style: TextStyle(color: AppColors.muted),
                              ),
                            ),
                          ] else ...[
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: AppColors.softSurface,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AppColors.border),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  const Text(
                                    'No loyalty card linked yet.',
                                    style: TextStyle(color: AppColors.muted),
                                  ),
                                  const SizedBox(height: 12),
                                  FilledButton.icon(
                                    onPressed:
                                        openingLoyaltyCard ? null : _openLoyaltyCard,
                                    icon: openingLoyaltyCard
                                        ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white,
                                            ),
                                          )
                                        : const Icon(Icons.card_giftcard),
                                    label: Text(
                                      openingLoyaltyCard
                                          ? 'Opening...'
                                          : 'Open Loyalty Card',
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  OutlinedButton.icon(
                                    onPressed: linkingRfid || openingLoyaltyCard
                                        ? null
                                        : _linkRfidCard,
                                    icon: const Icon(Icons.sensors),
                                    label: const Text('Link RFID card'),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: AppColors.green,
                                      side: const BorderSide(
                                        color: AppColors.greenBorder,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1, color: AppColors.border),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 14, 24, 20),
              child: FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PointsHistorySection extends StatelessWidget {
  const _PointsHistorySection({
    required this.logs,
    required this.loading,
    required this.onRefresh,
  });

  final List<LoyaltyPointLog> logs;
  final bool loading;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.history, color: AppColors.green, size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Points History',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
              ),
              IconButton(
                tooltip: 'Refresh history',
                onPressed: loading ? null : onRefresh,
                icon: loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Track how points were earned, redeemed, or when the card was opened.',
            style: TextStyle(fontSize: 12, color: AppColors.muted),
          ),
          const SizedBox(height: 12),
          if (loading && logs.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (logs.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.softSurface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'No point activity yet. New checkout and redemption events will appear here.',
                style: TextStyle(color: AppColors.muted),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: logs.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) => _PointsHistoryTile(log: logs[index]),
            ),
        ],
      ),
    );
  }
}

class _PointsHistoryTile extends StatelessWidget {
  const _PointsHistoryTile({required this.log});

  final LoyaltyPointLog log;

  Color get _accentColor {
    if (log.isCredit) return AppColors.green;
    if (log.isDebit) return AppColors.danger;
    return AppColors.blue;
  }

  IconData get _icon {
    switch (log.action) {
      case LoyaltyPointAction.earn:
        return Icons.add_circle_outline;
      case LoyaltyPointAction.redeem:
        return Icons.remove_circle_outline;
      case LoyaltyPointAction.openCard:
        return Icons.card_membership_outlined;
      case LoyaltyPointAction.adjust:
        return Icons.tune;
      case LoyaltyPointAction.other:
        return Icons.history;
    }
  }

  String get _changeLabel {
    if (log.pointsChange == 0) return '0 pts';
    final prefix = log.pointsChange > 0 ? '+' : '';
    return '$prefix${log.pointsChange} pts';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.softSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _accentColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(_icon, color: _accentColor, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        log.actionLabel,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    Text(
                      _changeLabel,
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: _accentColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  log.description,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.text,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${formatDateTime(log.createdAt)} • Balance ${log.pointsBalanceAfter} pts'
                      '${log.orderId != null ? ' • Order #${log.orderId}' : ''}',
                  style: const TextStyle(fontSize: 11, color: AppColors.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CustomerStatCard extends StatelessWidget {
  const _CustomerStatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: AppColors.text,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CustomerDirectoryTile extends StatelessWidget {
  const _CustomerDirectoryTile({
    required this.customer,
    required this.loyaltyCard,
    required this.onTap,
  });

  final Customer customer;
  final LoyaltyCard? loyaltyCard;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.lightGreen,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.person, color: AppColors.green),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      customer.displayName,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      customer.tableName.isEmpty
                          ? 'No reference'
                          : customer.tableName,
                      style: const TextStyle(fontSize: 12, color: AppColors.muted),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      children: [
                        _CustomerBadge(
                          label: customer.orderType,
                          color: AppColors.green,
                        ),
                        if (!customer.isWalkIn && loyaltyCard != null)
                          _CustomerBadge(
                            label: '${loyaltyCard!.points} pts',
                            color: AppColors.amber,
                            icon: Icons.card_giftcard,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}

class _CustomerBadge extends StatelessWidget {
  const _CustomerBadge({
    required this.label,
    required this.color,
    this.icon,
  });

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _CustomerInfoChip extends StatelessWidget {
  const _CustomerInfoChip({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.lightGreen,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.greenBorder),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.green),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(fontSize: 11, color: AppColors.muted),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.text,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CustomerDetailRow extends StatelessWidget {
  const _CustomerDetailRow({
    required this.label,
    required this.value,
    this.valueColor = AppColors.text,
  });

  final String label;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 110,
          child: Text(
            label,
            style: const TextStyle(fontSize: 13, color: AppColors.muted),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: valueColor,
            ),
          ),
        ),
      ],
    );
  }
}
