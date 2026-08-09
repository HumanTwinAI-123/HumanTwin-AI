import 'package:flutter/material.dart';

abstract final class AppColors {
  static const Color background = Color(0xFF090D12);
  static const Color surface1 = Color(0xFF11171E);
  static const Color surface2 = Color(0xFF171F28);
  static const Color borderSubtle = Color(0xFF29333E);
  static const Color accentPrimary = Color(0xFF86D7FF);
  static const Color accentPressed = Color(0xFF68C8F5);
  static const Color textPrimary = Color(0xFFF4F7FA);
  static const Color textSecondary = Color(0xFFA3AFBC);
  static const Color textTertiary = Color(0xFF6F7B87);
  static const Color success = Color(0xFF7ED6B4);
  static const Color error = Color(0xFFFF8D8D);
}

abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double page = 20;
  static const double xl = 24;
  static const double xxl = 32;
}

abstract final class AppRadii {
  static const double small = 12;
  static const double medium = 16;
  static const double large = 20;
  static const double full = 999;
}

abstract final class AppTheme {
  static ThemeData get dark {
    const ColorScheme scheme = ColorScheme.dark(
      primary: AppColors.accentPrimary,
      onPrimary: AppColors.background,
      secondary: AppColors.accentPrimary,
      onSecondary: AppColors.background,
      error: AppColors.error,
      onError: AppColors.background,
      surface: AppColors.surface1,
      onSurface: AppColors.textPrimary,
      onSurfaceVariant: AppColors.textSecondary,
      outline: AppColors.borderSubtle,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.background,
      splashFactory: InkSparkle.splashFactory,
      textTheme: const TextTheme(
        headlineMedium: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 28,
          height: 34 / 28,
          fontWeight: FontWeight.w600,
        ),
        titleLarge: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 22,
          height: 28 / 22,
          fontWeight: FontWeight.w600,
        ),
        titleMedium: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 18,
          height: 24 / 18,
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: TextStyle(
          color: AppColors.textSecondary,
          fontSize: 15,
          height: 22 / 15,
          fontWeight: FontWeight.w400,
        ),
        labelLarge: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 15,
          height: 22 / 15,
          fontWeight: FontWeight.w500,
        ),
        labelMedium: TextStyle(
          color: AppColors.textSecondary,
          fontSize: 13,
          height: 18 / 13,
          fontWeight: FontWeight.w500,
        ),
        bodySmall: TextStyle(
          color: AppColors.textTertiary,
          fontSize: 12,
          height: 16 / 12,
          fontWeight: FontWeight.w400,
        ),
      ),
    );
  }
}
