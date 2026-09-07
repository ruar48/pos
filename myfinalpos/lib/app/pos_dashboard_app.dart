import 'package:flutter/material.dart';

import '../core/constants/brand.dart';
import '../core/theme/app_colors.dart';
import '../core/utils/top_toast.dart';
import '../core/widgets/tablet_landscape_scope.dart';
import '../features/auth/splash_page.dart';

class PosDashboardApp extends StatelessWidget {
  const PosDashboardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: appNavigatorKey,
      debugShowCheckedModeBanner: false,
      title: AppBrand.shortName,
      builder: (context, child) {
        return TabletLandscapeScope(
          child: child ?? const SizedBox.shrink(),
        );
      },
      theme: _buildCafeTheme(),
      home: const SplashPage(),
    );
  }
}

/// Warm artisan café / bakery theme.
///
/// Every colour comes from `AppColors`; nothing is hardcoded here so the whole
/// look can be re-tuned from the token file.
ThemeData _buildCafeTheme() {
  const radius = 12.0;
  const fieldRadius = 10.0;

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.espresso,
      primary: AppColors.espresso,
      onPrimary: Colors.white,
      primaryContainer: AppColors.lightGreen,
      onPrimaryContainer: AppColors.darkGreen,
      secondary: AppColors.caramel,
      onSecondary: Colors.white,
      secondaryContainer: AppColors.caramelSoft,
      onSecondaryContainer: AppColors.caramelDeep,
      tertiary: AppColors.sage,
      onTertiary: Colors.white,
      tertiaryContainer: AppColors.successSoft,
      onTertiaryContainer: AppColors.success,
      error: AppColors.danger,
      onError: Colors.white,
      errorContainer: AppColors.dangerSoft,
      onErrorContainer: AppColors.danger,
      surface: AppColors.surface,
      onSurface: AppColors.text,
      surfaceContainerLowest: AppColors.surface,
      surfaceContainerLow: AppColors.softSurface,
      surfaceContainer: AppColors.page,
      surfaceContainerHigh: AppColors.lightGreen,
      onSurfaceVariant: AppColors.muted,
      outline: AppColors.border,
      outlineVariant: AppColors.border,
    ),
    scaffoldBackgroundColor: AppColors.page,
    fontFamily: 'Roboto',
    dividerColor: AppColors.border,
    splashFactory: InkRipple.splashFactory,
  );

  return base.copyWith(
    // -------------------------------------------------------------------
    // Typography — headings carry a little more character (tight tracking,
    // heavy weight); anything a cashier reads at a glance stays plain and
    // generously sized.
    // -------------------------------------------------------------------
    textTheme: base.textTheme
        .apply(bodyColor: AppColors.text, displayColor: AppColors.text)
        .copyWith(
          displaySmall: const TextStyle(
            fontSize: 34,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.6,
            height: 1.1,
            color: AppColors.text,
          ),
          headlineMedium: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
            height: 1.15,
            color: AppColors.text,
          ),
          headlineSmall: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
            height: 1.2,
            color: AppColors.text,
          ),
          titleLarge: const TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.2,
            color: AppColors.text,
          ),
          titleMedium: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppColors.text,
          ),
          titleSmall: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppColors.text,
          ),
          bodyLarge: const TextStyle(fontSize: 15, height: 1.45),
          bodyMedium: const TextStyle(fontSize: 14, height: 1.45),
          bodySmall: const TextStyle(
            fontSize: 12.5,
            height: 1.4,
            color: AppColors.muted,
          ),
          labelLarge: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.1,
          ),
          labelSmall: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            color: AppColors.muted,
          ),
        ),

    // -------------------------------------------------------------------
    // Header
    // -------------------------------------------------------------------
    appBarTheme: const AppBarTheme(
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: AppColors.surface,
      foregroundColor: AppColors.text,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      iconTheme: IconThemeData(color: AppColors.espresso, size: 22),
      actionsIconTheme: IconThemeData(color: AppColors.espresso, size: 22),
      titleTextStyle: TextStyle(
        color: AppColors.text,
        fontSize: 20,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.3,
      ),
    ),

    // -------------------------------------------------------------------
    // Navigation
    // -------------------------------------------------------------------
    drawerTheme: const DrawerThemeData(
      backgroundColor: AppColors.sidebar,
      surfaceTintColor: Colors.transparent,
      scrimColor: Color(0x66332A26),
      elevation: 0,
    ),
    navigationRailTheme: const NavigationRailThemeData(
      backgroundColor: AppColors.sidebar,
      selectedIconTheme: IconThemeData(color: AppColors.sidebarForeground),
      unselectedIconTheme: IconThemeData(color: AppColors.sidebarMuted),
      indicatorColor: AppColors.sidebarAccent,
    ),
    tabBarTheme: const TabBarThemeData(
      labelColor: AppColors.espresso,
      unselectedLabelColor: AppColors.muted,
      indicatorColor: AppColors.caramel,
      dividerColor: AppColors.border,
      labelStyle: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
      unselectedLabelStyle:
          TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    ),

    // -------------------------------------------------------------------
    // Surfaces
    // -------------------------------------------------------------------
    cardTheme: CardThemeData(
      color: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.border,
      thickness: 1,
      space: 1,
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: AppColors.muted,
      textColor: AppColors.text,
      selectedColor: AppColors.espresso,
      selectedTileColor: AppColors.lightGreen,
      titleTextStyle: TextStyle(
        fontSize: 14.5,
        fontWeight: FontWeight.w700,
        color: AppColors.text,
      ),
      subtitleTextStyle: TextStyle(fontSize: 12.5, color: AppColors.muted),
    ),
    iconTheme: const IconThemeData(color: AppColors.muted, size: 22),

    // -------------------------------------------------------------------
    // Buttons — the primary action is always espresso on cream.
    // -------------------------------------------------------------------
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.espresso,
        foregroundColor: Colors.white,
        disabledBackgroundColor: AppColors.border,
        disabledForegroundColor: AppColors.mutedSoft,
        minimumSize: const Size(48, 46),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        elevation: 0,
        textStyle: const TextStyle(
          fontSize: 14.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.1,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(fieldRadius),
        ),
      ).copyWith(
        overlayColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.pressed) ||
              states.contains(WidgetState.hovered)) {
            return AppColors.espressoHover;
          }
          return null;
        }),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.espresso,
        foregroundColor: Colors.white,
        disabledBackgroundColor: AppColors.border,
        disabledForegroundColor: AppColors.mutedSoft,
        minimumSize: const Size(48, 46),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        elevation: 0,
        shadowColor: AppColors.shadowSoft,
        textStyle: const TextStyle(
          fontSize: 14.5,
          fontWeight: FontWeight.w700,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(fieldRadius),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.espresso,
        backgroundColor: AppColors.surface,
        minimumSize: const Size(48, 46),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        side: const BorderSide(color: AppColors.greenBorder),
        textStyle: const TextStyle(
          fontSize: 14.5,
          fontWeight: FontWeight.w700,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(fieldRadius),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.espresso,
        textStyle: const TextStyle(
          fontSize: 14.5,
          fontWeight: FontWeight.w700,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(fieldRadius),
        ),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: AppColors.espresso,
        hoverColor: AppColors.lightGreen,
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.espresso,
      foregroundColor: Colors.white,
      elevation: 2,
      focusElevation: 2,
      hoverElevation: 3,
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? AppColors.espresso
              : AppColors.surface;
        }),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? Colors.white
              : AppColors.muted;
        }),
        side: const WidgetStatePropertyAll(
          BorderSide(color: AppColors.greenBorder),
        ),
        textStyle: const WidgetStatePropertyAll(
          TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(fieldRadius),
          ),
        ),
      ),
    ),

    // -------------------------------------------------------------------
    // Inputs & search
    // -------------------------------------------------------------------
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
      hintStyle: const TextStyle(color: AppColors.mutedSoft, fontSize: 14),
      labelStyle: const TextStyle(color: AppColors.muted, fontSize: 14),
      floatingLabelStyle: const TextStyle(
        color: AppColors.espresso,
        fontWeight: FontWeight.w700,
      ),
      prefixIconColor: AppColors.mutedSoft,
      suffixIconColor: AppColors.mutedSoft,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(fieldRadius),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(fieldRadius),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(fieldRadius),
        borderSide: const BorderSide(color: AppColors.caramel, width: 1.6),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(fieldRadius),
        borderSide: const BorderSide(color: AppColors.danger),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(fieldRadius),
        borderSide: const BorderSide(color: AppColors.danger, width: 1.6),
      ),
    ),
    dropdownMenuTheme: DropdownMenuThemeData(
      menuStyle: MenuStyle(
        backgroundColor: const WidgetStatePropertyAll(AppColors.surface),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(3),
        shadowColor: const WidgetStatePropertyAll(AppColors.shadowSoft),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius),
            side: const BorderSide(color: AppColors.border),
          ),
        ),
      ),
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: const WidgetStatePropertyAll(AppColors.surface),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius),
            side: const BorderSide(color: AppColors.border),
          ),
        ),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: const BorderSide(color: AppColors.border),
      ),
      textStyle: const TextStyle(fontSize: 14, color: AppColors.text),
    ),

    // -------------------------------------------------------------------
    // Category tabs / chips
    // -------------------------------------------------------------------
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.surface,
      selectedColor: AppColors.espresso,
      disabledColor: AppColors.softSurface,
      surfaceTintColor: Colors.transparent,
      // Checkmarks stay on: several FilterChips across the admin pages use
      // them as their only selected-state affordance.
      checkmarkColor: Colors.white,
      side: const BorderSide(color: AppColors.greenBorder),
      elevation: 0,
      pressElevation: 0,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      labelStyle: const TextStyle(
        fontSize: 13.5,
        fontWeight: FontWeight.w700,
        color: AppColors.text,
      ),
      secondaryLabelStyle: const TextStyle(
        fontSize: 13.5,
        fontWeight: FontWeight.w700,
        color: Colors.white,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(999),
      ),
    ),
    badgeTheme: const BadgeThemeData(
      backgroundColor: AppColors.caramel,
      textColor: Colors.white,
      textStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
    ),

    // -------------------------------------------------------------------
    // Modals & sheets
    // -------------------------------------------------------------------
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 6,
      shadowColor: AppColors.shadowSoft,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: AppColors.border),
      ),
      titleTextStyle: const TextStyle(
        fontSize: 19,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.2,
        color: AppColors.text,
      ),
      contentTextStyle: const TextStyle(
        fontSize: 14,
        height: 1.45,
        color: AppColors.text,
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      modalBackgroundColor: AppColors.surface,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      dragHandleColor: AppColors.greenBorder,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: AppColors.darkGreen,
        borderRadius: BorderRadius.circular(8),
      ),
      textStyle: const TextStyle(
        color: AppColors.milk,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    ),

    // -------------------------------------------------------------------
    // Tables
    // -------------------------------------------------------------------
    dataTableTheme: DataTableThemeData(
      headingRowColor: const WidgetStatePropertyAll(AppColors.softSurface),
      headingTextStyle: const TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.7,
        color: AppColors.muted,
      ),
      dataTextStyle: const TextStyle(fontSize: 13.5, color: AppColors.text),
      dividerThickness: 1,
      dataRowColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return AppColors.lightGreen;
        if (states.contains(WidgetState.hovered)) return AppColors.softSurface;
        return null;
      }),
    ),

    // -------------------------------------------------------------------
    // Feedback — loading, alerts, selection controls
    // -------------------------------------------------------------------
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.espresso,
      linearTrackColor: AppColors.lightGreen,
      circularTrackColor: Colors.transparent,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.darkGreen,
      contentTextStyle: const TextStyle(
        color: AppColors.milk,
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
      actionTextColor: AppColors.sidebarWheat,
      behavior: SnackBarBehavior.floating,
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        return states.contains(WidgetState.selected)
            ? Colors.white
            : AppColors.surface;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        return states.contains(WidgetState.selected)
            ? AppColors.espresso
            : AppColors.border;
      }),
      trackOutlineColor:
          const WidgetStatePropertyAll(AppColors.greenBorder),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        return states.contains(WidgetState.selected)
            ? AppColors.espresso
            : Colors.transparent;
      }),
      checkColor: const WidgetStatePropertyAll(Colors.white),
      side: const BorderSide(color: AppColors.greenBorder, width: 1.4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        return states.contains(WidgetState.selected)
            ? AppColors.espresso
            : AppColors.mutedSoft;
      }),
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor: AppColors.espresso,
      inactiveTrackColor: AppColors.lightGreen,
      thumbColor: AppColors.espresso,
      overlayColor: Color(0x1F4B2E24),
    ),
  );
}
