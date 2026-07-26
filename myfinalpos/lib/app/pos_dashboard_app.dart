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
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.green,
          primary: AppColors.green,
          secondary: AppColors.amber,
          surface: AppColors.surface,
        ),
        scaffoldBackgroundColor: AppColors.page,
        fontFamily: 'Roboto',
        dividerColor: AppColors.border,
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.green,
            foregroundColor: Colors.white,
            minimumSize: const Size(48, 46),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppColors.green, width: 1.4),
          ),
        ),
      ),
      home: const SplashPage(),
    );
  }
}
