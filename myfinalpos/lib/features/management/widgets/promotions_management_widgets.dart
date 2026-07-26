import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/format_utils.dart';
import '../../../core/utils/top_toast.dart';
import '../../../models/coupon.dart';
import '../../pos/pages/pos_home_page.dart';
import 'management_widgets.dart';

Future<void> showAddCouponDialog(
  BuildContext context,
  PosHomePageState pageState, {
  VoidCallback? onSaved,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _CouponFormDialog(
      pageState: pageState,
      onSaved: onSaved,
    ),
  );
}

Future<void> showEditCouponDialog(
  BuildContext context,
  PosHomePageState pageState, {
  required Coupon coupon,
  VoidCallback? onSaved,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _CouponFormDialog(
      pageState: pageState,
      coupon: coupon,
      onSaved: onSaved,
    ),
  );
}

class PromotionsManagementContent extends StatefulWidget {
  const PromotionsManagementContent({super.key, required this.pageState});

  final PosHomePageState pageState;

  @override
  State<PromotionsManagementContent> createState() =>
      _PromotionsManagementContentState();
}

class _PromotionsManagementContentState
    extends State<PromotionsManagementContent> {
  final searchController = TextEditingController();
  String statusFilter = 'All';
  bool refreshing = false;

  @override
  void initState() {
    super.initState();
    searchController.addListener(() => setState(() {}));
    _refreshCoupons();
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  Future<void> _refreshCoupons() async {
    setState(() => refreshing = true);
    try {
      await widget.pageState.reloadCoupons(includeInactive: true);
    } catch (_) {
      // Keep existing list on failure.
    } finally {
      if (mounted) setState(() => refreshing = false);
    }
  }

  List<Coupon> get filteredCoupons {
    final query = searchController.text.trim().toLowerCase();
    return widget.pageState.coupons.where((coupon) {
      final matchesStatus = switch (statusFilter) {
        'Active' => coupon.statusLabel == 'Active',
        'Inactive' => coupon.statusLabel == 'Inactive',
        'Expired' => coupon.statusLabel == 'Expired',
        'Scheduled' => coupon.statusLabel == 'Scheduled',
        _ => true,
      };
      final matchesSearch = query.isEmpty ||
          coupon.code.toLowerCase().contains(query) ||
          (coupon.description ?? '').toLowerCase().contains(query);
      return matchesStatus && matchesSearch;
    }).toList();
  }

  int get activeCount =>
      widget.pageState.coupons.where((c) => c.statusLabel == 'Active').length;

  int get percentageCount => widget.pageState.coupons
      .where((c) => c.discountType == CouponDiscountType.percentage)
      .length;

  @override
  Widget build(BuildContext context) {
    final coupons = filteredCoupons;
    final currency = widget.pageState.settings.currencySymbol;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 720;
            final cards = [
              SummaryCard(
                label: 'Total Coupons',
                value: '${widget.pageState.coupons.length}',
                icon: Icons.local_offer_outlined,
              ),
              SummaryCard(
                label: 'Active Now',
                value: '$activeCount',
                icon: Icons.check_circle_outline,
                color: AppColors.green,
              ),
              SummaryCard(
                label: 'Percentage Deals',
                value: '$percentageCount',
                icon: Icons.percent,
                color: AppColors.amber,
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
                for (final card in cards) SizedBox(width: 220, child: card),
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
                  hintText: 'Search by code or description...',
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
                    for (final filter in [
                      'All',
                      'Active',
                      'Scheduled',
                      'Expired',
                      'Inactive',
                    ])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          label: Text(filter),
                          selected: statusFilter == filter,
                          onSelected: (_) =>
                              setState(() => statusFilter = filter),
                          selectedColor: AppColors.lightGreen,
                          checkmarkColor: AppColors.green,
                          side: BorderSide(
                            color: statusFilter == filter
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
              'Coupon Codes',
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
                '${coupons.length} shown',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.green,
                ),
              ),
            ),
            const Spacer(),
            OutlinedButton.icon(
              onPressed: refreshing ? null : _refreshCoupons,
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
              onPressed: () => showAddCouponDialog(
                context,
                widget.pageState,
                onSaved: () => setState(() {}),
              ),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add Coupon'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (coupons.isEmpty)
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: const Column(
              children: [
                Icon(Icons.local_offer_outlined,
                    size: 42, color: AppColors.muted),
                SizedBox(height: 12),
                Text(
                  'No coupons match your filters.',
                  style: TextStyle(color: AppColors.muted),
                ),
              ],
            ),
          )
        else
          ...coupons.map(
            (coupon) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _CouponCard(
                coupon: coupon,
                currency: currency,
                onEdit: () => showEditCouponDialog(
                  context,
                  widget.pageState,
                  coupon: coupon,
                  onSaved: () => setState(() {}),
                ),
                onToggle: () async {
                  try {
                    await widget.pageState.toggleManagedCoupon(coupon.id);
                    if (!mounted) return;
                    setState(() {});
                    showAppTopSuccess(
                      coupon.isActive
                          ? 'Coupon ${coupon.code} deactivated'
                          : 'Coupon ${coupon.code} activated',
                    );
                  } catch (error) {
                    if (!mounted) return;
                    showAppTopError(error.toString());
                  }
                },
              ),
            ),
          ),
      ],
    );
  }
}

class _CouponCard extends StatelessWidget {
  const _CouponCard({
    required this.coupon,
    required this.currency,
    required this.onEdit,
    required this.onToggle,
  });

  final Coupon coupon;
  final String currency;
  final VoidCallback onEdit;
  final VoidCallback onToggle;

  Color get _statusColor {
    switch (coupon.statusLabel) {
      case 'Active':
        return AppColors.green;
      case 'Scheduled':
        return AppColors.blue;
      case 'Expired':
        return AppColors.amber;
      default:
        return AppColors.muted;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.lightGreen,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.local_offer, color: AppColors.green),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          coupon.code,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: AppColors.text,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: _statusColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            coupon.statusLabel,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: _statusColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      coupon.description?.isNotEmpty == true
                          ? coupon.description!
                          : 'No description',
                      style: const TextStyle(color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              Text(
                coupon.discountLabel(currency),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.green,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              _MetaChip(
                icon: Icons.calendar_today_outlined,
                label:
                    '${formatShortDate(coupon.startDate)} - ${formatShortDate(coupon.endDate)}',
              ),
              if (coupon.minOrderAmount > 0)
                _MetaChip(
                  icon: Icons.shopping_cart_outlined,
                  label:
                      'Min ${formatMoney(currency, coupon.minOrderAmount)}',
                ),
              if (coupon.maxUses != null)
                _MetaChip(
                  icon: Icons.confirmation_number_outlined,
                  label: '${coupon.usageCount}/${coupon.maxUses} used',
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              TextButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Edit'),
              ),
              TextButton.icon(
                onPressed: onToggle,
                icon: Icon(
                  coupon.isActive ? Icons.pause_circle_outline : Icons.play_circle_outline,
                  size: 18,
                ),
                label: Text(coupon.isActive ? 'Deactivate' : 'Activate'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppColors.muted),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: AppColors.muted),
        ),
      ],
    );
  }
}

class _CouponFormDialog extends StatefulWidget {
  const _CouponFormDialog({
    required this.pageState,
    this.coupon,
    this.onSaved,
  });

  final PosHomePageState pageState;
  final Coupon? coupon;
  final VoidCallback? onSaved;

  @override
  State<_CouponFormDialog> createState() => _CouponFormDialogState();
}

class _CouponFormDialogState extends State<_CouponFormDialog> {
  final codeController = TextEditingController();
  final descriptionController = TextEditingController();
  final valueController = TextEditingController();
  final minOrderController = TextEditingController();
  final maxUsesController = TextEditingController();
  late CouponDiscountType discountType;
  late DateTime startDate;
  late DateTime endDate;
  bool saving = false;

  bool get isEditing => widget.coupon != null;

  @override
  void initState() {
    super.initState();
    final coupon = widget.coupon;
    if (coupon != null) {
      codeController.text = coupon.code;
      descriptionController.text = coupon.description ?? '';
      valueController.text = coupon.discountValue.toString();
      minOrderController.text = coupon.minOrderAmount > 0
          ? coupon.minOrderAmount.toString()
          : '';
      maxUsesController.text =
          coupon.maxUses == null ? '' : '${coupon.maxUses}';
      discountType = coupon.discountType;
      startDate = coupon.startDate;
      endDate = coupon.endDate;
    } else {
      discountType = CouponDiscountType.fixed;
      startDate = DateTime.now();
      endDate = DateTime.now().add(const Duration(days: 365));
    }
  }

  @override
  void dispose() {
    codeController.dispose();
    descriptionController.dispose();
    valueController.dispose();
    minOrderController.dispose();
    maxUsesController.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool isStart}) async {
    final initial = isStart ? startDate : endDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        startDate = picked;
        if (endDate.isBefore(startDate)) endDate = startDate;
      } else {
        endDate = picked;
      }
    });
  }

  Future<void> _save() async {
    final code = codeController.text.trim().toUpperCase();
    final value = double.tryParse(valueController.text.trim()) ?? 0;
    final minOrder = double.tryParse(minOrderController.text.trim()) ?? 0;
    final maxUsesRaw = maxUsesController.text.trim();
    final maxUses = maxUsesRaw.isEmpty ? null : int.tryParse(maxUsesRaw);

    if (code.isEmpty) {
      _showError('Enter a coupon code.');
      return;
    }
    if (value <= 0) {
      _showError('Enter a valid discount value.');
      return;
    }
    if (discountType == CouponDiscountType.percentage && value > 100) {
      _showError('Percentage discount cannot exceed 100.');
      return;
    }
    if (maxUses != null && maxUses <= 0) {
      _showError('Max uses must be greater than zero.');
      return;
    }

    setState(() => saving = true);
    try {
      final start = _formatDate(startDate);
      final end = _formatDate(endDate);
      final description = descriptionController.text.trim();

      if (isEditing) {
        await widget.pageState.updateManagedCoupon(
          id: widget.coupon!.id,
          code: code,
          description: description,
          discountType: discountType,
          discountValue: value,
          minOrderAmount: minOrder,
          startDate: start,
          endDate: end,
          maxUses: maxUses,
        );
      } else {
        await widget.pageState.addManagedCoupon(
          code: code,
          description: description,
          discountType: discountType,
          discountValue: value,
          minOrderAmount: minOrder,
          startDate: start,
          endDate: end,
          maxUses: maxUses,
        );
      }

      if (!mounted) return;
      widget.onSaved?.call();
      showAppTopSuccess(isEditing ? 'Coupon updated' : 'Coupon created');
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      _showError(error.toString());
      setState(() => saving = false);
    }
  }

  void _showError(String message) {
    showAppTopError(message);
  }

  String _formatDate(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final currency = widget.pageState.settings.currencySymbol;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          const Icon(Icons.local_offer_outlined, color: AppColors.green),
          const SizedBox(width: 10),
          Text(isEditing ? 'Edit Coupon' : 'Add Coupon'),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: codeController,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Coupon Code *',
                  hintText: 'FARM10',
                  prefixIcon: Icon(Icons.confirmation_number_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  hintText: 'Seasonal farm supply promo',
                  prefixIcon: Icon(Icons.notes_outlined),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<CouponDiscountType>(
                value: discountType,
                decoration: const InputDecoration(
                  labelText: 'Discount Type *',
                  prefixIcon: Icon(Icons.percent),
                ),
                items: const [
                  DropdownMenuItem(
                    value: CouponDiscountType.fixed,
                    child: Text('Fixed amount'),
                  ),
                  DropdownMenuItem(
                    value: CouponDiscountType.percentage,
                    child: Text('Percentage'),
                  ),
                ],
                onChanged: saving
                    ? null
                    : (value) {
                        if (value == null) return;
                        setState(() => discountType = value);
                      },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: valueController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                ],
                decoration: InputDecoration(
                  labelText: 'Discount Value *',
                  hintText: discountType == CouponDiscountType.percentage
                      ? '10'
                      : '5.00',
                  prefixIcon: Icon(
                    discountType == CouponDiscountType.percentage
                        ? Icons.percent
                        : Icons.payments_outlined,
                  ),
                  suffixText: discountType == CouponDiscountType.percentage
                      ? '%'
                      : currency,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: minOrderController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                ],
                decoration: InputDecoration(
                  labelText: 'Minimum Order',
                  hintText: '0 = no minimum',
                  prefixIcon: const Icon(Icons.shopping_cart_outlined),
                  suffixText: currency,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: maxUsesController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Max Uses',
                  hintText: 'Leave blank for unlimited',
                  prefixIcon: Icon(Icons.confirmation_number_outlined),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: saving ? null : () => _pickDate(isStart: true),
                      icon: const Icon(Icons.event_outlined, size: 18),
                      label: Text('Start: ${formatShortDate(startDate)}'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: saving ? null : () => _pickDate(isStart: false),
                      icon: const Icon(Icons.event_available_outlined, size: 18),
                      label: Text('End: ${formatShortDate(endDate)}'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: saving ? null : _save,
          child: Text(saving ? 'Saving...' : (isEditing ? 'Update' : 'Save')),
        ),
      ],
    );
  }
}
