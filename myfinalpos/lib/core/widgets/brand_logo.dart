import 'package:flutter/material.dart';

import '../constants/brand.dart';
import '../theme/app_colors.dart';

enum BrandLogoSize { sm, md, lg }

class BrandLogo extends StatelessWidget {
  const BrandLogo({
    super.key,
    this.size = BrandLogoSize.md,
    this.subtitle = AppBrand.posSubtitle,
    this.showLogo = true,
    this.showText = true,
    this.onDark = false,
    this.alignment = CrossAxisAlignment.start,
  });

  final BrandLogoSize size;
  final String? subtitle;
  final bool showLogo;
  final bool showText;
  final bool onDark;
  final CrossAxisAlignment alignment;

  @override
  Widget build(BuildContext context) {
    final markSize = switch (size) {
      BrandLogoSize.sm => 36.0,
      BrandLogoSize.md => 44.0,
      BrandLogoSize.lg => 64.0,
    };
    final nameSize = switch (size) {
      BrandLogoSize.sm => 14.0,
      BrandLogoSize.md => 16.0,
      BrandLogoSize.lg => 20.0,
    };
    final subtitleSize = switch (size) {
      BrandLogoSize.sm => 11.0,
      BrandLogoSize.md => 12.0,
      BrandLogoSize.lg => 13.0,
    };

    final nameColor =
        onDark ? AppColors.sidebarForeground : AppColors.text;
    final subtitleColor =
        onDark ? AppColors.sidebarMuted : AppColors.muted;

    final logoMark = Container(
      width: markSize,
      height: markSize,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: onDark
              ? Colors.white.withValues(alpha: 0.1)
              : AppColors.border,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Image.asset(
        AppBrand.logoAsset,
        fit: BoxFit.contain,
      ),
    );

    final textBlock = showText
        ? Column(
            crossAxisAlignment: alignment,
            children: [
              Text(
                AppBrand.shortName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: alignment == CrossAxisAlignment.center
                    ? TextAlign.center
                    : TextAlign.start,
                style: TextStyle(
                  fontSize: nameSize,
                  fontWeight: FontWeight.w800,
                  color: nameColor,
                  height: 1.1,
                ),
              ),
              if (subtitle != null && subtitle!.isNotEmpty)
                Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: alignment == CrossAxisAlignment.center
                      ? TextAlign.center
                      : TextAlign.start,
                  style: TextStyle(
                    fontSize: subtitleSize,
                    fontWeight: FontWeight.w500,
                    color: subtitleColor,
                    height: 1.2,
                  ),
                ),
            ],
          )
        : null;

    if (alignment == CrossAxisAlignment.center) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showLogo) logoMark,
          if (showLogo && textBlock != null) const SizedBox(height: 12),
          if (textBlock != null) textBlock,
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (showLogo) logoMark,
        if (showLogo && textBlock != null) const SizedBox(width: 10),
        if (textBlock != null)
          alignment == CrossAxisAlignment.start
              ? Expanded(child: textBlock)
              : textBlock,
      ],
    );
  }
}
