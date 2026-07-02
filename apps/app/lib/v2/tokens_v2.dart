import 'package:flutter/material.dart';

/// v2 palette — exact sRGB conversions of the prototype's oklch values
/// (Read the World v2.dc.html is pixel-authoritative; see
/// docs/v2-implementation-spec.md §1b). Comments keep the source oklch.
class RtwV2Colors {
  // Base surfaces (unchanged from v1 brand).
  static const paper = Color(0xFFF3F0E9);
  static const paperAlt = Color(0xFFEDE9E0);
  static const card = Color(0xFFFBFAF6);
  static const ink = Color(0xFF211F1A);
  static const inkSoft = Color(0xFF23211C);
  static const border = Color(0xFFE4DFD4);
  static const borderStrong = Color(0xFFE0DACE);
  static const subText = Color(0xFF6E6A60);
  static const muted = Color(0xFF8A8475);
  static const faint = Color(0xFFA89F8C);
  static const navIdle = Color(0xFFB3AD9F);
  static const hairline = Color(0xFFEFEAE0);
  static const knobTrackOff = Color(0xFFD8D2C5);

  // Accents.
  static const blue = Color(0xFF3B649B); // oklch(0.50 0.10 256)
  static const clay = Color(0xFFA35D38); // oklch(0.55 0.105 47)
  static const green = Color(0xFF416F52); // oklch(0.50 0.07 155)
  static const purple = Color(0xFF7F5BB6); // oklch(0.55 0.14 300)
  static const teal = Color(0xFF007C84); // oklch(0.52 0.12 200)
  static const inkColorOption = Color(0xFF3A372F);
  static const worldInk = Color(0xFF194781); // oklch(0.40 0.11 256)
  static const danger = Color(0xFFB0432F); // oklch(0.55 0.155 25)

  // Text-on-tint deep shades.
  static const blueTextDeep = Color(0xFF2A4E7D); // oklch(0.42 0.09 256)
  static const clayTextDeep = Color(0xFF8C482F); // oklch(0.48 0.10 40)

  // Score deltas.
  static const deltaUp = Color(0xFF6FB880); // oklch(0.72 0.11 150)
  static const deltaDown = Color(0xFFDB7A58); // oklch(0.68 0.13 40)
  static const deltaUpBright = Color(0xFF76CF8A); // oklch(0.78 0.13 150), on ink
  static const deltaDownBright = Color(0xFFF48A64); // oklch(0.74 0.14 40), on ink

  // On-dark accents (world hero, reveal screen).
  static const onDarkBlue = Color(0xFF8DBAF7); // oklch(0.78 0.10 256)
  static const onDarkPaper = Color(0xFFEFEBE2);
  static const gradBlue = Color(0xFF3972BC); // oklch(0.55 0.13 256)
  static const gradBlueLight = Color(0xFF6BA0E8); // oklch(0.70 0.12 256)

  // Edge meter fills.
  static const meterBlue = Color(0xFF4973AB); // oklch(0.55 0.10 256)
  static const meterClay = Color(0xFFA55B35); // oklch(0.55 0.11 47)

  // Party player badges (prototype PLAYER_COLORS order).
  static const playerColors = <Color>[
    blue,
    clay,
    green,
    inkColorOption,
    purple,
    teal,
    Color(0xFF60892C), // oklch(0.58 0.13 130)
    Color(0xFFB9454C), // oklch(0.55 0.15 20)
  ];

  /// Room colors — server stores the prototype's oklch strings verbatim;
  /// this maps them for rendering. Order matches ROOM_COLOR_OPTIONS.
  static const roomColorByToken = <String, Color>{
    'oklch(0.50 0.07 155)': green,
    'oklch(0.55 0.105 47)': clay,
    'oklch(0.50 0.10 256)': blue,
    'oklch(0.55 0.14 300)': purple,
    'oklch(0.52 0.12 200)': teal,
    '#3A372F': inkColorOption,
  };

  static Color roomColor(String? token) =>
      roomColorByToken[token ?? ''] ?? blue;

  /// Tint helper mirroring the prototype's `oklch(... / 0.10)` fills.
  static Color tint(Color color, double opacity) =>
      color.withValues(alpha: opacity);
}

/// Motion constants lifted verbatim from the prototype (spec §1b).
class RtwV2Motion {
  static const revealFill = Duration(milliseconds: 1100);
  static const roomReveal = Duration(milliseconds: 1500);
  static const partyReveal = Duration(milliseconds: 1000);
  static const cardFling = Duration(milliseconds: 280);
  static const cardSettle = Duration(milliseconds: 320);
  static const pageFade = Duration(milliseconds: 500);
  static const flingDistance = 380.0;
  static const dragClamp = 170.0;
  static const commitThreshold = 66.0;
  static const borderTintThreshold = 28.0;
  static const zoneOpacityRamp = 110.0;
  static const tiltFactor = 0.04;
}
