import 'package:flutter/material.dart';

/// Brand and semantic colors for the Kiyat driver app.
abstract final class AppColors {
  // ── Brand ──────────────────────────────────────────────────────────
  static const primary = Color(0xFF1B5E8B);
  static const primaryLight = Color(0xFF2980B9);
  static const primaryDark = Color(0xFF134A6E);
  static const accent = Color(0xFFF5A623);
  static const accentLight = Color(0xFFF7BC5E);

  // ── Backgrounds ────────────────────────────────────────────────────
  static const backgroundLight = Color(0xFFF8F9FA);
  static const surfaceLight = Colors.white;
  static const backgroundDark = Color(0xFF121212);
  static const surfaceDark = Color(0xFF1E1E1E);
  static const cardDark = Color(0xFF252525);

  // ── Semantic ───────────────────────────────────────────────────────
  static const success = Color(0xFF2E7D32);
  static const error = Color(0xFFD32F2F);
  static const warning = Color(0xFFF57C00);
  static const info = Color(0xFF1976D2);

  // ── Text ───────────────────────────────────────────────────────────
  static const textPrimaryLight = Color(0xFF1A1A2E);
  static const textSecondaryLight = Color(0xFF6B7280);
  static const textPrimaryDark = Color(0xFFF5F5F5);
  static const textSecondaryDark = Color(0xFF9CA3AF);

  // ── Online / Offline status ────────────────────────────────────────
  static const online = Color(0xFF22C55E);
  static const offline = Color(0xFF9CA3AF);
}
