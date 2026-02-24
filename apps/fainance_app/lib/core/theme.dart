import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ── Farb-Palette ───────────────────────────────────────────────────────────────
// Inspiriert von Next.js / Vercel Design System.
// Alle Farben an einem Ort — niemals hardcoded im UI-Code.
class AppColors {
  AppColors._(); // privater Konstruktor: diese Klasse soll nie instanziiert werden

  // Hintergründe
  static const background = Color(0xFF0A0A0A);      // fast schwarz
  static const surface = Color(0xFF111111);          // Cards, Sheets
  static const surfaceElevated = Color(0xFF1A1A1A);  // elevated Cards
  static const border = Color(0xFF262626);           // subtile Trennlinien

  // Akzentfarben
  static const primary = Color(0xFFFFFFFF);          // weiß für Headlines
  static const secondary = Color(0xFF888888);        // grau für Subtexte
  static const accent = Color(0xFF3B82F6);           // blau für CTAs

  // Semantische Farben (für Charts und Status)
  static const income = Color(0xFF22C55E);           // grün für Einnahmen
  static const expense = Color(0xFFEF4444);          // rot für Ausgaben
  static const warning = Color(0xFFF59E0B);          // gelb für Warnungen
  static const positive = Color(0xFF22C55E);         // grün für positives Feedback

  // Chart-Farben — genug für alle Kategorien, harmonisch abgestimmt
  static const chartColors = [
    Color(0xFF3B82F6), // blau
    Color(0xFF8B5CF6), // lila
    Color(0xFF06B6D4), // cyan
    Color(0xFF10B981), // emerald
    Color(0xFFF59E0B), // amber
    Color(0xFFEF4444), // rot
    Color(0xFFEC4899), // pink
    Color(0xFF84CC16), // lime
    Color(0xFFF97316), // orange
    Color(0xFF6366F1), // indigo
    Color(0xFF14B8A6), // teal
    Color(0xFFA855F7), // violet
  ];
}

// ── Theme ──────────────────────────────────────────────────────────────────────
class AppTheme {
  AppTheme._();

  static ThemeData get dark {
    // Inter ist DIE Schrift des modernen Webs (verwendet von Vercel, Linear, etc.)
    final textTheme = GoogleFonts.interTextTheme(ThemeData.dark().textTheme);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: const ColorScheme.dark(
        background: AppColors.background,
        surface: AppColors.surface,
        primary: AppColors.accent,
        onPrimary: AppColors.primary,
        onSurface: AppColors.primary,
        outline: AppColors.border,
      ),
      textTheme: textTheme.copyWith(
        // Display: große Headlines
        displayLarge: textTheme.displayLarge?.copyWith(
          color: AppColors.primary,
          fontWeight: FontWeight.w700,
          letterSpacing: -1.5,
        ),
        // Headlines für Screen-Titel
        headlineMedium: textTheme.headlineMedium?.copyWith(
          color: AppColors.primary,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.5,
        ),
        // Body Text
        bodyLarge: textTheme.bodyLarge?.copyWith(
          color: AppColors.primary,
          fontSize: 15,
        ),
        bodyMedium: textTheme.bodyMedium?.copyWith(
          color: AppColors.secondary,
          fontSize: 13,
        ),
        // Labels (Buttons, Chips, etc.)
        labelLarge: textTheme.labelLarge?.copyWith(
          color: AppColors.primary,
          fontWeight: FontWeight.w500,
          letterSpacing: 0,
        ),
      ),

      // Cards
      cardTheme: CardTheme(
        color: AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.border, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),

      // AppBar
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.inter(
          color: AppColors.primary,
          fontSize: 16,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.3,
        ),
        iconTheme: const IconThemeData(color: AppColors.secondary),
        // Subtile Border-Linie unter der AppBar
        shape: const Border(
          bottom: BorderSide(color: AppColors.border, width: 1),
        ),
      ),

      // Buttons
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.background,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          textStyle: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.border),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),

      // BottomNavigationBar
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.surface,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.secondary,
        elevation: 0,
        type: BottomNavigationBarType.fixed,
      ),

      // Divider
      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
        space: 1,
      ),

      // Input Fields (für spätere Suche/Filter)
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.accent),
        ),
        hintStyle: const TextStyle(color: AppColors.secondary),
      ),
    );
  }
}