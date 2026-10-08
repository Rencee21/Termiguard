import 'package:flutter/material.dart';

/// Colors ported 1:1 from the original `assets/css/style.css`
/// `:root { --primary-color: ... }` variable block, so the Flutter
/// app keeps the same brand identity as the PHP site.
class AppColors {
  AppColors._();

  static const primary = Color(0xFF1B4332);
  static const primaryDark = Color(0xFF123024);
  static const primaryLight = Color(0xFF2D6A4F);
  static const secondary = Color(0xFF40916C);
  static const secondaryDark = Color(0xFF2D6A4F);
  static const accent = Color(0xFF8A5A34);
  static const accentDark = Color(0xFF6F4527);

  static const background = Color(0xFFF6F7F3);
  static const card = Color(0xFFFFFFFF);
  static const border = Color(0xFFE1E4DC);
  static const borderStrong = Color(0xFFCBD0C4);

  static const text = Color(0xFF2B2F2B);
  static const mutedText = Color(0xFF6B7268);
  static const heading = Color(0xFF17251D);
  static const textOnPrimary = Color(0xFFFFFFFF);

  static const success = Color(0xFF2D8A4E);
  static const successBg = Color(0xFFE7F5EC);
  static const successBorder = Color(0xFFB7E2C5);

  static const warning = Color(0xFFB7791F);
  static const warningBg = Color(0xFFFDF3DD);
  static const warningBorder = Color(0xFFF2D896);

  static const danger = Color(0xFFC0392B);
  static const dangerBg = Color(0xFFFBE9E7);
  static const dangerBorder = Color(0xFFF0BCB4);

  static const info = Color(0xFF2563A8);
  static const infoBg = Color(0xFFE8F1FB);
  static const infoBorder = Color(0xFFB8D5F0);

  static const neutral = Color(0xFF6B7268);
  static const neutralBg = Color(0xFFEEF0EA);
  static const neutralBorder = Color(0xFFD8DBD1);
}

class AppTheme {
  AppTheme._();

  static ThemeData get light {
    final base = ThemeData.light(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: base.colorScheme.copyWith(
        primary: AppColors.primary,
        secondary: AppColors.secondary,
        surface: AppColors.card,
        error: AppColors.danger,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.textOnPrimary,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: AppColors.textOnPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),
      textTheme: base.textTheme.apply(
        bodyColor: AppColors.text,
        displayColor: AppColors.heading,
      ),
      cardTheme: CardThemeData(
        color: AppColors.card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.border),
        ),
        margin: EdgeInsets.zero,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.textOnPrimary,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.borderStrong),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.card,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.mutedText,
        showUnselectedLabels: true,
        type: BottomNavigationBarType.fixed,
      ),
      dividerColor: AppColors.border,
    );
  }
}
