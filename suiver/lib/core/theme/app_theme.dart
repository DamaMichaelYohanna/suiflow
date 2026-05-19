import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // ─────────────────────────────────────────────────────────────────
  // DARK THEME (primary)
  // ─────────────────────────────────────────────────────────────────
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xFF0A0A0F),
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFF00E676),   // Neon Green
        secondary: Color(0xFF00B0FF), // Cyber Blue
        surface: Color(0xFF16161E),
        error: Color(0xFFFF3D00),
        onSurface: Colors.white,
        onPrimary: Colors.black,
        onSecondary: Colors.black,
      ),
      textTheme: GoogleFonts.outfitTextTheme(ThemeData.dark().textTheme).copyWith(
        displayLarge:  GoogleFonts.outfit(fontWeight: FontWeight.bold, color: Colors.white),
        headlineMedium: GoogleFonts.outfit(fontWeight: FontWeight.w700, color: Colors.white),
        titleLarge:    GoogleFonts.outfit(fontWeight: FontWeight.w600, color: Colors.white),
        bodyLarge:     GoogleFonts.outfit(color: Colors.white70),
        bodyMedium:    GoogleFonts.outfit(color: Colors.white60),
      ),
      // ── Buttons ────────────────────────────────────────────────────
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF00E676),
          foregroundColor: Colors.black,
          elevation: 8,
          shadowColor: const Color(0xFF00E676).withOpacity(0.4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          padding: const EdgeInsets.symmetric(vertical: 18),
          textStyle: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ),
      // ── Input Fields ────────────────────────────────────────────────
      // Key fix: fillColor is a clearly visible dark card tone, NOT near-transparent.
      // hintStyle, labelStyle, prefixIconColor are all explicitly set so they
      // contrast correctly against the fill.
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF1E1E2A),       // visible dark-card fill
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFF2E2E40), width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFF00E676), width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFFF3D00), width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFFF3D00), width: 2),
        ),
        // ── Text visibility fixes ──────────────────────────────────────
        hintStyle:       const TextStyle(color: Color(0xFF666680), fontSize: 16),
        labelStyle:      const TextStyle(color: Color(0xFF9090AA)),
        prefixIconColor: const Color(0xFF8888A8),
        suffixIconColor: const Color(0xFF8888A8),
      ),
      // ── Cards ──────────────────────────────────────────────────────
      cardTheme: CardThemeData(
        color: const Color(0xFF16161E),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: Color(0xFF2A2A3C)),
        ),
      ),
      // ── AppBar ─────────────────────────────────────────────────────
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
        titleTextStyle: GoogleFonts.outfit(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────
  // LIGHT THEME (fallback)
  // ─────────────────────────────────────────────────────────────────
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xFFF0F2F8),
      colorScheme: const ColorScheme.light(
        primary: Color(0xFF00C853),
        secondary: Color(0xFF2962FF),
        surface: Colors.white,
        onSurface: Color(0xFF0D0D1A),
        onPrimary: Colors.white,
        onSecondary: Colors.white,
      ),
      textTheme: GoogleFonts.outfitTextTheme(ThemeData.light().textTheme).copyWith(
        displayLarge:   GoogleFonts.outfit(fontWeight: FontWeight.bold, color: const Color(0xFF0D0D1A)),
        headlineMedium: GoogleFonts.outfit(fontWeight: FontWeight.w700, color: const Color(0xFF0D0D1A)),
        titleLarge:     GoogleFonts.outfit(fontWeight: FontWeight.w600, color: const Color(0xFF0D0D1A)),
        bodyLarge:      GoogleFonts.outfit(color: const Color(0xFF1A1A2E)),
        bodyMedium:     GoogleFonts.outfit(color: const Color(0xFF44445A)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF00C853),
          foregroundColor: Colors.white,
          elevation: 4,
          shadowColor: const Color(0xFF00C853).withOpacity(0.3),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          padding: const EdgeInsets.symmetric(vertical: 18),
          textStyle: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.grey.shade200, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFF00C853), width: 2),
        ),
        hintStyle:       TextStyle(color: Colors.grey.shade400, fontSize: 16),
        labelStyle:      const TextStyle(color: Color(0xFF44445A)),
        prefixIconColor: const Color(0xFF44445A),
        suffixIconColor: const Color(0xFF44445A),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 4,
        shadowColor: Colors.black.withOpacity(0.08),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Color(0xFF0D0D1A)),
        titleTextStyle: GoogleFonts.outfit(
          color: const Color(0xFF0D0D1A),
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
