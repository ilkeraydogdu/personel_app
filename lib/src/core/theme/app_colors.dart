import 'package:flutter/material.dart';

class AppColors {
  // Backgrounds
  static const Color background = Color(0xFF0B0F19);
  static const Color surface = Color(0xFF161F30);
  static const Color surfaceDark = Color(0xFF090B11);
  
  // Primary & Accents
  static const Color primary = Color(0xFF6366F1); // Indigo 500
  static const Color secondary = Color(0xFF3B82F6); // Blue 500
  static const Color accent = Color(0xFF06B6D4); // Cyan 500
  
  // Status Colors
  static const Color success = Color(0xFF10B981); // Emerald 500
  static const Color warning = Color(0xFFF59E0B); // Amber 500
  static const Color error = Color(0xFFEF4444); // Red 500
  
  // Text Colors
  static const Color textPrimary = Color(0xFFF8FAFC); // Slate 50
  static const Color textSecondary = Color(0xFF94A3B8); // Slate 400
  
  // Borders & Dividers
  static const Color border = Color(0x1AFFFFFF); // White 10%
  static const Color divider = Color(0x0DFFFFFF); // White 5%
  
  // Light Mode Colors
  static const Color lightBackground = Color(0xFFF8FAFC); // Slate 50
  static const Color lightSurface = Color(0xFFFFFFFF); // White
  static const Color lightSurfaceSecondary = Color(0xFFF1F5F9); // Slate 100
  static const Color lightTextPrimary = Color(0xFF0F172A); // Slate 900
  static const Color lightTextSecondary = Color(0xFF64748B); // Slate 500
  static const Color lightBorder = Color(0xFFE2E8F0); // Slate 200

  // Gradients
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primary, secondary],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Dynamic Theme-Aware Helpers
  static Color getScaffoldBg(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? const Color(0xFF0D1117) : lightBackground;

  static Color getCardBg(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? const Color(0xFF161B22) : lightSurface;

  static Color getCardBorder(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? const Color(0xFF21262D) : lightBorder;

  static Color getTextPrimary(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? Colors.white : lightTextPrimary;

  static Color getTextSecondary(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? Colors.white54 : lightTextSecondary;

  static Color getInnerInputBg(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? const Color(0xFF0D1117) : lightSurfaceSecondary;
}
