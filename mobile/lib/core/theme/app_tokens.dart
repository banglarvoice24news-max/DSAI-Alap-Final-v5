// Canonical v1 design tokens — Direction A "Nilkantha" (নীলকণ্ঠ).
//
// DECISION LOCKED: seed #0F6D5E (deep kingfisher teal). The alternate
// Direction B "Maati o Jol" is NOT used for v1. dsaialap_FrontSite_Design_
// MasterPrompt_v1.md is absent from the repo, so this file is the single
// source of truth until the committed front-site palette/type pairing is
// supplied; screen prototypes must read colors only from here.
//
// Transport colours are semantic and fixed (mesh / voip / gsm) so the UI never
// invents a 4th meaning for a status colour.

import 'package:flutter/material.dart';

abstract final class AppTokens {
  // Direction A Nilkantha palette -------------------------------------------------
  static const Color seed = Color(0xFF0F6D5E);

  /// Near-black, faintly green-tinted night canvas (replaces the blue-black
  /// `oled` of the earlier prototype).
  static const Color canvas = Color(0xFF050B0A);

  /// Raised surface for cards / sheets.
  static const Color surface = Color(0xFF0C1F1B);

  /// Primary (Nilkantha teal) and its brighter glow variants.
  static const Color primary = Color(0xFF0F6D5E);
  static const Color primaryBright = Color(0xFF2FC9A8);
  static const Color mint = Color(0xFF7CF0D4);

  static const Color textPrimary = Color(0xFFEAF6F2);
  static const Color textSecondary = Color(0xFF9CB8B0);

  static const Color glassFill = Color(0x3312A188);
  static const Color glassStroke = Color(0x3DFFFFFF);

  // Semantic transport colours ----------------------------------------------------
  static const Color mesh = Color(0xFF3DE0C2);
  static const Color voip = Color(0xFFA78BFA);
  static const Color gsm = Color(0xFFFFB84D);

  static Color forTransport(String transport) {
    return switch (transport) {
      'mesh' => mesh,
      'voip' => voip,
      'gsm' => gsm,
      _ => textSecondary,
    };
  }

  // Status ------------------------------------------------------------------------
  static const Color success = Color(0xFF67E8A2);
  static const Color warn = Color(0xFFFFC35C);
  static const Color danger = Color(0xFFFF6B6B);
}
