import 'package:flutter/material.dart';

/// Design tokens for FileTrack Hub.
///
/// The old interface leaned on large saturated gradient blocks. This system
/// inverts that: neutral surfaces carry the layout, and colour appears only in
/// small accents (a folder's icon chip, a status dot). That keeps dense
/// document lists readable and scales cleanly from phone to desktop.
class AppTheme {
  AppTheme._();

  // ---------------------------------------------------------------- surfaces
  /// Page background — a barely-there warm grey so white cards lift off it.
  static const Color canvas = Color(0xFFF7F8FA);
  static const Color surface = Colors.white;

  /// Hairline borders do the separating; shadows stay almost invisible.
  static const Color border = Color(0xFFE6E8EC);
  static const Color borderStrong = Color(0xFFD5D9E0);

  // -------------------------------------------------------------------- text
  static const Color textPrimary = Color(0xFF1A1D21);
  static const Color textSecondary = Color(0xFF5F6672);
  static const Color textMuted = Color(0xFF9AA1AD);

  // ------------------------------------------------------------------ accent
  /// Single brand accent. Used for primary actions and active state only.
  static const Color accent = Color(0xFF2F6FED);
  static const Color accentSoft = Color(0xFFEAF1FE);

  // ------------------------------------------------------------- status hues
  static const Color danger = Color(0xFFDC2626);
  static const Color dangerSoft = Color(0xFFFEECEC);
  static const Color warning = Color(0xFFD97706);
  static const Color warningSoft = Color(0xFFFEF3E2);
  static const Color success = Color(0xFF059669);
  static const Color successSoft = Color(0xFFE7F6F1);

  // ------------------------------------------------------- folder accents
  /// Muted, evenly-weighted hues for folder icon chips. Deliberately low
  /// saturation so eight of them on one screen never compete with each other.
  static const Color folderAmber = Color(0xFFE08A28);
  static const Color folderBlue = Color(0xFF2F6FED);
  static const Color folderIndigo = Color(0xFF5A5FD4);
  static const Color folderViolet = Color(0xFF8B5CF6);
  static const Color folderTeal = Color(0xFF0D9488);
  static const Color folderGreen = Color(0xFF16A34A);
  static const Color folderPink = Color(0xFFDB2777);
  static const Color folderSlate = Color(0xFF64748B);

  /// 12% tint of a folder accent, for the icon chip background.
  static Color soften(Color c) => Color.alphaBlend(c.withValues(alpha: 0.12), surface);

  // ------------------------------------------------------------------ shape
  static const double radiusSm = 8;
  static const double radius = 12;
  static const double radiusLg = 16;

  static BorderRadius get brSm => BorderRadius.circular(radiusSm);
  static BorderRadius get br => BorderRadius.circular(radius);
  static BorderRadius get brLg => BorderRadius.circular(radiusLg);

  /// Standard card: white, hairline border, no drop shadow.
  static BoxDecoration card({Color? background, BorderRadius? radius}) =>
      BoxDecoration(
        color: background ?? surface,
        borderRadius: radius ?? brLg,
        border: Border.all(color: border, width: 1),
      );

  // ---------------------------------------------------------------- spacing
  static const double gapXs = 4;
  static const double gapSm = 8;
  static const double gap = 12;
  static const double gapLg = 16;
  static const double gapXl = 24;

  // ------------------------------------------------------------ breakpoints
  /// Content is centred and capped on wide screens so a desktop browser
  /// doesn't stretch rows to an unreadable width.
  static const double maxContentWidth = 1180;

  /// Column count for the folder grid at a given available width.
  static int gridColumns(double width) {
    if (width >= 1100) return 4;
    if (width >= 820) return 3;
    if (width >= 520) return 2;
    return 1;
  }

  // ----------------------------------------------------------------- theme
  static ThemeData build() {
    final base = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: Brightness.light,
    ).copyWith(
      surface: surface,
      primary: accent,
      error: danger,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: base,
      scaffoldBackgroundColor: canvas,
      dividerColor: border,
      splashFactory: InkSparkle.splashFactory,

      textTheme: const TextTheme(
        headlineSmall: TextStyle(
            fontSize: 22, fontWeight: FontWeight.w700, color: textPrimary),
        titleLarge: TextStyle(
            fontSize: 18, fontWeight: FontWeight.w700, color: textPrimary),
        titleMedium: TextStyle(
            fontSize: 15, fontWeight: FontWeight.w600, color: textPrimary),
        titleSmall: TextStyle(
            fontSize: 13, fontWeight: FontWeight.w600, color: textPrimary),
        bodyLarge: TextStyle(fontSize: 15, color: textPrimary, height: 1.45),
        bodyMedium: TextStyle(fontSize: 13.5, color: textPrimary, height: 1.45),
        bodySmall: TextStyle(fontSize: 12, color: textSecondary, height: 1.4),
        labelLarge: TextStyle(
            fontSize: 13, fontWeight: FontWeight.w600, color: textPrimary),
        labelMedium: TextStyle(fontSize: 12, color: textSecondary),
        labelSmall: TextStyle(fontSize: 11, color: textMuted),
      ),

      appBarTheme: const AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: surface,
        foregroundColor: textPrimary,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
            fontSize: 16, fontWeight: FontWeight.w700, color: textPrimary),
        iconTheme: IconThemeData(color: textSecondary),
      ),

      cardTheme: CardThemeData(
        elevation: 0,
        color: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
          side: const BorderSide(color: border),
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: accent,
          foregroundColor: Colors.white,
          disabledBackgroundColor: const Color(0xFFE9ECF1),
          disabledForegroundColor: textMuted,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radius)),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accent,
          textStyle:
              const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radiusSm)),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textPrimary,
          side: const BorderSide(color: borderStrong),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radius)),
        ),
      ),

      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        elevation: 2,
        backgroundColor: accent,
        foregroundColor: Colors.white,
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: canvas,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        hintStyle: const TextStyle(color: textMuted, fontSize: 13),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: const BorderSide(color: accent, width: 1.5),
        ),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: canvas,
        side: const BorderSide(color: border),
        labelStyle: const TextStyle(fontSize: 12, color: textSecondary),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusSm)),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusLg)),
        titleTextStyle: const TextStyle(
            fontSize: 16, fontWeight: FontWeight.w700, color: textPrimary),
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: textPrimary,
        contentTextStyle: const TextStyle(fontSize: 13, color: Colors.white),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
      ),

      listTileTheme: const ListTileThemeData(
        iconColor: textSecondary,
        textColor: textPrimary,
      ),

      expansionTileTheme: const ExpansionTileThemeData(
        iconColor: textSecondary,
        collapsedIconColor: textMuted,
        textColor: textPrimary,
        collapsedTextColor: textPrimary,
        shape: Border(),
        collapsedShape: Border(),
      ),
    );
  }
}
