import 'package:flutter/material.dart';

/// Two hand-picked palettes (ui-ux-pro-max "Swiss" dashboard for light, a dark
/// "court" scoreboard for dark) chosen by the phone's light/dark setting.
/// Screens use [ColorScheme] roles and [StatColors], never raw colors. primary/tertiary are
/// also the radar's two series and pass the dataviz palette validator in both modes.

const _light = ColorScheme(
  brightness: Brightness.light,
  primary: Color(0xFF2563EB),
  onPrimary: Colors.white,
  primaryContainer: Color(0xFFDBEAFE),
  onPrimaryContainer: Color(0xFF1E3A8A),
  secondary: Color(0xFF475569),
  onSecondary: Colors.white,
  secondaryContainer: Color(0xFFE2E8F0),
  onSecondaryContainer: Color(0xFF0F172A),
  tertiary: Color(0xFFD97706),
  onTertiary: Colors.black,
  tertiaryContainer: Color(0xFFFEF3C7),
  onTertiaryContainer: Color(0xFF78350F),
  error: Color(0xFFB91C1C),
  onError: Colors.white,
  errorContainer: Color(0xFFFEE2E2),
  onErrorContainer: Color(0xFF7F1D1D),
  surface: Color(0xFFF8FAFC),
  onSurface: Color(0xFF0F172A),
  onSurfaceVariant: Color(0xFF475569),
  surfaceContainerLowest: Colors.white,
  surfaceContainerLow: Colors.white,
  surfaceContainer: Color(0xFFF1F5F9),
  surfaceContainerHigh: Color(0xFFE9EEF6),
  surfaceContainerHighest: Color(0xFFE2E8F0),
  outline: Color(0xFF94A3B8),
  outlineVariant: Color(0xFFE2E8F0),
  inverseSurface: Color(0xFF0F172A),
  onInverseSurface: Color(0xFFF1F5F9),
  inversePrimary: Color(0xFF93C5FD),
);

const _dark = ColorScheme(
  brightness: Brightness.dark,
  primary: Color(0xFFEA580C),
  onPrimary: Color(0xFF0B1220),
  primaryContainer: Color(0xFF431A06),
  onPrimaryContainer: Color(0xFFFDBA74),
  secondary: Color(0xFF94A3B8),
  onSecondary: Color(0xFF0B1220),
  secondaryContainer: Color(0xFF1E293B),
  onSecondaryContainer: Color(0xFFE2E8F0),
  tertiary: Color(0xFF3B9EDB),
  onTertiary: Color(0xFF0B1220),
  tertiaryContainer: Color(0xFF0C3A52),
  onTertiaryContainer: Color(0xFFBAE6FD),
  error: Color(0xFFF43F5E),
  onError: Color(0xFF0B1220),
  errorContainer: Color(0xFF4C0519),
  onErrorContainer: Color(0xFFFECDD3),
  surface: Color(0xFF0B1220),
  onSurface: Color(0xFFE2E8F0),
  onSurfaceVariant: Color(0xFF94A3B8),
  surfaceContainerLowest: Color(0xFF131C2E),
  surfaceContainerLow: Color(0xFF131C2E),
  surfaceContainer: Color(0xFF172238),
  surfaceContainerHigh: Color(0xFF1C2740),
  surfaceContainerHighest: Color(0xFF243049),
  outline: Color(0xFF64748B),
  outlineVariant: Color(0xFF1E293B),
  inverseSurface: Color(0xFFE2E8F0),
  onInverseSurface: Color(0xFF0B1220),
  inversePrimary: Color(0xFFC2410C),
);

/// Win / loss / warning colors that Material's roles don't cover. Always paired
/// with an icon or text, never color alone.
@immutable
class StatColors extends ThemeExtension<StatColors> {
  final Color win;
  final Color loss;
  final Color warn;
  final Color warnContainer;
  final Color onWarnContainer;

  const StatColors({
    required this.win,
    required this.loss,
    required this.warn,
    required this.warnContainer,
    required this.onWarnContainer,
  });

  static const light = StatColors(
    win: Color(0xFF15803D),
    loss: Color(0xFFB91C1C),
    warn: Color(0xFFB45309),
    warnContainer: Color(0xFFFEF3C7),
    onWarnContainer: Color(0xFF78350F),
  );

  static const dark = StatColors(
    win: Color(0xFF22C55E),
    loss: Color(0xFFF43F5E),
    warn: Color(0xFFFBBF24),
    warnContainer: Color(0xFF422006),
    onWarnContainer: Color(0xFFFDE68A),
  );

  @override
  StatColors copyWith() => this;

  @override
  StatColors lerp(StatColors? other, double t) => t < 0.5 || other == null ? this : other;
}

extension StatColorsX on BuildContext {
  StatColors get stat => Theme.of(this).extension<StatColors>()!;

  /// Green for positive z, red for negative.
  Color zColor(double z) => z >= 0 ? stat.win : stat.loss;
}

ThemeData buildTheme(Brightness brightness) {
  final c = brightness == Brightness.light ? _light : _dark;
  final base = ThemeData(colorScheme: c, useMaterial3: true);
  final rounded12 = RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));

  // Tabular figures everywhere so z-scores and stats line up in columns.
  TextStyle? tab(TextStyle? s) => s?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
  final t = base.textTheme;
  final text = t.copyWith(
    displayLarge: tab(t.displayLarge),
    displayMedium: tab(t.displayMedium),
    displaySmall: tab(t.displaySmall),
    headlineLarge: tab(t.headlineLarge),
    headlineMedium: tab(t.headlineMedium),
    headlineSmall: tab(t.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
    titleLarge: tab(t.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
    titleMedium: tab(t.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
    titleSmall: tab(t.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
    bodyLarge: tab(t.bodyLarge),
    bodyMedium: tab(t.bodyMedium),
    bodySmall: tab(t.bodySmall?.copyWith(color: c.onSurfaceVariant)),
    labelLarge: tab(t.labelLarge?.copyWith(fontWeight: FontWeight.w600)),
    labelMedium: tab(t.labelMedium),
    labelSmall: tab(t.labelSmall),
  );

  return base.copyWith(
    scaffoldBackgroundColor: c.surface,
    textTheme: text,
    extensions: [brightness == Brightness.light ? StatColors.light : StatColors.dark],
    appBarTheme: AppBarTheme(
      backgroundColor: c.surface,
      foregroundColor: c.onSurface,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: text.headlineSmall?.copyWith(color: c.onSurface),
    ),
    cardTheme: CardThemeData(
      color: c.surfaceContainerLowest,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: c.outlineVariant),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: c.surfaceContainerLowest,
      surfaceTintColor: Colors.transparent,
      indicatorColor: c.primaryContainer,
      height: 68,
      labelTextStyle: WidgetStateProperty.all(text.labelMedium?.copyWith(fontWeight: FontWeight.w600)),
    ),
    listTileTheme: ListTileThemeData(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      iconColor: c.onSurfaceVariant,
      subtitleTextStyle: text.bodySmall,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.surfaceContainer,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: c.primary, width: 2),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(minimumSize: const Size(64, 48), shape: rounded12, textStyle: text.labelLarge),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 48),
        shape: rounded12,
        side: BorderSide(color: c.outline),
        textStyle: text.labelLarge,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(minimumSize: const Size(48, 48), shape: rounded12, textStyle: text.labelLarge),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      side: BorderSide(color: c.outlineVariant),
      backgroundColor: c.surfaceContainerLowest,
      selectedColor: c.primaryContainer,
      labelStyle: text.labelLarge,
    ),
    dividerTheme: DividerThemeData(color: c.outlineVariant, space: 1, thickness: 1),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.surfaceContainerLowest,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.surfaceContainerLowest,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(selectedBackgroundColor: c.primaryContainer, minimumSize: const Size(48, 44)),
    ),
  );
}
