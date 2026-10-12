import 'package:flutter/material.dart';

/// Système visuel de Golden Bridge Pay : plat, noir et blanc, beaucoup d'air,
/// une seule couleur de marque (l'or) réservée à l'essentiel.
class AppColors {
  // Marque
  static const navy = Color(0xFF0A1F44);
  static const navyLight = Color(0xFF173A7A);
  static const gold = Color(0xFFF5B70A);
  static const goldDark = Color(0xFFC98A00);

  // Encres et surfaces (thème clair)
  static const ink = Color(0xFF0B0C10);
  static const muted = Color(0xFF6E7280);
  static const surface = Color(0xFFF3F4F6);
  static const outline = Color(0xFFE6E7EB);
  static const background = Colors.white;

  // Thème sombre
  static const night = Color(0xFF000000);
  static const nightSoft = Color(0xFF15161A);

  // Sémantique (utilisée avec parcimonie)
  static const green = Color(0xFF00A36C);
  static const red = Color(0xFFE5484D);
  static const amber = Color(0xFFD98E04);

  // Noms historiques : tous ramenés à l'encre pour des icônes monochromes.
  static const indigo = ink;
  static const violet = ink;
  static const teal = ink;
  static const sky = ink;

  /// Fond du bandeau de solde (seul dégradé de l'application).
  static const primaryGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF173A7A), navy],
  );

  static const nightGradient = primaryGradient;
  static const tealGradient = primaryGradient;
  static const sunsetGradient = primaryGradient;
  static const goldGradient = LinearGradient(colors: [gold, gold]);
}

class AppTheme {
  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final ink = isDark ? const Color(0xFFF5F5F7) : AppColors.ink;
    final muted = isDark ? const Color(0xFF9A9DA6) : AppColors.muted;
    final bg = isDark ? AppColors.night : AppColors.background;
    final card = isDark ? AppColors.nightSoft : AppColors.surface;
    final outline = isDark ? const Color(0xFF26272D) : AppColors.outline;

    final scheme = ColorScheme(
      brightness: brightness,
      primary: ink,
      onPrimary: bg,
      secondary: AppColors.gold,
      onSecondary: AppColors.navy,
      error: AppColors.red,
      onError: Colors.white,
      surface: bg,
      onSurface: ink,
      onSurfaceVariant: muted,
      surfaceContainerLowest: bg,
      surfaceContainerLow: card,
      surfaceContainer: card,
      surfaceContainerHigh: card,
      surfaceContainerHighest: card,
      outline: muted,
      outlineVariant: outline,
    );
    final pill = const StadiumBorder();
    final field = BorderRadius.circular(14);

    return ThemeData(
      useMaterial3: true,
      fontFamily: 'Inter',
      colorScheme: scheme,
      brightness: brightness,
      scaffoldBackgroundColor: bg,
      splashFactory: InkSparkle.splashFactory,
      textTheme: Typography.material2021(platform: TargetPlatform.android)
          .black
          .apply(fontFamily: 'Inter', bodyColor: ink, displayColor: ink),
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        foregroundColor: ink,
        titleTextStyle: TextStyle(
          fontFamily: 'Inter',
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: ink,
          letterSpacing: -0.2,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: card,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: card,
        labelStyle: TextStyle(color: muted),
        hintStyle: TextStyle(color: muted.withValues(alpha: 0.7)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(borderRadius: field, borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: field, borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: field, borderSide: BorderSide(color: ink, width: 1.2)),
        errorBorder: OutlineInputBorder(borderRadius: field, borderSide: const BorderSide(color: AppColors.red)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: ink,
          foregroundColor: bg,
          disabledBackgroundColor: card,
          disabledForegroundColor: muted,
          minimumSize: const Size.fromHeight(54),
          shape: pill,
          elevation: 0,
          textStyle: const TextStyle(fontFamily: 'Inter', fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ink,
          minimumSize: const Size.fromHeight(54),
          shape: pill,
          side: BorderSide(color: outline),
          textStyle: const TextStyle(fontFamily: 'Inter', fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: isDark ? AppColors.gold : AppColors.navyLight,
          textStyle: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 64,
        elevation: 0,
        backgroundColor: bg,
        surfaceTintColor: Colors.transparent,
        indicatorColor: Colors.transparent,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(color: s.contains(WidgetState.selected) ? ink : muted, size: 24),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => TextStyle(
            fontFamily: 'Inter',
            fontSize: 11,
            fontWeight: s.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w500,
            color: s.contains(WidgetState.selected) ? ink : muted,
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: pill,
        side: BorderSide.none,
        backgroundColor: card,
        selectedColor: ink,
        labelStyle: TextStyle(fontFamily: 'Inter', color: ink, fontWeight: FontWeight.w500),
        secondaryLabelStyle: TextStyle(fontFamily: 'Inter', color: bg, fontWeight: FontWeight.w600),
        checkmarkColor: bg,
        showCheckmark: false,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          selectedBackgroundColor: ink,
          selectedForegroundColor: bg,
          side: BorderSide(color: outline),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: ink,
        contentTextStyle: TextStyle(fontFamily: 'Inter', color: bg),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: bg,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      ),
      dialogTheme: DialogThemeData(backgroundColor: bg, surfaceTintColor: Colors.transparent),
      listTileTheme: ListTileThemeData(iconColor: ink, contentPadding: const EdgeInsets.symmetric(horizontal: 16)),
      dividerTheme: DividerThemeData(color: outline, space: 1, thickness: 1),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: ink, linearTrackColor: card),
      sliderTheme: SliderThemeData(activeTrackColor: ink, thumbColor: ink, inactiveTrackColor: outline),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? bg : muted),
        trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? AppColors.green : outline),
      ),
    );
  }
}
