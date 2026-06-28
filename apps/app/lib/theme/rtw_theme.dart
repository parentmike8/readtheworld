import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'tokens.dart';

ThemeData buildRtwTheme() {
  final base = ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: RtwColors.paper,
    colorScheme: ColorScheme.fromSeed(
      seedColor: RtwColors.blue,
      brightness: Brightness.light,
      surface: RtwColors.card,
    ),
  );

  return base.copyWith(
    textTheme: GoogleFonts.hankenGroteskTextTheme(base.textTheme).copyWith(
      displayLarge: GoogleFonts.newsreader(
        fontSize: 58,
        height: 1.02,
        fontWeight: FontWeight.w500,
        color: RtwColors.ink,
      ),
      headlineLarge: GoogleFonts.newsreader(
        fontSize: 38,
        height: 1.08,
        fontWeight: FontWeight.w500,
        color: RtwColors.ink,
      ),
      headlineMedium: GoogleFonts.newsreader(
        fontSize: 30,
        height: 1.12,
        fontWeight: FontWeight.w500,
        color: RtwColors.ink,
      ),
      titleLarge: GoogleFonts.newsreader(
        fontSize: 24,
        height: 1.18,
        fontWeight: FontWeight.w500,
        color: RtwColors.ink,
      ),
      bodyLarge: GoogleFonts.hankenGrotesk(
        fontSize: 17,
        height: 1.5,
        color: RtwColors.subText,
      ),
      bodyMedium: GoogleFonts.hankenGrotesk(
        fontSize: 15,
        height: 1.45,
        color: RtwColors.subText,
      ),
      labelSmall: GoogleFonts.ibmPlexMono(
        fontSize: 11,
        height: 1.2,
        letterSpacing: 1.3,
        color: RtwColors.muted,
      ),
    ),
    dividerColor: RtwColors.border,
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: RtwColors.card,
      hintStyle: GoogleFonts.hankenGrotesk(
        color: RtwColors.faint,
        fontSize: 16,
        fontWeight: FontWeight.w500,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(RtwRadii.input),
        borderSide: const BorderSide(color: RtwColors.borderStrong),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(RtwRadii.input),
        borderSide: const BorderSide(color: RtwColors.borderStrong),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(RtwRadii.input),
        borderSide: const BorderSide(color: RtwColors.blue, width: 1.5),
      ),
    ),
  );
}
