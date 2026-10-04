import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/models.dart';

/// Huddle's visual identity: basketball orange on warm paper by day,
/// arena-at-night navy in dark mode.
abstract final class Brand {
  static const orange = Color(0xFFF26A1B);
  static const orangeDeep = Color(0xFFD4550C);
  static const orangeSoft = Color(0xFFFFE3D1);
  static const ink = Color(0xFF151827);
  static const inkSoft = Color(0xFF5C6072);
  static const paper = Color(0xFFF6F3EE);
  static const card = Color(0xFFFFFFFF);
  static const night = Color(0xFF0D0F17);
  static const nightCard = Color(0xFF171A25);
  static const nightCardHigh = Color(0xFF20242F);

  /// Scoreboard panel, the same in both themes.
  static const board = Color(0xFF0B0D14);
  static const led = Color(0xFFFF8A3D);

  static const display = 'BarlowCondensed';
  static const body = 'Barlow';

  /// Colours a coach can pick for a squad.
  static const squadColors = [
    Color(0xFFF26A1B), // orange
    Color(0xFF3D7BF7), // blue
    Color(0xFF1FA463), // green
    Color(0xFF8B5CF6), // purple
    Color(0xFFE5487F), // pink
    Color(0xFF0EA5A5), // teal
    Color(0xFFD99A0B), // gold
    Color(0xFF64748B), // slate
  ];

  static Color squadColor(int index) =>
      squadColors[index % squadColors.length];
}

extension HuddleContext on BuildContext {
  ThemeData get theme => Theme.of(this);
  ColorScheme get colors => Theme.of(this).colorScheme;
  TextTheme get text => Theme.of(this).textTheme;
  bool get isDark => Theme.of(this).brightness == Brightness.dark;

  Color statusColor(AttendanceStatus s) => statusColorFor(s, isDark);

  Color squadColor(Squad? squad) =>
      squad == null ? colors.outline : Brand.squadColor(squad.colorIndex);
}

Color statusColorFor(AttendanceStatus s, bool dark) => switch (s) {
  AttendanceStatus.present =>
    dark ? const Color(0xFF34C77B) : const Color(0xFF1C9A57),
  AttendanceStatus.late =>
    dark ? const Color(0xFFF5B83D) : const Color(0xFFE09304),
  AttendanceStatus.excused =>
    dark ? const Color(0xFF8197FF) : const Color(0xFF4F67E8),
  AttendanceStatus.absent =>
    dark ? const Color(0xFFFF6B6F) : const Color(0xFFDC4349),
};

IconData statusIcon(AttendanceStatus s) => switch (s) {
  AttendanceStatus.present => Icons.check_rounded,
  AttendanceStatus.late => Icons.schedule_rounded,
  AttendanceStatus.excused => Icons.shield_moon_outlined,
  AttendanceStatus.absent => Icons.close_rounded,
};

/// Colour for an attendance rate: green when healthy, amber, then red.
Color rateColor(double? rate, bool dark) {
  if (rate == null) return dark ? const Color(0xFF6B7080) : Brand.inkSoft;
  if (rate >= 0.85) return statusColorFor(AttendanceStatus.present, dark);
  if (rate >= 0.65) return statusColorFor(AttendanceStatus.late, dark);
  return statusColorFor(AttendanceStatus.absent, dark);
}

String formatRate(double? rate) =>
    rate == null ? '–' : '${(rate * 100).round()}%';

/// Soft, per-player avatar colours (stable for a given id).
({Color bg, Color fg}) avatarColors(String seed, bool dark) {
  var hash = 0;
  for (final unit in seed.codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  final hue = (hash % 12) * 30.0 + 8;
  if (dark) {
    return (
      bg: HSLColor.fromAHSL(1, hue, 0.32, 0.27).toColor(),
      fg: HSLColor.fromAHSL(1, hue, 0.85, 0.84).toColor(),
    );
  }
  return (
    bg: HSLColor.fromAHSL(1, hue, 0.70, 0.89).toColor(),
    fg: HSLColor.fromAHSL(1, hue, 0.55, 0.30).toColor(),
  );
}

ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final ink = dark ? const Color(0xFFF2F0EC) : Brand.ink;
  final inkSoft = dark ? const Color(0xFFA4A8B6) : Brand.inkSoft;
  final background = dark ? Brand.night : Brand.paper;
  final card = dark ? Brand.nightCard : Brand.card;
  final cardHigh = dark ? Brand.nightCardHigh : const Color(0xFFEFEBE4);
  final outline = dark ? const Color(0xFF2C303D) : const Color(0xFFE4DFD6);

  final scheme =
      ColorScheme.fromSeed(
        seedColor: Brand.orange,
        brightness: brightness,
      ).copyWith(
        primary: Brand.orange,
        onPrimary: Colors.white,
        primaryContainer: dark ? const Color(0xFF4A2410) : Brand.orangeSoft,
        onPrimaryContainer: dark ? const Color(0xFFFFD2B5) : const Color(0xFF6B2600),
        secondary: dark ? const Color(0xFFE9C893) : const Color(0xFF8A5A1F),
        surface: background,
        onSurface: ink,
        onSurfaceVariant: inkSoft,
        surfaceContainerLowest: card,
        surfaceContainerLow: card,
        surfaceContainer: card,
        surfaceContainerHigh: cardHigh,
        surfaceContainerHighest: cardHigh,
        outline: inkSoft.withValues(alpha: 0.6),
        outlineVariant: outline,
        error: statusColorFor(AttendanceStatus.absent, dark),
        inverseSurface: dark ? const Color(0xFFF2F0EC) : Brand.ink,
        onInverseSurface: dark ? Brand.ink : Colors.white,
      );

  TextStyle display(double size, [FontWeight weight = FontWeight.w800]) =>
      TextStyle(
        fontFamily: Brand.display,
        fontSize: size,
        fontWeight: weight,
        height: 1.05,
        color: ink,
        letterSpacing: 0.2,
      );

  final textTheme = TextTheme(
    displayLarge: display(64),
    displayMedium: display(48),
    displaySmall: display(38),
    headlineLarge: display(34),
    headlineMedium: display(28),
    headlineSmall: display(24, FontWeight.w700),
    titleLarge: TextStyle(
      fontFamily: Brand.body,
      fontSize: 20,
      fontWeight: FontWeight.w700,
      color: ink,
    ),
    titleMedium: TextStyle(
      fontFamily: Brand.body,
      fontSize: 17,
      fontWeight: FontWeight.w600,
      color: ink,
    ),
    titleSmall: TextStyle(
      fontFamily: Brand.body,
      fontSize: 15,
      fontWeight: FontWeight.w600,
      color: ink,
    ),
    bodyLarge: TextStyle(fontFamily: Brand.body, fontSize: 17, color: ink),
    bodyMedium: TextStyle(fontFamily: Brand.body, fontSize: 15, color: ink),
    bodySmall: TextStyle(fontFamily: Brand.body, fontSize: 13, color: inkSoft),
    labelLarge: const TextStyle(
      fontFamily: Brand.body,
      fontSize: 16,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.2,
    ),
    labelMedium: TextStyle(
      fontFamily: Brand.body,
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: inkSoft,
    ),
    labelSmall: TextStyle(
      fontFamily: Brand.display,
      fontSize: 12,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.2,
      color: inkSoft,
    ),
  );

  final rounded16 = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(16),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    fontFamily: Brand.body,
    textTheme: textTheme,
    scaffoldBackgroundColor: background,
    splashFactory: InkSparkle.splashFactory,
    visualDensity: VisualDensity.standard,
    appBarTheme: AppBarTheme(
      backgroundColor: background,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      elevation: 0,
      centerTitle: false,
      foregroundColor: ink,
      titleTextStyle: display(24, FontWeight.w800),
      systemOverlayStyle: dark
          ? SystemUiOverlayStyle.light.copyWith(
              statusBarColor: Colors.transparent,
            )
          : SystemUiOverlayStyle.dark.copyWith(
              statusBarColor: Colors.transparent,
            ),
    ),
    cardTheme: CardThemeData(
      color: card,
      elevation: 0,
      margin: EdgeInsets.zero,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: outline.withValues(alpha: dark ? 0.6 : 0.8)),
      ),
    ),
    dividerTheme: DividerThemeData(color: outline, thickness: 1, space: 1),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 54),
        shape: rounded16,
        textStyle: textTheme.labelLarge,
        backgroundColor: Brand.orange,
        foregroundColor: Colors.white,
        disabledBackgroundColor: cardHigh,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 54),
        shape: rounded16,
        foregroundColor: ink,
        side: BorderSide(color: outline, width: 1.5),
        textStyle: textTheme.labelLarge,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: dark ? const Color(0xFFFF9A5C) : Brand.orangeDeep,
        textStyle: textTheme.labelLarge,
        shape: rounded16,
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: Brand.orange,
      foregroundColor: Colors.white,
      elevation: 2,
      highlightElevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      extendedTextStyle: textTheme.labelLarge,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: card,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      height: 72,
      indicatorColor: dark ? const Color(0xFF4A2410) : Brand.orangeSoft,
      indicatorShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? (dark ? const Color(0xFFFF9A5C) : Brand.orangeDeep)
              : inkSoft,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontFamily: Brand.body,
          fontSize: 12.5,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w600,
          color: states.contains(WidgetState.selected) ? ink : inkSoft,
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: card,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      hintStyle: TextStyle(color: inkSoft.withValues(alpha: 0.8)),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: outline, width: 1.5),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: outline, width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Brand.orange, width: 2),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: card,
      selectedColor: dark ? const Color(0xFF4A2410) : Brand.orangeSoft,
      side: BorderSide(color: outline),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      labelStyle: TextStyle(
        fontFamily: Brand.body,
        fontWeight: FontWeight.w600,
        color: ink,
      ),
      showCheckmark: false,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        side: WidgetStatePropertyAll(BorderSide(color: outline)),
        textStyle: WidgetStatePropertyAll(
          textTheme.labelLarge?.copyWith(fontSize: 14),
        ),
        backgroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? (dark ? const Color(0xFF4A2410) : Brand.orangeSoft)
              : card,
        ),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: card,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: outline,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titleTextStyle: display(26, FontWeight.w800),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: dark ? const Color(0xFFF2F0EC) : Brand.ink,
      contentTextStyle: TextStyle(
        fontFamily: Brand.body,
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: dark ? Brand.ink : Colors.white,
      ),
      actionTextColor: dark ? Brand.orangeDeep : const Color(0xFFFF9A5C),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: inkSoft,
      titleTextStyle: textTheme.titleMedium,
      subtitleTextStyle: textTheme.bodySmall,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? Colors.white : null,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? Brand.orange : null,
      ),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: Brand.orange,
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      },
    ),
  );
}
