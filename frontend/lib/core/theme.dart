import 'package:flutter/material.dart';

import 'design_tokens.dart';

/// The exact mint from `assets/branding/` (sampled: RGB 114,214,176) -- the
/// seed for the whole tonal palette, and also forced as `primary` itself
/// (see below) since `ColorScheme.fromSeed`'s own tone-40/tone-80 pick for
/// "primary" is close but not pixel-identical to the source logo color.
const _brandMint = Color(0xFF72D6B0);

/// The exact navy from the icon's background (RGB 23,37,43) -- used as-is
/// for dark mode's `surface`, rather than the green-tinted near-black
/// `ColorScheme.fromSeed` would derive from the mint seed, so dark mode
/// actually looks like the icon's own navy card instead of an
/// algorithm's approximation of it.
const _brandNavy = Color(0xFF17252B);

/// Navy blended progressively toward white -- the M3 "elevation" ramp
/// (surfaceContainerLow < ...High < ...Highest) hand-tuned around the brand
/// navy instead of derived from the seed, so cards/app bar/nav bar in dark
/// mode read as *the* brand navy at different tints, not a nearby guess.
Color _onNavy(double t) => Color.lerp(_brandNavy, Colors.white, t)!;

/// Every component theme below exists because the previous `ThemeData`
/// was `ColorScheme.fromSeed(...) + useMaterial3: true` and nothing else --
/// every screen fell back to raw Material defaults (underlined text fields,
/// borderless flat `ListTile`s, an unstyled `NavigationBar`), which reads as
/// an unfinished prototype next to a polished tracker like Hevy. Centralizing
/// the look here means individual screens don't have to (and shouldn't)
/// repeat shape/color/padding choices themselves.
ThemeData buildTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final seeded = ColorScheme.fromSeed(seedColor: _brandMint, brightness: brightness);

  // Mint is light and highly saturated, so navy text/icons on it clear
  // WCAG AA by a wide margin -- white-on-mint would not. Everything else
  // (secondary/tertiary/error, and primaryContainer's tone) stays whatever
  // `fromSeed` derived, for tonal harmony with the forced primary.
  final colorScheme = !isDark
      ? seeded.copyWith(primary: _brandMint, onPrimary: _brandNavy, inversePrimary: _brandMint)
      : seeded.copyWith(
          primary: _brandMint,
          onPrimary: _brandNavy,
          inversePrimary: _brandMint,
          surface: _brandNavy,
          onSurface: _onNavy(0.93),
          onSurfaceVariant: _onNavy(0.70),
          surfaceContainerLowest: Color.lerp(_brandNavy, Colors.black, 0.10)!,
          surfaceContainerLow: _onNavy(0.05),
          surfaceContainer: _onNavy(0.09),
          surfaceContainerHigh: _onNavy(0.15),
          surfaceContainerHighest: _onNavy(0.22),
          outline: _onNavy(0.45),
          outlineVariant: _onNavy(0.20),
        );

  final fieldBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppRadius.sm),
    borderSide: BorderSide.none,
  );

  return ThemeData(
    brightness: brightness,
    colorScheme: colorScheme,
    useMaterial3: true,
    scaffoldBackgroundColor: colorScheme.surface,
    splashFactory: InkSparkle.splashFactory,
    visualDensity: VisualDensity.standard,

    textTheme: const TextTheme(
      headlineMedium: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.5),
      headlineSmall: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.4),
      titleLarge: TextStyle(fontWeight: FontWeight.w700, letterSpacing: -0.2),
      titleMedium: TextStyle(fontWeight: FontWeight.w600),
      titleSmall: TextStyle(fontWeight: FontWeight.w600),
      bodyLarge: TextStyle(height: 1.35),
      bodyMedium: TextStyle(height: 1.35),
      labelLarge: TextStyle(fontWeight: FontWeight.w600),
    ),

    appBarTheme: AppBarTheme(
      backgroundColor: colorScheme.surface,
      foregroundColor: colorScheme.onSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 2,
      shadowColor: colorScheme.shadow.withValues(alpha: 0.15),
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.4,
        color: colorScheme.onSurface,
      ),
    ),

    cardTheme: CardThemeData(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: isDark ? 0.5 : 0.7)),
      ),
    ),

    listTileTheme: ListTileThemeData(
      iconColor: colorScheme.onSurfaceVariant,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xs,
      ),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: isDark ? 0.4 : 0.55),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      border: fieldBorder,
      enabledBorder: fieldBorder,
      disabledBorder: fieldBorder,
      focusedBorder: fieldBorder.copyWith(
        borderSide: BorderSide(color: colorScheme.primary, width: 2),
      ),
      errorBorder: fieldBorder.copyWith(
        borderSide: BorderSide(color: colorScheme.error, width: 1.5),
      ),
      focusedErrorBorder: fieldBorder.copyWith(
        borderSide: BorderSide(color: colorScheme.error, width: 2),
      ),
    ),

    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(50),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        side: BorderSide(color: colorScheme.outline),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
      ),
    ),

    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: colorScheme.primary,
      foregroundColor: colorScheme.onPrimary,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
    ),

    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: colorScheme.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      indicatorColor: colorScheme.primaryContainer,
      elevation: 3,
      height: 68,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 12,
          fontWeight: states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
          color: states.contains(WidgetState.selected)
              ? colorScheme.onSurface
              : colorScheme.onSurfaceVariant,
        ),
      ),
    ),

    chipTheme: ChipThemeData(
      backgroundColor: colorScheme.surfaceContainerHighest,
      side: BorderSide.none,
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: colorScheme.onSurfaceVariant,
      ),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
    ),

    dividerTheme: DividerThemeData(color: colorScheme.outlineVariant, space: 1, thickness: 1),

    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
    ),

    dialogTheme: DialogThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
      surfaceTintColor: Colors.transparent,
    ),

    switchTheme: SwitchThemeData(
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
  );
}
