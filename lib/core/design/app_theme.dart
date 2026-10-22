import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'app_colors.dart';
import 'app_typography.dart';
import 'app_spacing.dart';

/// Полная тема Personal Hub на основе Material 3 Design System.
class AppTheme {
  AppTheme._();

  static ThemeData get light {
    final colorScheme = AppColors.lightColorScheme;
    final textTheme = AppTypography.lightTextTheme;

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: colorScheme,
      textTheme: textTheme.apply(
        bodyColor: colorScheme.onSurface,
        displayColor: colorScheme.onSurface,
      ),

      // AppBar
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: AppSpacing.elevation0,
        scrolledUnderElevation: AppSpacing.elevation1,
        surfaceTintColor: Colors.transparent,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          color: colorScheme.onSurface,
        ),
      ),

      // Card — на ПРИПОДЯТОЙ поверхности, не на базовой.
      //
      // Раньше cardTheme.color был равен colorScheme.surface, то есть
      // цвету фона Scaffold: в тёмной теме карточки визуально не
      // отделялись от фона (аудит Stage 10). В Warm Bronze / Raw
      // Tactile (Stage 11) поверхность `#21201D` и есть «приподнятая»
      // ступень — ей и принадлежат карточки.
      cardTheme: CardThemeData(
        color: colorScheme.surfaceContainerHighest,
        elevation: AppElevation.getLight(1),
        shadowColor: colorScheme.shadow.withValues(alpha: 0.1),
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.md,
        ),
      ),

      // Buttons
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: Size(0, AppSpacing.buttonMinHeight),
          padding: EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.sm,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: AppRadii.sm,
          ),
          textStyle: AppTypography.lightTextTheme.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: Size(0, AppSpacing.buttonMinHeight),
          padding: EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.sm,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: AppRadii.sm,
          ),
          side: BorderSide(
            color: colorScheme.outlineVariant,
            width: 1,
          ),
          textStyle: AppTypography.lightTextTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: Size(0, AppSpacing.buttonMinHeight),
          padding: EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.sm,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: AppRadii.sm,
          ),
          textStyle: AppTypography.lightTextTheme.labelLarge,
        ),
      ),

      // Input
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest,
        contentPadding: EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        border: OutlineInputBorder(
          borderRadius: AppRadii.sm,
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadii.sm,
          borderSide: BorderSide(
            color: colorScheme.outlineVariant,
            width: 1,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadii.sm,
          borderSide: BorderSide(
            color: colorScheme.primary,
            width: 2,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: AppRadii.sm,
          borderSide: BorderSide(
            color: colorScheme.error,
            width: 1,
          ),
        ),
        labelStyle: AppTypography.lightTextTheme.bodyMedium?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
        hintStyle: AppTypography.lightTextTheme.bodyMedium?.copyWith(
          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
        ),
      ),

      // Chip
      chipTheme: ChipThemeData(
        backgroundColor: colorScheme.surfaceContainerHighest,
        selectedColor: colorScheme.primaryContainer,
        disabledColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        labelStyle: AppTypography.chipLabel.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
        secondaryLabelStyle: AppTypography.chipLabel.copyWith(
          color: colorScheme.onPrimaryContainer,
        ),
        padding: EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.full,
        ),
      ),

      // Divider
      dividerTheme: DividerThemeData(
        color: colorScheme.outlineVariant,
        thickness: 1,
        space: 1,
        indent: AppSpacing.md,
        endIndent: AppSpacing.md,
      ),

      // ListTile
      listTileTheme: ListTileThemeData(
        minTileHeight: AppSpacing.listTileMinHeight,
        contentPadding: AppInsets.listItemPadding,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.sm,
        ),
        tileColor: Colors.transparent,
        selectedTileColor: colorScheme.primaryContainer,
        iconColor: colorScheme.onSurfaceVariant,
        textColor: colorScheme.onSurface,
        titleTextStyle: AppTypography.lightTextTheme.titleMedium,
        subtitleTextStyle: AppTypography.lightTextTheme.bodySmall,
      ),

      // Dialog
      dialogTheme: DialogThemeData(
        backgroundColor: colorScheme.surface,
        elevation: AppSpacing.elevation3,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.lg,
        ),
        titleTextStyle: AppTypography.lightTextTheme.titleLarge?.copyWith(
          color: colorScheme.onSurface,
        ),
        contentTextStyle: AppTypography.lightTextTheme.bodyMedium?.copyWith(
          color: colorScheme.onSurface,
        ),
        surfaceTintColor: Colors.transparent,
      ),

      // BottomSheet
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colorScheme.surface,
        elevation: AppSpacing.elevation3,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.topLg,
        ),
        surfaceTintColor: Colors.transparent,
        dragHandleColor: colorScheme.onSurfaceVariant,
        dragHandleSize: Size(36, 4),
        modalBackgroundColor: colorScheme.surface,
      ),

      // NavigationDrawer
      navigationDrawerTheme: NavigationDrawerThemeData(
        backgroundColor: colorScheme.surface,
        elevation: AppSpacing.elevation2,
        surfaceTintColor: Colors.transparent,
        indicatorColor: colorScheme.primaryContainer,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AppTypography.lightTextTheme.labelLarge?.copyWith(
              color: colorScheme.onPrimaryContainer,
            );
          }
          return AppTypography.lightTextTheme.labelLarge?.copyWith(
            color: colorScheme.onSurface,
          );
        }),
      ),

      // FloatingActionButton
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppColors.accentAmber.withValues(alpha: 0.12),
        foregroundColor: AppColors.accentAmber,
        elevation: AppElevation.getLight(3),
        focusElevation: AppElevation.getLight(3),
        hoverElevation: AppElevation.getLight(3),
        highlightElevation: AppElevation.getLight(3),
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.xl,
        ),
      ),

      // SnackBar
      snackBarTheme: SnackBarThemeData(
        backgroundColor: colorScheme.inverseSurface,
        contentTextStyle: AppTypography.lightTextTheme.bodyMedium?.copyWith(
          color: colorScheme.onInverseSurface,
        ),
        actionTextColor: colorScheme.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.md,
        ),
        elevation: AppElevation.getLight(3),
      ),

      // Page Transitions
      pageTransitionsTheme: PageTransitionsTheme(
        builders: {
          TargetPlatform.android: ZoomPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: ZoomPageTransitionsBuilder(),
          TargetPlatform.linux: ZoomPageTransitionsBuilder(),
        },
      ),
    );
  }

  static ThemeData get dark {
    final colorScheme = AppColors.darkColorScheme;
    final textTheme = AppTypography.darkTextTheme;

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      textTheme: textTheme.apply(
        bodyColor: colorScheme.onSurface,
        displayColor: colorScheme.onSurface,
      ),

      // AppBar
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: AppSpacing.elevation0,
        scrolledUnderElevation: AppSpacing.elevation1,
        surfaceTintColor: Colors.transparent,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          color: colorScheme.onSurface,
        ),
      ),

      // Card
      // Card — приподнятая поверхность `#21201D` (Raw Tactile, Stage 11),
      // чтобы карточки читались на фоне `#181716`. Тень в тёмной теме
      // почти не видна, поэтому разделение держится на цвете.
      cardTheme: CardThemeData(
        color: colorScheme.surfaceContainerHighest,
        elevation: AppElevation.getDark(1),
        shadowColor: colorScheme.shadow.withValues(alpha: 0.3),
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.md,
        ),
      ),

      // Buttons
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: Size(0, AppSpacing.buttonMinHeight),
          padding: EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.sm,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: AppRadii.sm,
          ),
          textStyle: AppTypography.darkTextTheme.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: Size(0, AppSpacing.buttonMinHeight),
          padding: EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.sm,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: AppRadii.sm,
          ),
          side: BorderSide(
            color: colorScheme.outlineVariant,
            width: 1,
          ),
          textStyle: AppTypography.darkTextTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: Size(0, AppSpacing.buttonMinHeight),
          padding: EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.sm,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: AppRadii.sm,
          ),
          textStyle: AppTypography.darkTextTheme.labelLarge,
        ),
      ),

      // Input
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest,
        contentPadding: EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        border: OutlineInputBorder(
          borderRadius: AppRadii.sm,
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadii.sm,
          borderSide: BorderSide(
            color: colorScheme.outlineVariant,
            width: 1,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadii.sm,
          borderSide: BorderSide(
            color: colorScheme.primary,
            width: 2,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: AppRadii.sm,
          borderSide: BorderSide(
            color: colorScheme.error,
            width: 1,
          ),
        ),
        labelStyle: AppTypography.darkTextTheme.bodyMedium?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
        hintStyle: AppTypography.darkTextTheme.bodyMedium?.copyWith(
          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
        ),
      ),

      // Chip
      chipTheme: ChipThemeData(
        backgroundColor: colorScheme.surfaceContainerHighest,
        selectedColor: colorScheme.primaryContainer,
        disabledColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        labelStyle: AppTypography.chipLabel.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
        secondaryLabelStyle: AppTypography.chipLabel.copyWith(
          color: colorScheme.onPrimaryContainer,
        ),
        padding: EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.full,
        ),
      ),

      // Divider
      dividerTheme: DividerThemeData(
        color: colorScheme.outlineVariant,
        thickness: 1,
        space: 1,
        indent: AppSpacing.md,
        endIndent: AppSpacing.md,
      ),

      // ListTile
      listTileTheme: ListTileThemeData(
        minTileHeight: AppSpacing.listTileMinHeight,
        contentPadding: AppInsets.listItemPadding,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.sm,
        ),
        tileColor: Colors.transparent,
        selectedTileColor: colorScheme.primaryContainer,
        iconColor: colorScheme.onSurfaceVariant,
        textColor: colorScheme.onSurface,
        titleTextStyle: AppTypography.darkTextTheme.titleMedium,
        subtitleTextStyle: AppTypography.darkTextTheme.bodySmall,
      ),

      // Dialog
      dialogTheme: DialogThemeData(
        backgroundColor: colorScheme.surface,
        elevation: AppSpacing.elevation3,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.lg,
        ),
        titleTextStyle: AppTypography.darkTextTheme.titleLarge?.copyWith(
          color: colorScheme.onSurface,
        ),
        contentTextStyle: AppTypography.darkTextTheme.bodyMedium?.copyWith(
          color: colorScheme.onSurface,
        ),
        surfaceTintColor: Colors.transparent,
      ),

      // BottomSheet
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colorScheme.surface,
        elevation: AppSpacing.elevation3,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.topLg,
        ),
        surfaceTintColor: Colors.transparent,
        dragHandleColor: colorScheme.onSurfaceVariant,
        dragHandleSize: Size(36, 4),
        modalBackgroundColor: colorScheme.surface,
      ),

      // NavigationDrawer
      navigationDrawerTheme: NavigationDrawerThemeData(
        backgroundColor: colorScheme.surface,
        elevation: AppSpacing.elevation2,
        surfaceTintColor: Colors.transparent,
        indicatorColor: colorScheme.primaryContainer,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AppTypography.darkTextTheme.labelLarge?.copyWith(
              color: colorScheme.onPrimaryContainer,
            );
          }
          return AppTypography.darkTextTheme.labelLarge?.copyWith(
            color: colorScheme.onSurface,
          );
        }),
      ),

      // FloatingActionButton
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppColors.accentAmber.withValues(alpha: 0.15),
        foregroundColor: AppColors.accentAmber,
        elevation: AppElevation.getDark(3),
        focusElevation: AppElevation.getDark(3),
        hoverElevation: AppElevation.getDark(3),
        highlightElevation: AppElevation.getDark(3),
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.xl,
        ),
      ),

      // SnackBar
      snackBarTheme: SnackBarThemeData(
        backgroundColor: colorScheme.inverseSurface,
        contentTextStyle: AppTypography.darkTextTheme.bodyMedium?.copyWith(
          color: colorScheme.onInverseSurface,
        ),
        actionTextColor: colorScheme.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.md,
        ),
        elevation: AppElevation.getDark(3),
      ),

      // Page Transitions
      pageTransitionsTheme: PageTransitionsTheme(
        builders: {
          TargetPlatform.android: ZoomPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: ZoomPageTransitionsBuilder(),
          TargetPlatform.linux: ZoomPageTransitionsBuilder(),
        },
      ),
    );
  }
}