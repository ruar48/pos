import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Shared admin UI primitives matching the Laravel web `agri-*` design system.

enum AgriKpiTone { orange, teal, green, coral }

enum AgriStatTone { positive, warning, danger, neutral }

class AgriAdminTheme {
  static const pagePadding = EdgeInsets.fromLTRB(20, 20, 20, 20);
  static const cardRadius = 16.0;
  static const cardBorder = Color(0x99E1E7EC);

  static BoxDecoration cardDecoration({Color? color}) {
    return BoxDecoration(
      color: color ?? AppColors.surface,
      borderRadius: BorderRadius.circular(cardRadius),
      border: Border.all(color: cardBorder),
      boxShadow: [
        BoxShadow(
          color: const Color(0x0A17202A),
          blurRadius: 2,
          offset: const Offset(0, 1),
        ),
        BoxShadow(
          color: const Color(0x0817202A),
          blurRadius: 16,
          offset: const Offset(0, 4),
        ),
      ],
    );
  }

  static LinearGradient kpiGradient(AgriKpiTone tone) {
    switch (tone) {
      case AgriKpiTone.orange:
        return const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF5A962), Color(0xFFE8924A)],
        );
      case AgriKpiTone.teal:
        return const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF5EC4B8), Color(0xFF45B5A8)],
        );
      case AgriKpiTone.green:
        return const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF6FCF97), Color(0xFF56C486)],
        );
      case AgriKpiTone.coral:
        return const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF2847A), Color(0xFFE86A5E)],
        );
    }
  }

  static Color statIconBackground(AgriStatTone tone) {
    switch (tone) {
      case AgriStatTone.warning:
        return AppColors.amber.withValues(alpha: 0.12);
      case AgriStatTone.danger:
        return AppColors.danger.withValues(alpha: 0.12);
      case AgriStatTone.neutral:
        return AppColors.softSurface;
      case AgriStatTone.positive:
        return AppColors.green.withValues(alpha: 0.12);
    }
  }

  static Color statIconColor(AgriStatTone tone) {
    switch (tone) {
      case AgriStatTone.warning:
        return AppColors.amber;
      case AgriStatTone.danger:
        return AppColors.danger;
      case AgriStatTone.neutral:
        return AppColors.muted;
      case AgriStatTone.positive:
        return AppColors.green;
    }
  }
}

class AgriCard extends StatelessWidget {
  const AgriCard({
    super.key,
    required this.child,
    this.padding,
    this.clipBehavior = Clip.none,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Clip clipBehavior;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: clipBehavior,
      decoration: AgriAdminTheme.cardDecoration(),
      padding: padding,
      child: child,
    );
  }
}

class AgriPageHeader extends StatelessWidget {
  const AgriPageHeader({
    super.key,
    required this.title,
    this.badge,
    this.description,
    this.actions,
  });

  final String title;
  final String? badge;
  final String? description;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stackHeader = constraints.maxWidth < 720;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (badge != null) ...[
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  badge!.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: AppColors.green,
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
            if (stackHeader) ...[
              Text(
                title,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: AppColors.text,
                  height: 1.15,
                  letterSpacing: -0.3,
                ),
              ),
              if (description != null) ...[
                const SizedBox(height: 6),
                Text(
                  description!,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    color: AppColors.muted,
                  ),
                ),
              ],
              if (actions != null && actions!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: actions!,
                ),
              ],
            ] else
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: AppColors.text,
                            height: 1.15,
                            letterSpacing: -0.3,
                          ),
                        ),
                        if (description != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            description!,
                            style: const TextStyle(
                              fontSize: 14,
                              height: 1.5,
                              color: AppColors.muted,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (actions != null && actions!.isNotEmpty) ...[
                    const SizedBox(width: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.end,
                      children: actions!,
                    ),
                  ],
                ],
              ),
          ],
        );
      },
    );
  }
}

class AgriIconBox extends StatelessWidget {
  const AgriIconBox({
    super.key,
    required this.icon,
    this.size = 44,
    this.iconSize = 20,
    this.tone = AgriStatTone.positive,
  });

  final IconData icon;
  final double size;
  final double iconSize;
  final AgriStatTone tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AgriAdminTheme.statIconBackground(tone),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(
        icon,
        size: iconSize,
        color: AgriAdminTheme.statIconColor(tone),
      ),
    );
  }
}

class AgriStatCard extends StatelessWidget {
  const AgriStatCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.hint,
    this.tone = AgriStatTone.positive,
  });

  final String label;
  final String value;
  final IconData icon;
  final String? hint;
  final AgriStatTone tone;

  @override
  Widget build(BuildContext context) {
    return AgriCard(
      padding: const EdgeInsets.all(20),
      child: SizedBox(
        height: 120,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    label.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      color: AppColors.muted,
                    ),
                  ),
                ),
                AgriIconBox(icon: icon, size: 32, iconSize: 16, tone: tone),
              ],
            ),
            const Spacer(),
            Text(
              value,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: AppColors.text,
                height: 1.1,
              ),
            ),
            if (hint != null) ...[
              const SizedBox(height: 4),
              Text(
                hint!,
                style: const TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class DashboardKpiCard extends StatelessWidget {
  const DashboardKpiCard({
    super.key,
    required this.label,
    required this.value,
    required this.tone,
  });

  final String label;
  final String value;
  final AgriKpiTone tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 88),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: AgriAdminTheme.kpiGradient(tone),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.95),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}

class AgriStatusBadge extends StatelessWidget {
  const AgriStatusBadge({
    super.key,
    required this.ok,
    required this.label,
  });

  final bool ok;
  final String label;

  @override
  Widget build(BuildContext context) {
    final color = ok ? AppColors.green : AppColors.danger;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            ok ? Icons.check_circle_outline : Icons.cancel_outlined,
            size: 14,
            color: color,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class AgriSegmentedTabs extends StatelessWidget {
  const AgriSegmentedTabs({
    super.key,
    required this.tabs,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<AgriTabItem> tabs;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return AgriCard(
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          for (var i = 0; i < tabs.length; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            Expanded(
              child: _AgriTabButton(
                item: tabs[i],
                selected: selectedIndex == i,
                onTap: () => onSelected(i),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class AgriTabItem {
  const AgriTabItem({required this.label, required this.icon});

  final String label;
  final IconData icon;
}

class _AgriTabButton extends StatelessWidget {
  const _AgriTabButton({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final AgriTabItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.lightGreen : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                item.icon,
                size: 18,
                color: selected ? AppColors.green : AppColors.muted,
              ),
              const SizedBox(width: 8),
              Text(
                item.label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: selected ? AppColors.green : AppColors.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
