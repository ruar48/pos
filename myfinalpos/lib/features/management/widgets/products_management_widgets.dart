import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/agri_admin_widgets.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/category_icons.dart';
import '../../../core/utils/format_utils.dart';
import '../../../core/utils/product_units.dart';
import '../../../models/product_variety.dart';
import 'catalog_table_widgets.dart';
import '../../../core/utils/top_toast.dart';
import '../../../models/product.dart';
import '../../pos/pages/pos_home_page.dart';
import '../../pos/widgets/product_section.dart';

Future<void> showAddCategoryDialog(
  BuildContext context,
  PosHomePageState pageState, {
  VoidCallback? onSaved,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _AddCategoryDialog(
      pageState: pageState,
      onSaved: onSaved,
    ),
  );
}

Future<void> showAddProductDialog(
  BuildContext context,
  PosHomePageState pageState, {
  VoidCallback? onSaved,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (_) => _ProductFormDialog(
      pageState: pageState,
      onSaved: onSaved,
    ),
  );
}

Future<void> showEditProductDialog(
  BuildContext context,
  PosHomePageState pageState, {
  required Product product,
  VoidCallback? onSaved,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (_) => _ProductFormDialog(
      pageState: pageState,
      existingProduct: product,
      onSaved: onSaved,
    ),
  );
}

Future<void> showProductDetailsDialog(
  BuildContext context, {
  required Product product,
  required String currency,
  PosHomePageState? pageState,
  VoidCallback? onEdit,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (_) => _ProductDetailsDialog(
      product: product,
      currency: currency,
      pageState: pageState,
      onEdit: onEdit,
    ),
  );
}

class _AddCategoryDialog extends StatefulWidget {
  const _AddCategoryDialog({
    required this.pageState,
    this.onSaved,
  });

  final PosHomePageState pageState;
  final VoidCallback? onSaved;

  @override
  State<_AddCategoryDialog> createState() => _AddCategoryDialogState();
}

class _AddCategoryDialogState extends State<_AddCategoryDialog> {
  final nameController = TextEditingController();
  final descriptionController = TextEditingController();
  late String selectedIconKey;
  bool iconManuallySelected = false;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    selectedIconKey = suggestCategoryIconKey('');
    nameController.addListener(_onNameChanged);
  }

  @override
  void dispose() {
    nameController.removeListener(_onNameChanged);
    nameController.dispose();
    descriptionController.dispose();
    super.dispose();
  }

  void _onNameChanged() {
    if (!iconManuallySelected) {
      final suggested = suggestCategoryIconKey(nameController.text);
      if (suggested != selectedIconKey) {
        setState(() => selectedIconKey = suggested);
      }
      return;
    }
    setState(() {});
  }

  void _selectIcon(String key) {
    setState(() {
      selectedIconKey = key;
      iconManuallySelected = true;
    });
  }

  void _useSuggestedIcon() {
    final suggested = suggestCategoryIconKey(nameController.text);
    setState(() {
      selectedIconKey = suggested;
      iconManuallySelected = false;
    });
    showTopMessage(
      context,
      'Using suggested icon: ${categoryIconOptionForKey(suggested).label}',
      backgroundColor: AppColors.text,
    );
  }

  Future<void> _save() async {
    final name = nameController.text.trim();
    if (name.isEmpty) {
      showTopMessage(
        context,
        'Enter a category name.',
        backgroundColor: AppColors.danger,
      );
      return;
    }

    setState(() => saving = true);
    try {
      await widget.pageState.addManagedCategory(
        name: name,
        description: descriptionController.text.trim(),
        icon: selectedIconKey,
      );
      if (!mounted) return;
      final iconLabel = categoryIconOptionForKey(selectedIconKey).label;
      Navigator.of(context).pop();
      widget.onSaved?.call();
      showTopToast(
        context,
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              resolveCategoryIcon(iconKey: selectedIconKey, categoryName: name),
              color: Colors.white,
              size: 24,
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                'Category "$name" added · $iconLabel',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
      );
    } catch (error) {
      if (!mounted) return;
      showTopError(context, error.toString());
      setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedOption = categoryIconOptionForKey(selectedIconKey);
    final suggestedKey = suggestCategoryIconKey(nameController.text);
    final suggestedOption = categoryIconOptionForKey(suggestedKey);
    final showSuggestedHint =
        nameController.text.trim().isNotEmpty &&
        iconManuallySelected &&
        suggestedKey != selectedIconKey;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(
        children: [
          Icon(Icons.create_new_folder_outlined, color: AppColors.green),
          SizedBox(width: 10),
          Text('Add Category'),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: nameController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Category Name *',
                  hintText: 'e.g. Organic Feed',
                  prefixIcon: Icon(Icons.category_outlined),
                ),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.lightGreen,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.greenBorder),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        selectedOption.icon,
                        color: AppColors.green,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            selectedOption.label,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: AppColors.darkGreen,
                            ),
                          ),
                          Text(
                            iconManuallySelected
                                ? 'Custom icon selected'
                                : 'Auto-selected from category name',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Choose Icon',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: AppColors.text,
                      ),
                    ),
                  ),
                  if (showSuggestedHint)
                    TextButton(
                      onPressed: _useSuggestedIcon,
                      child: Text('Use "${suggestedOption.label}"'),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final option in categoryIconOptions)
                    Material(
                      color: selectedIconKey == option.key
                          ? AppColors.lightGreen
                          : AppColors.softSurface,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        onTap: () => _selectIcon(option.key),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          width: 72,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: selectedIconKey == option.key
                                  ? AppColors.green
                                  : AppColors.border,
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                option.icon,
                                color: selectedIconKey == option.key
                                    ? AppColors.green
                                    : AppColors.muted,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                option.label,
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: selectedIconKey == option.key
                                      ? FontWeight.w800
                                      : FontWeight.w500,
                                  color: selectedIconKey == option.key
                                      ? AppColors.darkGreen
                                      : AppColors.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                controller: descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  hintText: 'Optional notes for staff',
                  prefixIcon: Icon(Icons.notes_outlined),
                ),
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
          child: Text(saving ? 'Saving...' : 'Save Category'),
        ),
      ],
    );
  }
}

class _VarietyDraft {
  _VarietyDraft({
    this.id,
    String name = '',
    String price = '',
    String cost = '',
    String stock = '',
    String reorder = '5',
    String sku = '',
    String barcode = '',
    Set<String>? units,
  })  : nameController = TextEditingController(text: name),
        priceController = TextEditingController(text: price),
        costController = TextEditingController(text: cost),
        stockController = TextEditingController(text: stock),
        reorderController = TextEditingController(text: reorder),
        skuController = TextEditingController(text: sku),
        barcodeController = TextEditingController(text: barcode),
        selectedUnits = units == null || units.isEmpty ? {'pc'} : {...units};

  final int? id;
  final TextEditingController nameController;
  final TextEditingController priceController;
  final TextEditingController costController;
  final TextEditingController stockController;
  final TextEditingController reorderController;
  final TextEditingController skuController;
  final TextEditingController barcodeController;
  Set<String> selectedUnits;

  Map<String, dynamic> toPayload() {
    final map = <String, dynamic>{
      if (id != null) 'id': id,
      'name': nameController.text.trim(),
      'price': toDouble(priceController.text),
      'stock': int.tryParse(stockController.text.trim()) ?? 0,
      'reorder_level':
          int.tryParse(reorderController.text.trim()) ?? Product.defaultReorderLevel,
    };
    final cost = costController.text.trim();
    map['cost_price'] = cost.isEmpty ? null : toDouble(cost);
    final sku = skuController.text.trim();
    if (sku.isNotEmpty) map['sku'] = sku;
    final barcode = barcodeController.text.trim();
    if (barcode.isNotEmpty) map['barcode'] = barcode;
    map['unit'] = encodeProductUnits(selectedUnits);
    return map;
  }

  void dispose() {
    nameController.dispose();
    priceController.dispose();
    costController.dispose();
    stockController.dispose();
    reorderController.dispose();
    skuController.dispose();
    barcodeController.dispose();
  }
}

class _ProductFormDialog extends StatefulWidget {
  const _ProductFormDialog({
    required this.pageState,
    this.existingProduct,
    this.onSaved,
  });

  final PosHomePageState pageState;
  final Product? existingProduct;
  final VoidCallback? onSaved;

  bool get isEditing => existingProduct != null;

  @override
  State<_ProductFormDialog> createState() => _ProductFormDialogState();
}

class _ProductFormDialogState extends State<_ProductFormDialog> {
  final nameController = TextEditingController();
  final skuController = TextEditingController();
  final barcodeController = TextEditingController();
  final priceController = TextEditingController();
  final costPriceController = TextEditingController();
  final stockController = TextEditingController();
  final reorderLevelController = TextEditingController(
    text: '${Product.defaultReorderLevel}',
  );
  final descriptionController = TextEditingController();
  final optionController = TextEditingController();
  String? category;
  Set<String> selectedUnits = {};
  bool saving = false;
  bool hasVarieties = false;
  final List<_VarietyDraft> varietyDrafts = [];

  @override
  void initState() {
    super.initState();
    final existing = widget.existingProduct;
    if (existing != null) {
      nameController.text = existing.name;
      optionController.text = existing.option ?? '';
      skuController.text = existing.sku ?? '';
      barcodeController.text = existing.barcode ?? '';
      selectedUnits = parseProductUnits(existing.unit).toSet();
      priceController.text = existing.price.toStringAsFixed(2);
      if (existing.costPrice != null) {
        costPriceController.text = existing.costPrice!.toStringAsFixed(2);
      }
      if (existing.stock != null) {
        stockController.text = existing.stock.toString();
      }
      reorderLevelController.text = existing.reorderLevel.toString();
      descriptionController.text = existing.description ?? '';
      category = existing.category;
      hasVarieties = existing.varieties.isNotEmpty;
      for (final variety in existing.varieties) {
        varietyDrafts.add(
          _VarietyDraft(
            id: variety.id,
            name: variety.name,
            price: variety.price.toStringAsFixed(2),
            cost: variety.costPrice?.toStringAsFixed(2) ?? '',
            stock: variety.stock?.toString() ?? '',
            reorder: variety.reorderLevel.toString(),
            sku: variety.sku ?? '',
            barcode: variety.barcode ?? '',
            units: parseProductUnits(variety.unit ?? existing.unit).toSet(),
          ),
        );
      }
    } else {
      category = null;
      selectedUnits = {};
    }
  }

  String? _skuForSave() {
    final sku = skuController.text.trim();
    return sku.isEmpty ? null : sku;
  }

  void _addUnit(String? value) {
    if (value == null) return;
    setState(() => selectedUnits = {...selectedUnits, normalizeProductUnit(value)});
  }

  void _removeUnit(String value) {
    setState(() {
      selectedUnits = {...selectedUnits}..remove(normalizeProductUnit(value));
    });
  }

  @override
  void dispose() {
    nameController.dispose();
    skuController.dispose();
    barcodeController.dispose();
    priceController.dispose();
    costPriceController.dispose();
    stockController.dispose();
    reorderLevelController.dispose();
    descriptionController.dispose();
    optionController.dispose();
    for (final draft in varietyDrafts) {
      draft.dispose();
    }
    super.dispose();
  }

  void _toggleVarieties(bool value) {
    setState(() {
      hasVarieties = value;
      if (value && varietyDrafts.isEmpty) {
        varietyDrafts.add(_VarietyDraft(units: selectedUnits));
      }
    });
  }

  void _addVarietyDraft() {
    setState(
      () => varietyDrafts.add(
        _VarietyDraft(
          units: varietyDrafts.isNotEmpty
              ? varietyDrafts.last.selectedUnits
              : selectedUnits,
        ),
      ),
    );
  }

  void _removeVarietyDraft(int index) {
    setState(() {
      varietyDrafts.removeAt(index).dispose();
    });
  }

  Future<void> _save() async {
    final name = nameController.text.trim();
    final price = toDouble(priceController.text);

    if (widget.pageState.categories.isEmpty) {
      showTopMessage(
        context,
        'Add a category first using Add Category on this screen.',
        backgroundColor: AppColors.danger,
      );
      return;
    }

    if (category == null || category!.trim().isEmpty) {
      showTopMessage(
        context,
        'Select a category.',
        backgroundColor: AppColors.danger,
      );
      return;
    }

    if (!hasVarieties && selectedUnits.isEmpty) {
      showTopMessage(
        context,
        'Select at least one unit.',
        backgroundColor: AppColors.danger,
      );
      return;
    }

    if (name.isEmpty) {
      showTopMessage(
        context,
        'Enter a product name.',
        backgroundColor: AppColors.danger,
      );
      return;
    }

    List<Map<String, dynamic>> varietiesPayload = [];
    double effectivePrice = price;

    if (hasVarieties) {
      final drafts = varietyDrafts
          .where((d) => d.nameController.text.trim().isNotEmpty)
          .toList();
      if (drafts.isEmpty) {
        showTopMessage(
          context,
          'Add at least one variety, or turn varieties off.',
          backgroundColor: AppColors.danger,
        );
        return;
      }
      for (final draft in drafts) {
        if (toDouble(draft.priceController.text) <= 0) {
          showTopMessage(
            context,
            'Enter a valid price for "${draft.nameController.text.trim()}".',
            backgroundColor: AppColors.danger,
          );
          return;
        }
        if (draft.selectedUnits.isEmpty) {
          showTopMessage(
            context,
            'Select a sold-by unit for "${draft.nameController.text.trim()}".',
            backgroundColor: AppColors.danger,
          );
          return;
        }
      }
      varietiesPayload = drafts.map((d) => d.toPayload()).toList();
      effectivePrice = varietiesPayload
          .map((v) => (v['price'] as num).toDouble())
          .reduce((a, b) => a < b ? a : b);
    } else if (price <= 0) {
      showTopMessage(
        context,
        'Enter a valid price.',
        backgroundColor: AppColors.danger,
      );
      return;
    }

    setState(() => saving = true);
    try {
      final stockText = stockController.text.trim();
      final stock = hasVarieties
          ? null
          : (stockText.isEmpty ? null : int.tryParse(stockText));
      final reorderText = reorderLevelController.text.trim();
      final reorderLevel = reorderText.isEmpty
          ? Product.defaultReorderLevel
          : int.tryParse(reorderText);
      final unit = hasVarieties
          ? encodeProductUnits(
              varietyDrafts
                  .where((d) => d.nameController.text.trim().isNotEmpty)
                  .expand((draft) => draft.selectedUnits),
            )
          : encodeProductUnits(selectedUnits);
      final costText = costPriceController.text.trim();
      final costPrice =
          hasVarieties || costText.isEmpty ? null : toDouble(costText);
      final description = descriptionController.text.trim();
      final productOption = optionController.text.trim();
      final sku = _skuForSave();
      final barcode = barcodeController.text.trim();
      final imageBytes = null;
      final imageFilename = null;
      final imageMimeType = null;
      final savedImageUrl = null;

      if (widget.isEditing) {
        await widget.pageState.updateManagedProduct(
          id: widget.existingProduct!.id,
          name: name,
          category: category!,
          price: effectivePrice,
          option: productOption.isEmpty ? null : productOption,
          sku: sku,
          barcode: barcode.isEmpty ? null : barcode,
          description: description.isEmpty ? null : description,
          costPrice: costPrice,
          stock: stock,
          reorderLevel: reorderLevel,
          unit: unit,
          imageUrl: savedImageUrl,
          imageBytes: imageBytes,
          imageFilename: imageFilename,
          imageMimeType: imageMimeType,
          varieties: varietiesPayload,
        );
      } else {
        await widget.pageState.addManagedProduct(
          name: name,
          category: category!,
          price: effectivePrice,
          option: productOption.isEmpty ? null : productOption,
          sku: sku,
          barcode: barcode.isEmpty ? null : barcode,
          description: description.isEmpty ? null : description,
          costPrice: costPrice,
          stock: stock,
          reorderLevel: reorderLevel,
          unit: unit,
          imageUrl: savedImageUrl,
          imageBytes: imageBytes,
          imageFilename: imageFilename,
          imageMimeType: imageMimeType,
          varieties: varietiesPayload,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onSaved?.call();
      showTopMessage(
        context,
        widget.isEditing ? '"$name" updated' : '"$name" added to catalog',
      );
    } catch (error) {
      if (!mounted) return;
      showTopError(context, error.toString());
      setState(() => saving = false);
    }
  }

  Widget _buildVarietyEditor(PosHomePageState pageState) {
    final currency = pageState.settings.currencySymbol;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _FormSectionTitle(
          icon: Icons.style_outlined,
          label: 'Varieties',
        ),
        const SizedBox(height: 6),
        const Text(
          'Each variety has its own price and stock, e.g. SUPER 222, INBRED-160.',
          style: TextStyle(fontSize: 12, color: AppColors.muted),
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < varietyDrafts.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _VarietyDraftCard(
              draft: varietyDrafts[i],
              index: i,
              currency: currency,
              canRemove: varietyDrafts.length > 1,
              onRemove: () => _removeVarietyDraft(i),
              onChanged: () => setState(() {}),
            ),
          ),
        OutlinedButton.icon(
          onPressed: _addVarietyDraft,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Add Variety'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final pageState = widget.pageState;

    return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
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
                        child: const Icon(
                          Icons.add_box_outlined,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.isEditing ? 'Edit Product' : 'Add Product',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              widget.isEditing
                                  ? 'Update catalog details and pricing'
                                  : 'Add a new item to your farm supply catalog',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                              ),
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
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const _FormSectionTitle(
                          icon: Icons.inventory_2_outlined,
                          label: 'Basic Information',
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: nameController,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(
                            labelText: 'Product Name *',
                            hintText: 'e.g. NPK Fertilizer 14-14-14',
                            prefixIcon: Icon(Icons.label_outline),
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: optionController,
                          textCapitalization: TextCapitalization.sentences,
                          maxLength: 120,
                          decoration: const InputDecoration(
                            labelText: 'Option',
                            hintText: 'Pack / unit (e.g. 50kg bag)',
                            prefixIcon: Icon(Icons.tune_outlined),
                          ),
                        ),
                        const SizedBox(height: 14),
                        if (pageState.categories.isEmpty)
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.lightGreen,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppColors.greenBorder),
                            ),
                            child: const Text(
                              'No categories yet. Close this form and tap Add Category first.',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.muted,
                              ),
                            ),
                          )
                        else
                          DropdownButtonFormField<String>(
                            value: category,
                            decoration: const InputDecoration(
                              labelText: 'Category *',
                              hintText: 'Select category',
                              prefixIcon: Icon(Icons.category_outlined),
                            ),
                            hint: const Text('Select category'),
                            isExpanded: true,
                            items: [
                              for (final item in pageState.categories)
                                DropdownMenuItem(
                                  value: item.name,
                                  child: Text(item.name),
                                ),
                            ],
                            onChanged: (value) {
                              setState(() => category = value);
                            },
                          ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: descriptionController,
                          maxLines: 2,
                          decoration: const InputDecoration(
                            labelText: 'Description',
                            hintText: 'Short product details for staff reference',
                            prefixIcon: Icon(Icons.notes_outlined),
                            alignLabelWithHint: true,
                          ),
                        ),
                        const SizedBox(height: 20),
                        _VarietyToggle(
                          value: hasVarieties,
                          onChanged: _toggleVarieties,
                        ),
                        const SizedBox(height: 16),
                        if (!hasVarieties) ...[
                        const _FormSectionTitle(
                          icon: Icons.payments_outlined,
                          label: 'Pricing & Inventory',
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: priceController,
                                keyboardType: const TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(
                                    RegExp(r'^\d*\.?\d{0,2}'),
                                  ),
                                ],
                                decoration: InputDecoration(
                                  labelText: 'Selling Price *',
                                  prefixText: pageState.settings.currencySymbol,
                                  prefixIcon: const Icon(Icons.sell_outlined),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: costPriceController,
                                keyboardType: const TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(
                                    RegExp(r'^\d*\.?\d{0,2}'),
                                  ),
                                ],
                                decoration: InputDecoration(
                                  labelText: 'Cost Price',
                                  prefixText: pageState.settings.currencySymbol,
                                  prefixIcon: const Icon(Icons.payments_outlined),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: stockController,
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                                decoration: const InputDecoration(
                                  labelText: 'Stock Qty',
                                  hintText: 'Optional',
                                  prefixIcon: Icon(Icons.warehouse_outlined),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: reorderLevelController,
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                                decoration: const InputDecoration(
                                  labelText: 'Reorder Level',
                                  hintText: 'Low stock alert',
                                  prefixIcon: Icon(Icons.notification_important_outlined),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: skuController,
                                decoration: const InputDecoration(
                                  labelText: 'SKU (optional)',
                                  hintText: 'Leave blank if none',
                                  prefixIcon: Icon(Icons.tag_outlined),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: barcodeController,
                                decoration: const InputDecoration(
                                  labelText: 'Barcode (optional)',
                                  hintText: 'For scanner at register',
                                  prefixIcon: Icon(Icons.qr_code_2_outlined),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        ] else ...[
                          _buildVarietyEditor(pageState),
                          const SizedBox(height: 16),
                        ],
                        if (!hasVarieties) ...[
                          _ProductUnitSelector(
                            selectedUnits: selectedUnits,
                            onAdd: _addUnit,
                            onRemove: _removeUnit,
                          ),
                          const SizedBox(height: 20),
                        ],
                      ],
                    ),
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
                          label: Text(
                            saving
                                ? 'Saving...'
                                : widget.isEditing
                                    ? 'Save Changes'
                                    : 'Save Product',
                          ),
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

class _ProductTableRow {
  const _ProductTableRow({
    required this.index,
    required this.product,
    this.variety,
  });

  final int index;
  final Product product;
  final ProductVariety? variety;
}

List<_ProductTableRow> _buildProductTableRows(List<Product> products) {
  final rows = <_ProductTableRow>[];
  var index = 0;
  for (final product in products) {
    if (product.varieties.isNotEmpty) {
      for (final variety in product.varieties) {
        index++;
        rows.add(_ProductTableRow(index: index, product: product, variety: variety));
      }
    } else {
      index++;
      rows.add(_ProductTableRow(index: index, product: product));
    }
  }
  return rows;
}

class ProductsManagementContent extends StatefulWidget {
  const ProductsManagementContent({
    super.key,
    required this.pageState,
    this.onRefresh,
  });

  final PosHomePageState pageState;
  final VoidCallback? onRefresh;

  @override
  State<ProductsManagementContent> createState() =>
      _ProductsManagementContentState();
}

class _ProductsManagementContentState extends State<ProductsManagementContent> {
  final searchController = TextEditingController();
  String selectedCategory = 'All';

  @override
  void initState() {
    super.initState();
    searchController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  void _notifyChanged() {
    if (mounted) setState(() {});
    widget.onRefresh?.call();
  }

  List<Product> get filteredProducts {
    final query = searchController.text.trim().toLowerCase();
    return widget.pageState.products.where((product) {
      final matchesCategory = selectedCategory == 'All' ||
          product.category == selectedCategory;
      final matchesSearch = query.isEmpty ||
          product.name.toLowerCase().contains(query) ||
          (product.sku ?? '').toLowerCase().contains(query) ||
          product.category.toLowerCase().contains(query);
      return matchesCategory && matchesSearch;
    }).toList();
  }

  int get lowStockCount => widget.pageState.products
      .where((product) => (product.stock ?? 99) <= product.effectiveReorderLevel)
      .length;

  IconData _iconForCategory(String name) {
    ProductCategory? category;
    for (final item in widget.pageState.categories) {
      if (item.name == name) {
        category = item;
        break;
      }
    }
    return resolveCategoryIcon(
      iconKey: category?.icon,
      categoryName: name,
    );
  }

  int _countForCategory(String name) {
    return widget.pageState.products
        .where((product) => product.category == name)
        .length;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: widget.pageState.catalogRevision,
      builder: (context, _, __) => _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    final currency = widget.pageState.settings.currencySymbol;
    final products = filteredProducts;
    final tableRows = _buildProductTableRows(products);
    final categories = widget.pageState.categories;

    const colIndex = 40.0;
    const colCategory = 120.0;
    const colOption = 90.0;
    const colUnit = 100.0;
    const colPrice = 90.0;
    const colCost = 90.0;
    const colStock = 80.0;
    const colAction = 56.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
        const AgriPageHeader(
          badge: 'Products',
          title: 'Items & Categories',
          description:
              'Add categories and products that sync with your tablet register in real time.',
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 720;
            final children = [
              AgriStatCard(
                label: 'Products',
                value: '${widget.pageState.products.length}',
                icon: Icons.inventory_2_outlined,
                tone: AgriStatTone.positive,
              ),
              AgriStatCard(
                label: 'Categories',
                value: '${widget.pageState.categories.length}',
                icon: Icons.category_outlined,
                tone: AgriStatTone.positive,
              ),
              AgriStatCard(
                label: 'Low stock',
                value: '$lowStockCount',
                icon: Icons.warning_amber_rounded,
                tone: lowStockCount > 0
                    ? AgriStatTone.warning
                    : AgriStatTone.neutral,
              ),
              AgriStatCard(
                label: 'Showing',
                value: '${products.length}',
                icon: Icons.grid_view_outlined,
                tone: AgriStatTone.positive,
              ),
            ];

            if (isWide) {
              return Row(
                children: [
                  for (var i = 0; i < children.length; i++) ...[
                    if (i > 0) const SizedBox(width: 12),
                    Expanded(child: children[i]),
                  ],
                ],
              );
            }

            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final child in children)
                  SizedBox(width: 160, height: 120, child: child),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: searchController,
              decoration: InputDecoration(
                hintText: 'Search by name',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: AppColors.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => showAddCategoryDialog(
                    context,
                    widget.pageState,
                    onSaved: _notifyChanged,
                  ),
                  icon: const Icon(Icons.sell_outlined, size: 18),
                  label: const Text('Add Category'),
                ),
                FilledButton.icon(
                  onPressed: () => showAddProductDialog(
                    context,
                    widget.pageState,
                    onSaved: _notifyChanged,
                  ),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add Product'),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: AgriCategoryChip(
                  label: 'All',
                  count: widget.pageState.products.length,
                  selected: selectedCategory == 'All',
                  onTap: () => setState(() => selectedCategory = 'All'),
                ),
              ),
              for (final category in categories)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: AgriCategoryChip(
                    label: category.name,
                    count: _countForCategory(category.name),
                    icon: _iconForCategory(category.name),
                    selected: selectedCategory == category.name,
                    onTap: () => setState(() => selectedCategory = category.name),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        AgriCatalogTable(
          minWidth: 860,
          header: AgriTableHeaderRow(
            cells: const [
              AgriTableHeaderCell(label: '#', width: colIndex, align: TextAlign.center),
              AgriTableHeaderCell(label: 'Category', width: colCategory),
              AgriTableHeaderCell(label: 'Item', flex: true),
              AgriTableHeaderCell(label: 'Option', width: colOption),
              AgriTableHeaderCell(label: 'Unit', width: colUnit),
              AgriTableHeaderCell(label: 'Price', width: colPrice, align: TextAlign.right),
              AgriTableHeaderCell(label: 'Cost', width: colCost, align: TextAlign.right),
              AgriTableHeaderCell(label: 'Stock', width: colStock, align: TextAlign.right),
              AgriTableHeaderCell(label: '', width: colAction, align: TextAlign.right),
            ],
          ),
          rows: [
            for (final row in tableRows)
              Builder(
                builder: (context) {
                  final variety = row.variety;
                  final price = variety?.price ?? row.product.price;
                  final cost = variety?.costPrice ?? row.product.costPrice;
                  final stock = variety?.stock ?? row.product.stock ?? 0;
                  final reorder = variety?.effectiveReorderLevel ??
                      row.product.effectiveReorderLevel;
                  final low = stock <= reorder;
                  final unit = variety?.unit ?? row.product.unit;
                  final unitLabel = unit == null || unit.trim().isEmpty
                      ? productUnitLabel(primaryProductUnit(row.product.unit))
                      : displayProductUnits(unit);

                  return AgriTableDataRow(
                    onTap: () => showProductDetailsDialog(
                      context,
                      product: row.product,
                      currency: currency,
                      pageState: widget.pageState,
                      onEdit: () => showEditProductDialog(
                        context,
                        widget.pageState,
                        product: row.product,
                        onSaved: _notifyChanged,
                      ),
                    ),
                    cells: [
                      AgriTableCell(
                        width: colIndex,
                        align: Alignment.center,
                        child: Text(
                          '${row.index}',
                          style: const TextStyle(color: AppColors.muted),
                        ),
                      ),
                      AgriTableCell(
                        width: colCategory,
                        child: Text(
                          row.product.category,
                          style: const TextStyle(color: AppColors.muted),
                        ),
                      ),
                      AgriTableCell(
                        flex: true,
                        child: Text(
                          row.product.name,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      AgriTableCell(
                        width: colOption,
                        child: Text(
                          variety?.name ?? row.product.displayOption ?? '—',
                          style: const TextStyle(color: AppColors.muted),
                        ),
                      ),
                      AgriTableCell(
                        width: colUnit,
                        child: Text(
                          unitLabel,
                          style: const TextStyle(color: AppColors.muted),
                        ),
                      ),
                      AgriTableCell(
                        width: colPrice,
                        align: Alignment.centerRight,
                        child: Text(
                          formatMoney(currency, price),
                          style: const TextStyle(
                            color: AppColors.green,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      AgriTableCell(
                        width: colCost,
                        align: Alignment.centerRight,
                        child: Text(
                          cost == null ? '—' : formatMoney(currency, cost),
                          style: const TextStyle(color: AppColors.muted),
                        ),
                      ),
                      AgriTableCell(
                        width: colStock,
                        align: Alignment.centerRight,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: low
                                ? AppColors.danger.withValues(alpha: 0.1)
                                : AppColors.green.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '$stock',
                            style: TextStyle(
                              color: low ? AppColors.danger : AppColors.green,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      AgriTableCell(
                        width: colAction,
                        align: Alignment.centerRight,
                        child: IconButton(
                          onPressed: () => showEditProductDialog(
                            context,
                            widget.pageState,
                            product: row.product,
                            onSaved: _notifyChanged,
                          ),
                          icon: const Icon(Icons.edit_outlined, size: 18),
                        ),
                      ),
                    ],
                  );
                },
              ),
          ],
          footer: tableRows.isEmpty
              ? null
              : AgriTableFooterRow(
                  cells: [
                    AgriTableCell(
                      flex: true,
                      child: Text(
                        '${tableRows.length} row${tableRows.length == 1 ? '' : 's'}',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    AgriTableCell(
                      width: colStock,
                      align: Alignment.centerRight,
                      child: Text(
                        '${tableRows.fold<int>(0, (sum, row) => sum + (row.variety?.stock ?? row.product.stock ?? 0))}',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    const AgriTableCell(width: colAction, child: SizedBox.shrink()),
                  ],
                ),
          empty: _EmptyProductsState(
            onAdd: () => showAddProductDialog(
              context,
              widget.pageState,
              onSaved: _notifyChanged,
            ),
          ),
        ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CategoriesPanel extends StatelessWidget {
  const _CategoriesPanel({
    required this.pageState,
    required this.onChanged,
  });

  final PosHomePageState pageState;
  final VoidCallback onChanged;

  int _productCountFor(String categoryName) {
    return pageState.products
        .where((product) => product.category == categoryName)
        .length;
  }

  @override
  Widget build(BuildContext context) {
    final categories = pageState.categories;

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
            children: [
              const Expanded(
                child: Text(
                  'Categories',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.text,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: () => showAddCategoryDialog(
                  context,
                  pageState,
                  onSaved: onChanged,
                ),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Category'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Create categories here, then pick one when adding a product.',
            style: TextStyle(fontSize: 12, color: AppColors.muted),
          ),
          const SizedBox(height: 12),
          if (categories.isEmpty)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.lightGreen,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.greenBorder),
              ),
              child: const Text(
                'No categories yet. Tap Add Category to create one first.',
                style: TextStyle(fontSize: 13, color: AppColors.muted),
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final category in categories)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.lightGreen,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.greenBorder),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          resolveCategoryIcon(
                            iconKey: category.icon,
                            categoryName: category.name,
                          ),
                          size: 16,
                          color: AppColors.green,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          category.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppColors.darkGreen,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${_productCountFor(category.name)}',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: AppColors.green,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _FormSectionTitle extends StatelessWidget {
  const _FormSectionTitle({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.green),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: AppColors.text,
          ),
        ),
      ],
    );
  }
}

class _VarietyToggle extends StatelessWidget {
  const _VarietyToggle({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
      decoration: BoxDecoration(
        color: AppColors.softSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'This product has varieties',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppColors.text,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Track price & stock per variety',
                  style: TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _VarietyDraftCard extends StatelessWidget {
  const _VarietyDraftCard({
    required this.draft,
    required this.index,
    required this.currency,
    required this.canRemove,
    required this.onRemove,
    required this.onChanged,
  });

  final _VarietyDraft draft;
  final int index;
  final String currency;
  final bool canRemove;
  final VoidCallback onRemove;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: draft.nameController,
                  textCapitalization: TextCapitalization.characters,
                  onChanged: (_) => onChanged(),
                  decoration: InputDecoration(
                    labelText: 'Variety ${index + 1} name *',
                    hintText: 'e.g. SUPER 222',
                    isDense: true,
                  ),
                ),
              ),
              IconButton(
                onPressed: canRemove ? onRemove : null,
                icon: const Icon(Icons.delete_outline),
                color: AppColors.danger,
                tooltip: 'Remove variety',
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: draft.priceController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                      RegExp(r'^\d*\.?\d{0,2}'),
                    ),
                  ],
                  decoration: InputDecoration(
                    labelText: 'Price *',
                    prefixText: currency,
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: draft.costController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                      RegExp(r'^\d*\.?\d{0,2}'),
                    ),
                  ],
                  decoration: InputDecoration(
                    labelText: 'Cost',
                    prefixText: currency,
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: draft.stockController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Stock',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: draft.reorderController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Reorder at',
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _ProductUnitSelector(
            selectedUnits: draft.selectedUnits,
            onAdd: (value) {
              if (value == null) return;
              draft.selectedUnits = {
                ...draft.selectedUnits,
                normalizeProductUnit(value),
              };
              onChanged();
            },
            onRemove: (value) {
              draft.selectedUnits = {...draft.selectedUnits}
                ..remove(normalizeProductUnit(value));
              onChanged();
            },
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: draft.skuController,
                  decoration: const InputDecoration(
                    labelText: 'SKU (optional)',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: draft.barcodeController,
                  decoration: const InputDecoration(
                    labelText: 'Barcode (optional)',
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProductUnitSelector extends StatelessWidget {
  const _ProductUnitSelector({
    required this.selectedUnits,
    required this.onAdd,
    required this.onRemove,
  });

  final Set<String> selectedUnits;
  final ValueChanged<String?> onAdd;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    final sortedSelected = selectedUnits.toList()..sort();
    final remaining = availableProductUnits(selectedUnits);

    if (sortedSelected.isEmpty) {
      return DropdownButtonFormField<String>(
        key: const ValueKey('unit-primary'),
        value: null,
        hint: const Text('Select unit'),
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'Unit *',
          hintText: 'Select unit',
          prefixIcon: Icon(Icons.straighten_outlined),
        ),
        items: [
          for (final option in productUnitOptions)
            DropdownMenuItem(
              value: option.value,
              child: Text(option.label),
            ),
        ],
        onChanged: onAdd,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InputDecorator(
          decoration: const InputDecoration(
            labelText: 'Unit(s) *',
            prefixIcon: Icon(Icons.straighten_outlined),
            filled: true,
            fillColor: AppColors.softSurface,
          ),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final unit in sortedSelected)
                InputChip(
                  label: Text(productUnitLabel(unit)),
                  onDeleted: () => onRemove(unit),
                  deleteIconColor: AppColors.green,
                  backgroundColor: AppColors.lightGreen,
                  side: const BorderSide(color: AppColors.greenBorder),
                  labelStyle: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.darkGreen,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          key: ValueKey(sortedSelected.join(',')),
          value: null,
          hint: Text(
            remaining.isEmpty ? 'All units selected' : 'Add another unit',
          ),
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Add unit',
            prefixIcon: Icon(Icons.add_circle_outline),
          ),
          items: [
            for (final value in remaining)
              DropdownMenuItem(
                value: value,
                child: Text(productUnitLabel(value)),
              ),
          ],
          onChanged: remaining.isEmpty
              ? null
              : (value) {
                  if (value != null) {
                    onAdd(value);
                  }
                },
        ),
      ],
    );
  }
}

class _ProductCatalogTile extends StatelessWidget {
  const _ProductCatalogTile({
    super.key,
    required this.product,
    required this.currency,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  final Product product;
  final String currency;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final stock = product.stock;
    final isLowStock = stock != null && stock <= 5;

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
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 64,
                height: 64,
                child: _ProductThumbnail(product: product),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppColors.text,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _InfoChip(
                        icon: Icons.category_outlined,
                        label: product.category,
                      ),
                      if (product.sku != null && product.sku!.isNotEmpty)
                        _InfoChip(
                          icon: Icons.qr_code_2_outlined,
                          label: product.sku!,
                        ),
                      if (isLowStock)
                        const _InfoChip(
                          icon: Icons.warning_amber_rounded,
                          label: 'Low stock',
                          color: AppColors.orange,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  (product.hasVarieties ? 'from ' : '') +
                      formatMoney(currency, product.price),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: AppColors.green,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  product.hasVarieties
                      ? '${product.varieties.length} varieties'
                      : stock == null
                          ? 'Stock: —'
                          : 'Stock: $stock ${product.displayUnit}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isLowStock ? AppColors.orange : AppColors.muted,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _ActionIconButton(
                      icon: Icons.edit_outlined,
                      tooltip: 'Edit',
                      onTap: onEdit,
                    ),
                    const SizedBox(width: 4),
                    _ActionIconButton(
                      icon: Icons.delete_outline,
                      tooltip: 'Delete',
                      color: AppColors.danger,
                      onTap: onDelete,
                    ),
                  ],
                ),
              ],
            ),
          ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProductDetailsDialog extends StatelessWidget {
  const _ProductDetailsDialog({
    required this.product,
    required this.currency,
    this.pageState,
    this.onEdit,
  });

  final Product product;
  final String currency;
  final PosHomePageState? pageState;
  final VoidCallback? onEdit;

  String get _stockLabel {
    final stock = product.stock;
    if (stock == null) return 'Not tracked';
    if (stock <= 0) return 'Out of stock';
    if (stock <= product.effectiveReorderLevel) return 'Low stock';
    return 'In stock';
  }

  Color get _stockColor {
    final stock = product.stock;
    if (stock == null) return AppColors.muted;
    if (stock <= 0) return AppColors.danger;
    if (stock <= product.effectiveReorderLevel) return AppColors.orange;
    return AppColors.green;
  }

  String _formatUpdatedAt() {
    final value = product.updatedAt;
    if (value == null) return '—';
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '$month/$day/${value.year} ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
  }

  String? _categoryIconKey() {
    final categories = pageState?.categories ?? const <ProductCategory>[];
    for (final category in categories) {
      if (category.name == product.category) {
        return category.icon;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.88;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 520, maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 20, 16, 0),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.green,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  resolveCategoryIcon(
                                    iconKey: _categoryIconKey(),
                                    categoryName: product.category,
                                  ),
                                  size: 16,
                                  color: Colors.white,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  product.category,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close),
                            tooltip: 'Close',
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            product.name,
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                              color: AppColors.text,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 6),
                          if (product.description != null &&
                              product.description!.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(
                                product.description!,
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: AppColors.muted,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          Text(
                            'Product ID #${product.id}',
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.muted,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: AppColors.primaryGradient,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 16,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                product.hasVarieties
                                    ? 'Starting Price'
                                    : 'Selling Price',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Text(
                              (product.hasVarieties ? 'from ' : '') +
                                  formatMoney(currency, product.price),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 28,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (product.hasVarieties) ...[
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Varieties',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: AppColors.text,
                              ),
                            ),
                            const SizedBox(height: 8),
                            for (final variety in product.varieties)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: AppColors.softSurface,
                                    borderRadius: BorderRadius.circular(12),
                                    border:
                                        Border.all(color: AppColors.border),
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              variety.name,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w800,
                                                color: AppColors.text,
                                              ),
                                            ),
                                            if (variety.sku != null &&
                                                variety.sku!.isNotEmpty)
                                              Text(
                                                variety.sku!,
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  color: AppColors.muted,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          Text(
                                            formatMoney(
                                                currency, variety.price),
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w900,
                                              color: AppColors.green,
                                            ),
                                          ),
                                          Text(
                                            variety.stock == null
                                                ? '—'
                                                : '${variety.stock} in stock',
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: AppColors.muted,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final chipWidth = (constraints.maxWidth - 10) / 2;
                          return Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              SizedBox(
                                width: chipWidth,
                                child: _DetailInfoChip(
                                  icon: Icons.qr_code_2_outlined,
                                  label: 'Barcode',
                                  value: product.barcode?.isNotEmpty == true
                                      ? product.barcode!
                                      : '—',
                                ),
                              ),
                              SizedBox(
                                width: chipWidth,
                                child: _DetailInfoChip(
                                  icon: Icons.tag_outlined,
                                  label: 'SKU',
                                  value: product.sku?.isNotEmpty == true
                                      ? product.sku!
                                      : 'Auto-generated',
                                ),
                              ),
                              SizedBox(
                                width: chipWidth,
                                child: _DetailInfoChip(
                                  icon: Icons.straighten_outlined,
                                  label: 'Unit(s)',
                                  value: product.displayUnit,
                                ),
                              ),
                              SizedBox(
                                width: chipWidth,
                                child: _DetailInfoChip(
                                  icon: Icons.inventory_2_outlined,
                                  label: 'Stock',
                                  value: product.stock?.toString() ?? '—',
                                  valueColor: _stockColor,
                                ),
                              ),
                              SizedBox(
                                width: chipWidth,
                                child: _DetailInfoChip(
                                  icon: Icons.notification_important_outlined,
                                  label: 'Reorder Level',
                                  value: '${product.effectiveReorderLevel}',
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.softSurface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Column(
                          children: [
                            _ProductDetailRow(
                              label: 'Category',
                              value: product.category,
                            ),
                            const Divider(height: 20, color: AppColors.border),
                            _ProductDetailRow(
                              label: 'Status',
                              value: _stockLabel,
                            ),
                            if (product.costPrice != null) ...[
                              const Divider(height: 20, color: AppColors.border),
                              _ProductDetailRow(
                                label: 'Cost Price',
                                value: formatMoney(currency, product.costPrice!),
                              ),
                              if (product.margin != null)
                                _ProductDetailRow(
                                  label: 'Margin',
                                  value:
                                      '${formatMoney(currency, product.margin!)} (${product.marginPercent?.toStringAsFixed(1) ?? '0'}%)',
                                ),
                            ],
                            const Divider(height: 20, color: AppColors.border),
                            _ProductDetailRow(
                              label: 'Last Updated',
                              value: _formatUpdatedAt(),
                            ),
                            const Divider(height: 20, color: AppColors.border),
                            _ProductDetailRow(
                              label: 'Category ID',
                              value: '#${product.categoryId}',
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1, color: AppColors.border),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 14, 24, 20),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Close'),
                    ),
                  ),
                  if (onEdit != null) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: FilledButton.icon(
                        onPressed: () {
                          final editAction = onEdit;
                          Navigator.pop(context);
                          if (editAction != null) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              editAction();
                            });
                          }
                        },
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        label: const Text('Edit Product'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailInfoChip extends StatelessWidget {
  const _DetailInfoChip({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor = AppColors.text,
    this.iconSize = 16,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color valueColor;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.lightGreen,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.greenBorder),
      ),
      child: Row(
        children: [
          Icon(icon, size: iconSize, color: AppColors.green),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: valueColor,
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

class _ProductDetailRow extends StatelessWidget {
  const _ProductDetailRow({
    required this.label,
    required this.value,
    this.multiline = false,
  });

  final String label;
  final String value;
  final bool multiline;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment:
          multiline ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 110,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.muted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            maxLines: multiline ? 3 : 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
          ),
        ),
      ],
    );
  }
}

class _ProductThumbnail extends StatelessWidget {
  const _ProductThumbnail({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.lightGreen,
      child: ProductCategoryIconFallback(category: product.category),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.icon,
    required this.label,
    this.color = AppColors.green,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
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

class _ActionIconButton extends StatelessWidget {
  const _ActionIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.color = AppColors.green,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.softSurface,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Tooltip(
          message: tooltip,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(icon, size: 18, color: color),
          ),
        ),
      ),
    );
  }
}

class _EmptyProductsState extends StatelessWidget {
  const _EmptyProductsState({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppColors.lightGreen,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(
              Icons.inventory_2_outlined,
              size: 36,
              color: AppColors.green,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'No products found',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Add your first farm supply product to start selling on the register.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: const Text('Add First Product'),
          ),
        ],
      ),
    );
  }
}
