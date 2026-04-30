import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

class AppTheme {
  static const Color primary = Color(0xFF4F46E5);
  static const Color primaryDark = Color(0xFF3730A3);
  static const Color primaryLight = Color(0xFF818CF8);
  static const Color secondary = Color(0xFF06B6D4);
  static const Color accent = Color(0xFFF59E0B);
  static const Color success = Color(0xFF10B981);
  static const Color warning = Color(0xFFF59E0B);
  static const Color danger = Color(0xFFEF4444);
  static const Color surface = Color(0xFFF8FAFC);
  static const Color cardBg = Color(0xFFFFFFFF);
  static const Color textPrimary = Color(0xFF1E293B);
  static const Color textSecondary = Color(0xFF64748B);
  static const Color textLight = Color(0xFF94A3B8);
  static const Color divider = Color(0xFFE2E8F0);

  static const List<Color> gradientColors = [
    Color(0xFF4F46E5),
    Color(0xFF7C3AED),
    Color(0xFF06B6D4),
  ];

  static const List<Color> curveColors = [
    Color(0xFF4F46E5),
    Color(0xFF6366F1),
    Color(0xFF818CF8),
  ];

  static ThemeData get lightTheme => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.light,
    ).copyWith(primary: primary, secondary: secondary, surface: surface),
    fontFamily: 'SF Pro Display',
    iconTheme: const IconThemeData(
      size: 24,
      fill: 0,
      weight: 400,
      grade: 0,
      opticalSize: 24,
      color: Color(0xFF1E293B),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      iconTheme: IconThemeData(color: Colors.white),
      titleTextStyle: TextStyle(
        color: Colors.white,
        fontSize: 20,
        fontWeight: FontWeight.w700,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: divider),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: divider),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: primary, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    cardTheme: CardThemeData(
      color: cardBg,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: divider),
      ),
    ),
    scaffoldBackgroundColor: surface,
  );

  // Responsive font size helpers for WebView optimization
  static double getResponsiveFontSize(
    double mobileSize, {
    double webScale = 0.85,
  }) {
    return kIsWeb ? mobileSize * webScale : mobileSize;
  }

  static TextStyle getResponsiveTextStyle({
    required double fontSize,
    FontWeight? fontWeight,
    Color? color,
    double webScale = 0.85,
  }) {
    return TextStyle(
      fontSize: getResponsiveFontSize(fontSize, webScale: webScale),
      fontWeight: fontWeight,
      color: color,
    );
  }

  // Pre-defined responsive text styles
  static TextStyle get responsiveHeadline1 => getResponsiveTextStyle(
    fontSize: 32,
    fontWeight: FontWeight.bold,
    color: textPrimary,
  );

  static TextStyle get responsiveHeadline2 => getResponsiveTextStyle(
    fontSize: 24,
    fontWeight: FontWeight.bold,
    color: textPrimary,
  );

  static TextStyle get responsiveHeadline3 => getResponsiveTextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w700,
    color: textPrimary,
  );

  static TextStyle get responsiveHeadline4 => getResponsiveTextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: textPrimary,
  );

  static TextStyle get responsiveHeadline5 => getResponsiveTextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: textPrimary,
  );

  static TextStyle get responsiveHeadline6 => getResponsiveTextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: textPrimary,
  );

  static TextStyle get responsiveBodyLarge => getResponsiveTextStyle(
    fontSize: 16,
    fontWeight: FontWeight.normal,
    color: textPrimary,
  );

  static TextStyle get responsiveBodyMedium => getResponsiveTextStyle(
    fontSize: 14,
    fontWeight: FontWeight.normal,
    color: textPrimary,
  );

  static TextStyle get responsiveBodySmall => getResponsiveTextStyle(
    fontSize: 12,
    fontWeight: FontWeight.normal,
    color: textSecondary,
  );

  static TextStyle get responsiveLabelLarge => getResponsiveTextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: textPrimary,
  );

  static TextStyle get responsiveLabelMedium => getResponsiveTextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: textSecondary,
  );

  static TextStyle get responsiveLabelSmall => getResponsiveTextStyle(
    fontSize: 10,
    fontWeight: FontWeight.w500,
    color: textSecondary,
  );

  // Card-specific responsive styles
  static TextStyle get responsiveCardTitle => getResponsiveTextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w700,
    color: textPrimary,
  );

  static TextStyle get responsiveCardSubtitle => getResponsiveTextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: textSecondary,
  );

  static TextStyle get responsiveCardCaption => getResponsiveTextStyle(
    fontSize: 10,
    fontWeight: FontWeight.w400,
    color: textLight,
  );
}
