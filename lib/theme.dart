import 'package:flutter/material.dart';

/// DSH 品牌蓝 + 暖中性设计令牌(与 docs/design/launcher-mockup.html 一致)。
const Color dshBg = Color(0xFFF5F6F4);
const Color dshSurface = Color(0xFFFFFFFF);
const Color dshSurface2 = Color(0xFFF0F2EE);
const Color dshBorder = Color(0xFFE1E6DD);
const Color dshBorderStrong = Color(0xFFCBD2C6);
const Color dshInk = Color(0xFF1B241F);
const Color dshInk2 = Color(0xFF5A645E);
const Color dshInk3 = Color(0xFF8B948E);
const Color dshPrimary = Color(0xFF243B7A);
const Color dshPrimaryHover = Color(0xFF1D315F);
const Color dshAccent = Color(0xFF3B5BE0);
const Color dshAccentHover = Color(0xFF2F4BC4);
const Color dshAccentSoft = Color(0xFFE3EAFF);
const Color dshAccentSofter = Color(0xFFF0F4FF);
const Color dshGold = Color(0xFFC9A227);
const Color dshDanger = Color(0xFFB23B3B);
const Color dshDangerSoft = Color(0xFFF9E8E8);
const Color dshLogBg = Color(0xFF121A16);
const Color dshLogBorder = Color(0xFF26332C);
const Color dshLogText = Color(0xFFB9C9C0);

ThemeData buildDshTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: dshPrimary,
    primary: dshPrimary,
    secondary: dshAccent,
    surface: dshSurface,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: const Color(0xFFE8EBE5),
    fontFamilyFallback: const ['Microsoft YaHei', 'Segoe UI'],
  );
}
