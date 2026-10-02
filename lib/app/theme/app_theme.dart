import 'package:flutter/material.dart';

/// Colour roles from the v1 design system (design/product-proposal-v1/03-design-system.md).
abstract final class AppColors {
  static const Color background = Color(0xFF0D1117);
  static const Color surface1 = Color(0xFF141A23);
  static const Color surface2 = Color(0xFF1A212C);
  static const Color surface3 = Color(0xFF232C38);
  static const Color surfaceSheet = Color(0xFF181F29);
  static const Color surfaceDialog = Color(0xFF1C2430);
  static const Color borderSubtle = Color(0xFF2A3441);
  static const Color borderStrong = Color(0xFF3B4757);
  static const Color navBar = Color(0xFF11161E);

  static const Color accentPrimary = Color(0xFF86D7FF);
  static const Color accentPressed = Color(0xFF68C8F5);
  static const Color tonalForeground = Color(0xFFA9E4FF);
  static const Color tonalBackground = Color(0x2486D7FF);

  static const Color textPrimary = Color(0xFFF2F5F8);
  static const Color textSecondary = Color(0xFFAAB4C0);
  static const Color textTertiary = Color(0xFF8591A0);

  static const Color success = Color(0xFF5FD3A6);
  static const Color warning = Color(0xFFF5C26B);
  static const Color error = Color(0xFFFF8A8A);
  static const Color errorStrong = Color(0xFFF26D6D);
  static const Color processing = Color(0xFF00E5FF);

  static const Color originSampleForeground = Color(0xFFC7BCFF);
  static const Color originSampleBackground = Color(0x337B61FF);
  static const Color originAiForeground = Color(0xFF8BEFFF);
  static const Color originAiBackground = Color(0x2100E5FF);

  static const Color brandCyan = Color(0xFF00E5FF);
  static const Color brandBlue = Color(0xFF2979FF);
  static const Color brandViolet = Color(0xFF7B61FF);
  static const Color scrim = Color(0xA803060A);

  static const LinearGradient brandGradient = LinearGradient(
    colors: <Color>[brandCyan, brandBlue, brandViolet],
    stops: <double>[0, 0.55, 1],
  );

  static Color tint(Color color, [double alpha = 0.14]) =>
      color.withValues(alpha: alpha);
}

abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double page = 20;
  static const double xl = 24;
  static const double xxl = 32;

  /// Page gutter: 20dp, 16dp below 390dp width.
  static double gutter(BuildContext context) =>
      MediaQuery.sizeOf(context).width < 390 ? 16 : page;
}

abstract final class AppRadii {
  static const double xs = 8;
  static const double small = 12;
  static const double medium = 16;
  static const double large = 20;
  static const double xl = 28;
  static const double full = 999;
}

/// Layout adaptations for large system text (≥150%), e.g. grids become lists.
bool isLargeText(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(10) >= 15;

abstract final class AppTheme {
  static ThemeData get dark {
    const ColorScheme scheme = ColorScheme.dark(
      primary: AppColors.accentPrimary,
      onPrimary: AppColors.background,
      primaryContainer: AppColors.tonalBackground,
      onPrimaryContainer: AppColors.tonalForeground,
      secondary: AppColors.accentPrimary,
      onSecondary: AppColors.background,
      error: AppColors.error,
      onError: AppColors.background,
      surface: AppColors.surface1,
      onSurface: AppColors.textPrimary,
      onSurfaceVariant: AppColors.textSecondary,
      surfaceContainerLowest: AppColors.background,
      surfaceContainerLow: AppColors.surface1,
      surfaceContainer: AppColors.surface2,
      surfaceContainerHigh: AppColors.surfaceSheet,
      surfaceContainerHighest: AppColors.surface3,
      outline: AppColors.borderStrong,
      outlineVariant: AppColors.borderSubtle,
      inverseSurface: Color(0xFFE6EDF3),
      onInverseSurface: AppColors.background,
      inversePrimary: Color(0xFF0B5CAD),
      scrim: AppColors.scrim,
    );

    const TextTheme text = TextTheme(
      displaySmall: TextStyle(
        color: AppColors.textPrimary,
        fontSize: 28,
        height: 36 / 28,
        fontWeight: FontWeight.w600,
      ),
      headlineMedium: TextStyle(
        color: AppColors.textPrimary,
        fontSize: 24,
        height: 32 / 24,
        fontWeight: FontWeight.w600,
      ),
      headlineSmall: TextStyle(
        color: AppColors.textPrimary,
        fontSize: 24,
        height: 32 / 24,
        fontWeight: FontWeight.w600,
      ),
      titleLarge: TextStyle(
        color: AppColors.textPrimary,
        fontSize: 20,
        height: 28 / 20,
        fontWeight: FontWeight.w600,
      ),
      titleMedium: TextStyle(
        color: AppColors.textPrimary,
        fontSize: 17,
        height: 24.5 / 17,
        fontWeight: FontWeight.w600,
      ),
      bodyLarge: TextStyle(
        color: AppColors.textPrimary,
        fontSize: 16,
        height: 1.55,
      ),
      bodyMedium: TextStyle(
        color: AppColors.textSecondary,
        fontSize: 14,
        height: 1.55,
      ),
      bodySmall: TextStyle(
        color: AppColors.textTertiary,
        fontSize: 12,
        height: 1.5,
      ),
      labelLarge: TextStyle(
        color: AppColors.textPrimary,
        fontSize: 16,
        height: 1.4,
        fontWeight: FontWeight.w600,
      ),
      labelMedium: TextStyle(
        color: AppColors.textSecondary,
        fontSize: 14,
        height: 1.45,
        fontWeight: FontWeight.w500,
      ),
      labelSmall: TextStyle(
        color: AppColors.textSecondary,
        fontSize: 12,
        height: 1.35,
        fontWeight: FontWeight.w600,
      ),
    );

    final RoundedRectangleBorder buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadii.medium),
    );
    const Size buttonMinimum = Size(64, 52);
    const EdgeInsets buttonPadding = EdgeInsets.symmetric(
      horizontal: 20,
      vertical: 12,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.background,
      canvasColor: AppColors.background,
      splashFactory: InkSparkle.splashFactory,
      textTheme: text,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleSpacing: 4,
        toolbarHeight: 56,
        titleTextStyle: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 20,
          height: 28 / 20,
          fontWeight: FontWeight.w600,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.accentPrimary,
          foregroundColor: AppColors.background,
          disabledBackgroundColor: AppColors.textPrimary.withValues(alpha: 0.1),
          disabledForegroundColor: AppColors.textPrimary.withValues(
            alpha: 0.38,
          ),
          minimumSize: buttonMinimum,
          padding: buttonPadding,
          shape: buttonShape,
          textStyle: text.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          disabledForegroundColor: AppColors.textPrimary.withValues(
            alpha: 0.38,
          ),
          side: const BorderSide(color: AppColors.borderStrong),
          minimumSize: buttonMinimum,
          padding: buttonPadding,
          shape: buttonShape,
          textStyle: text.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.accentPrimary,
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.small),
          ),
          textStyle: text.labelLarge,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          minimumSize: const Size.square(48),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.borderSubtle,
        thickness: 1,
        space: 1,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surfaceDialog,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.xl),
        ),
        titleTextStyle: text.titleLarge,
        contentTextStyle: text.bodyMedium,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surfaceSheet,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: AppColors.surfaceSheet,
        showDragHandle: true,
        dragHandleColor: AppColors.borderStrong,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadii.xl),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFFE6EDF3),
        contentTextStyle: const TextStyle(
          color: AppColors.background,
          fontSize: 14,
          height: 1.45,
        ),
        actionTextColor: const Color(0xFF0B5CAD),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.small),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.navBar,
        surfaceTintColor: Colors.transparent,
        indicatorColor: AppColors.tonalBackground,
        height: 72,
        labelTextStyle: WidgetStateProperty.resolveWith<TextStyle>(
          (Set<WidgetState> states) => TextStyle(
            fontSize: 12,
            height: 1.3,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? AppColors.textPrimary
                : AppColors.textSecondary,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith<IconThemeData>(
          (Set<WidgetState> states) => IconThemeData(
            size: 24,
            color: states.contains(WidgetState.selected)
                ? AppColors.tonalForeground
                : AppColors.textSecondary,
          ),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith<Color>(
          (Set<WidgetState> states) => states.contains(WidgetState.selected)
              ? AppColors.background
              : AppColors.textTertiary,
        ),
        trackColor: WidgetStateProperty.resolveWith<Color>(
          (Set<WidgetState> states) => states.contains(WidgetState.selected)
              ? AppColors.accentPrimary
              : AppColors.surface3,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith<Color>(
          (Set<WidgetState> states) => states.contains(WidgetState.selected)
              ? AppColors.accentPrimary
              : AppColors.borderStrong,
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith<Color>(
          (Set<WidgetState> states) => states.contains(WidgetState.selected)
              ? AppColors.accentPrimary
              : Colors.transparent,
        ),
        checkColor: const WidgetStatePropertyAll<Color>(AppColors.background),
        side: const BorderSide(color: AppColors.textSecondary, width: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface1,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        hintStyle: const TextStyle(color: AppColors.textTertiary),
        helperStyle: text.bodySmall,
        errorStyle: text.bodySmall?.copyWith(color: AppColors.error),
        counterStyle: text.bodySmall,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.small),
          borderSide: const BorderSide(color: AppColors.borderStrong),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.small),
          borderSide: const BorderSide(color: AppColors.borderStrong),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.small),
          borderSide: const BorderSide(
            color: AppColors.accentPrimary,
            width: 2,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.small),
          borderSide: const BorderSide(color: AppColors.error, width: 2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.small),
          borderSide: const BorderSide(color: AppColors.error, width: 2),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.accentPrimary,
        linearTrackColor: AppColors.surface3,
        circularTrackColor: Color(0x24F2F5F8),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: AppColors.textSecondary,
        textColor: AppColors.textPrimary,
        minVerticalPadding: 12,
      ),
    );
  }
}
