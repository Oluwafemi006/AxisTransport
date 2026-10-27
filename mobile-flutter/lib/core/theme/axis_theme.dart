import 'package:flutter/material.dart';

import 'axis_colors.dart';
import 'axis_spacing.dart';
import 'axis_tokens.dart';
import 'axis_typography.dart';

export 'axis_spacing.dart';
export 'axis_tokens.dart';
export 'axis_typography.dart';

/// Thème clair Axis (Material 3). Pas de thème sombre pour l'instant (phase 1).
abstract final class AxisTheme {
  static ThemeData light() {
    final textTheme = AxisTypography.textTheme();

    final colorScheme = ColorScheme.fromSeed(
      seedColor: AxisPalette.primary,
      brightness: Brightness.light,
    ).copyWith(
      primary: AxisPalette.primary,
      onPrimary: AxisPalette.onDark,
      primaryContainer: AxisPalette.primarySoft,
      onPrimaryContainer: AxisPalette.primaryDark,
      // Sur l'ambre, le texte est toujours bleu marine (jamais blanc).
      secondary: AxisPalette.accent,
      onSecondary: AxisPalette.primary,
      secondaryContainer: AxisPalette.accentSoft,
      onSecondaryContainer: AxisPalette.onAccentSoft,
      surface: AxisPalette.surface,
      onSurface: AxisPalette.ink,
      onSurfaceVariant: AxisPalette.textSecondary,
      surfaceTint: Colors.transparent,
      error: AxisPalette.danger,
      onError: AxisPalette.onDark,
      outline: AxisPalette.borderStrong,
      outlineVariant: AxisPalette.border,
    );

    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AxisRadius.button),
    );

    OutlineInputBorder fieldBorder(Color color, [double width = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(AxisRadius.field),
          borderSide: BorderSide(color: color, width: width),
        );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      fontFamily: AxisTypography.fontFamily,
      textTheme: textTheme,
      scaffoldBackgroundColor: AxisPalette.background,
      dividerColor: AxisPalette.border,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      extensions: const [AxisTokens.light],

      appBarTheme: AppBarTheme(
        backgroundColor: AxisPalette.background,
        foregroundColor: AxisPalette.ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge,
        iconTheme: const IconThemeData(color: AxisPalette.ink, size: 24),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AxisPalette.primary,
          foregroundColor: AxisPalette.onDark,
          disabledBackgroundColor: AxisPalette.disabled,
          disabledForegroundColor: AxisPalette.textMuted,
          minimumSize: const Size.fromHeight(AxisSizes.primaryButton),
          shape: buttonShape,
          textStyle: textTheme.labelLarge,
          elevation: 0,
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AxisPalette.primary,
          disabledForegroundColor: AxisPalette.textMuted,
          minimumSize: const Size.fromHeight(AxisSizes.secondaryButton),
          shape: buttonShape,
          side: const BorderSide(color: AxisPalette.borderStrong),
          textStyle: textTheme.labelLarge,
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AxisPalette.primary,
          minimumSize: const Size(AxisSizes.minTarget, AxisSizes.minTarget),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AxisRadius.small),
          ),
          textStyle: textTheme.labelMedium,
        ),
      ),

      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(AxisSizes.minTarget, AxisSizes.minTarget),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AxisPalette.surface,
        // ~50 px de hauteur avec le corps de texte à 15.
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AxisSpacing.s14,
          vertical: AxisSpacing.s14,
        ),
        constraints: const BoxConstraints(minHeight: AxisSizes.field),
        labelStyle: textTheme.labelMedium?.copyWith(color: AxisPalette.textMuted),
        floatingLabelStyle: textTheme.labelMedium?.copyWith(color: AxisPalette.primary),
        hintStyle: textTheme.bodyMedium?.copyWith(color: AxisPalette.textMuted),
        helperStyle: textTheme.bodySmall,
        errorStyle: textTheme.bodySmall?.copyWith(color: AxisPalette.danger),
        prefixIconColor: AxisPalette.textMuted,
        suffixIconColor: AxisPalette.textMuted,
        border: fieldBorder(AxisPalette.borderStrong),
        enabledBorder: fieldBorder(AxisPalette.borderStrong),
        disabledBorder: fieldBorder(AxisPalette.border),
        focusedBorder: fieldBorder(AxisPalette.primary, 1.6),
        errorBorder: fieldBorder(AxisPalette.danger),
        focusedErrorBorder: fieldBorder(AxisPalette.danger, 1.6),
      ),

      cardTheme: CardThemeData(
        color: AxisPalette.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AxisRadius.card),
          side: const BorderSide(color: AxisPalette.border),
        ),
      ),

      navigationBarTheme: NavigationBarThemeData(
        height: AxisSizes.navigationBar,
        backgroundColor: AxisPalette.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        indicatorColor: AxisPalette.primarySoft,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? textTheme.labelSmall?.copyWith(
                  color: AxisPalette.primary,
                  fontWeight: FontWeight.w700,
                )
              : textTheme.labelSmall?.copyWith(color: AxisPalette.textMuted),
        ),
        // Icônes inactives en textMuted (contraste suffisant sur blanc).
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 24,
            color: states.contains(WidgetState.selected)
                ? AxisPalette.primary
                : AxisPalette.textMuted,
          ),
        ),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: AxisPalette.surface,
        selectedColor: AxisPalette.primarySoft,
        disabledColor: AxisPalette.disabled,
        side: const BorderSide(color: AxisPalette.border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AxisRadius.chip),
        ),
        labelStyle: textTheme.labelMedium,
        secondaryLabelStyle: textTheme.labelMedium?.copyWith(color: AxisPalette.primary),
        padding: const EdgeInsets.symmetric(horizontal: AxisSpacing.s8, vertical: AxisSpacing.s6),
        checkmarkColor: AxisPalette.primary,
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: AxisPalette.ink,
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: AxisPalette.onDark),
        actionTextColor: AxisPalette.accent,
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AxisRadius.small),
        ),
      ),

      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AxisPalette.surface,
        modalBackgroundColor: AxisPalette.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        modalElevation: 0,
        dragHandleColor: AxisPalette.borderStrong,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AxisRadius.sheet)),
        ),
      ),

      dividerTheme: const DividerThemeData(
        color: AxisPalette.border,
        thickness: 1,
      ),
    );
  }
}

