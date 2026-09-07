import 'package:flutter/material.dart';

/// Café & bakery design tokens.
///
/// The palette is espresso + warm cream with caramel and sage accents,
/// balanced roughly 70% cream/white, 20% espresso, 10% caramel/sage.
///
/// Historic token names (`green`, `amber`, `orange`, ...) are kept so the
/// ~1,200 existing call sites keep compiling; only their *values* moved to the
/// café palette. New code should prefer the semantic aliases at the bottom
/// (`espresso`, `cream`, `caramel`, `sage`, `success`, ...).
class AppColors {
  // ---------------------------------------------------------------------
  // Brand / primary — espresso
  // ---------------------------------------------------------------------

  /// Primary brand colour. Espresso brown.
  static const green = Color(0xFF4B2E24);

  /// Deepest espresso — price emphasis, gradient anchor, pressed states.
  static const darkGreen = Color(0xFF35201A);

  /// Soft caramel-tinted cream — selected tabs, tinted panels, chips.
  static const lightGreen = Color(0xFFF4E9DD);

  /// Border that pairs with [lightGreen].
  static const greenBorder = Color(0xFFE7D5C2);

  // ---------------------------------------------------------------------
  // Accents — caramel & sage
  // ---------------------------------------------------------------------

  /// Caramel. Secondary accent: highlights, deal badges, warning fills.
  static const amber = Color(0xFFC58B5A);

  /// Deep caramel. Warning text/fills that need readable contrast.
  static const orange = Color(0xFF9A5A28);

  /// Muted denim — informational only, deliberately desaturated.
  static const blue = Color(0xFF4E6E8E);

  // ---------------------------------------------------------------------
  // Neutrals — cream & warm greys
  // ---------------------------------------------------------------------

  /// App background. Warm cream.
  static const page = Color(0xFFFAF6EF);

  /// Cards, sheets, dialogs.
  static const surface = Color(0xFFFFFFFF);

  /// Subtle inset surfaces — total panels, table headers, fields.
  static const softSurface = Color(0xFFFCF8F2);

  /// Hairline borders and dividers.
  static const border = Color(0xFFEBE1D5);

  /// Primary text.
  static const text = Color(0xFF332A26);

  /// Secondary text. Darkened from the palette's #8D8179 so body copy clears
  /// 4.5:1 on cream; use [mutedSoft] for hints and placeholders.
  static const muted = Color(0xFF7A6E66);

  /// Palette muted tone — placeholders, disabled text, decorative labels.
  static const mutedSoft = Color(0xFF8D8179);

  /// Warm brick red — errors, refunds, destructive actions.
  static const danger = Color(0xFFC0453F);

  static const primaryGradient = LinearGradient(
    colors: [darkGreen, green],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  // ---------------------------------------------------------------------
  // Sidebar / navigation — deep roasted espresso
  // ---------------------------------------------------------------------

  static const sidebar = Color(0xFF3B241C);
  static const sidebarForeground = Color(0xFFF6EFE6);
  static const sidebarMuted = Color(0x99F6EFE6);

  /// Selected / hovered nav row. The palette's dark brown hover.
  static const sidebarAccent = Color(0xFF634136);
  static const sidebarBorder = Color(0xFF55372C);

  /// Active nav indicator — caramel, lifted for contrast on espresso.
  static const sidebarWheat = Color(0xFFD9A574);

  // ---------------------------------------------------------------------
  // Semantic aliases (preferred in new code)
  // ---------------------------------------------------------------------

  /// Espresso brown — same as [green].
  static const espresso = green;

  /// Dark brown hover / pressed.
  static const espressoHover = Color(0xFF634136);

  /// Warm cream page ground — same as [page].
  static const cream = page;

  /// Caramel accent — same as [amber].
  static const caramel = amber;

  /// Caramel dark enough for text on cream.
  static const caramelDeep = Color(0xFF8A5A2B);

  /// Caramel wash for badge and banner fills.
  static const caramelSoft = Color(0xFFF7EADC);

  /// Sage green — natural accent for fills and illustrative marks.
  static const sage = Color(0xFF8A9A78);

  /// Deep sage — success text and badges (readable on cream and under white).
  static const success = Color(0xFF64754F);

  /// Sage wash for success banners.
  static const successSoft = Color(0xFFEDF1E6);

  /// Warm wash for error banners.
  static const dangerSoft = Color(0xFFFBEDEC);

  /// Milk white with a hint of warmth — used over espresso surfaces.
  static const milk = Color(0xFFF6EFE6);

  // ---------------------------------------------------------------------
  // Camera / face scanner chrome
  //
  // Deliberately dark so the camera preview keeps its contrast, but warmed
  // into the espresso family instead of the old blue-black.
  // ---------------------------------------------------------------------

  static const scannerShell = Color(0xFF241611);
  static const scannerBar = Color(0xFF1B0F0B);
  static const scannerDim = Color(0x59241611);

  /// "Ready to scan" text on the dark scanner bar.
  static const scannerReady = Color(0xFFB9C8A6);

  // ---------------------------------------------------------------------
  // Charts
  // ---------------------------------------------------------------------

  /// Categorical series colours — roasted, caramel and sage tones ordered so
  /// neighbouring slices stay distinguishable by both hue and lightness.
  static const chartPalette = <Color>[
    Color(0xFF4B2E24), // espresso
    Color(0xFFC58B5A), // caramel
    Color(0xFF8A9A78), // sage
    Color(0xFF8C5343), // clay
    Color(0xFFE0C9A6), // latte
    Color(0xFF64754F), // deep sage
    Color(0xFFA9754B), // toffee
    Color(0xFFD9A574), // golden caramel
    Color(0xFF6B6259), // warm grey
    Color(0xFF3B241C), // dark roast
  ];

  /// Sequential low → high ramp (cream to espresso). Monotonic in lightness so
  /// it stays readable for anyone who can't separate the hues.
  static const chartHeatRamp = <Color>[
    Color(0xFFEDE5DA), // none
    Color(0xFFE5D3BC),
    Color(0xFFD9B58C),
    Color(0xFFC58B5A),
    Color(0xFF9A5A28),
    Color(0xFF4B2E24), // peak
  ];

  // ---------------------------------------------------------------------
  // Elevation — warm, low-opacity shadows (never heavy)
  // ---------------------------------------------------------------------

  /// Tight contact shadow.
  static const shadowSoft = Color(0x0F4B2E24);

  /// Wider ambient shadow.
  static const shadowAmbient = Color(0x0A4B2E24);
}
