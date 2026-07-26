import 'package:flutter/material.dart';

import '../../../core/theme/agri_admin_widgets.dart';
import '../../../core/theme/app_colors.dart';

class AgriRangePill extends StatelessWidget {
  const AgriRangePill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.green : AppColors.softSurface,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: selected ? Colors.white : AppColors.text,
            ),
          ),
        ),
      ),
    );
  }
}

class AgriFilterDropdown<T> extends StatelessWidget {
  const AgriFilterDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.width = 180,
  });

  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: DropdownButtonFormField<T>(
        value: value,
        isExpanded: true,
        items: items,
        onChanged: onChanged,
        decoration: InputDecoration(
          filled: true,
          fillColor: AppColors.surface,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.border),
          ),
        ),
      ),
    );
  }
}

class AgriCatalogTable extends StatelessWidget {
  const AgriCatalogTable({
    super.key,
    required this.minWidth,
    required this.header,
    required this.rows,
    this.footer,
    this.empty,
    this.loading = false,
  });

  final double minWidth;
  final Widget header;
  final List<Widget> rows;
  final Widget? footer;
  final Widget? empty;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return AgriCard(
        clipBehavior: Clip.antiAlias,
        padding: EdgeInsets.zero,
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: 48),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    if (rows.isEmpty) {
      return AgriCard(
        clipBehavior: Clip.antiAlias,
        padding: EdgeInsets.zero,
        child: empty ??
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(
                child: Text(
                  'No items match your filters',
                  style: TextStyle(color: AppColors.muted),
                ),
              ),
            ),
      );
    }

    return AgriCard(
      clipBehavior: Clip.antiAlias,
      padding: EdgeInsets.zero,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final tableWidth = constraints.maxWidth.isFinite
              ? constraints.maxWidth.clamp(minWidth, double.infinity)
              : minWidth;

          final table = SizedBox(
            width: tableWidth,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                header,
                ...rows,
                if (footer != null) footer!,
              ],
            ),
          );

          if (constraints.maxWidth < minWidth) {
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: table,
            );
          }

          return table;
        },
      ),
    );
  }
}

class AgriTableHeaderRow extends StatelessWidget {
  const AgriTableHeaderRow({super.key, required this.cells});

  final List<Widget> cells;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.softSurface.withValues(alpha: 0.85),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Row(
        children: cells,
      ),
    );
  }
}

class AgriTableHeaderCell extends StatelessWidget {
  const AgriTableHeaderCell({
    super.key,
    required this.label,
    this.width,
    this.flex = false,
    this.align = TextAlign.left,
  }) : assert(flex || width != null);

  final String label;
  final double? width;
  final bool flex;
  final TextAlign align;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      label,
      textAlign: align,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: AppColors.muted,
      ),
    );

    if (flex) {
      return Expanded(child: text);
    }

    return SizedBox(width: width, child: text);
  }
}

class AgriTableDataRow extends StatelessWidget {
  const AgriTableDataRow({
    super.key,
    required this.cells,
    this.onTap,
  });

  final List<Widget> cells;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(color: AppColors.border, width: 0.5),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: cells,
          ),
        ),
      ),
    );
  }
}

class AgriTableFooterRow extends StatelessWidget {
  const AgriTableFooterRow({super.key, required this.cells});

  final List<Widget> cells;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.softSurface.withValues(alpha: 0.7),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Row(
        children: cells,
      ),
    );
  }
}

class AgriTableCell extends StatelessWidget {
  const AgriTableCell({
    super.key,
    this.width,
    this.flex = false,
    required this.child,
    this.align = Alignment.centerLeft,
  }) : assert(flex || width != null);

  final double? width;
  final bool flex;
  final Widget child;
  final Alignment align;

  @override
  Widget build(BuildContext context) {
    final content = Align(alignment: align, child: child);

    if (flex) {
      return Expanded(child: content);
    }

    return SizedBox(width: width, child: content);
  }
}

class AgriCategoryChip extends StatelessWidget {
  const AgriCategoryChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.count,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final text = count == null ? label : '$label $count';

    return Material(
      color: selected ? AppColors.green : AppColors.surface,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? AppColors.green : AppColors.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 14,
                  color: selected ? Colors.white : AppColors.green,
                ),
                const SizedBox(width: 6),
              ],
              Text(
                text,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : AppColors.text,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
