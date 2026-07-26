import 'package:flutter/material.dart';

class AppColors {
  static const green = Color(0xFF1F8A4C);
  static const darkGreen = Color(0xFF0E5F35);
  static const lightGreen = Color(0xFFEAF7EF);
  static const greenBorder = Color(0xFFC8EAD4);
  static const amber = Color(0xFFF2A93B);
  static const page = Color(0xFFF4F6F5);
  static const surface = Color(0xFFFFFFFF);
  static const softSurface = Color(0xFFFAFBFC);
  static const border = Color(0xFFE1E7EC);
  static const text = Color(0xFF17202A);
  static const muted = Color(0xFF64748B);
  static const danger = Color(0xFFE23A4E);
  static const orange = Color(0xFFE8891C);
  static const blue = Color(0xFF2563EB);

  static const primaryGradient = LinearGradient(
    colors: [darkGreen, green],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  // Laravel admin sidebar (app.css --sidebar tokens)
  static const sidebar = Color(0xFF2A4A3E);
  static const sidebarForeground = Color(0xFFEEF6F0);
  static const sidebarMuted = Color(0x99EEF6F0);
  static const sidebarAccent = Color(0xFF355548);
  static const sidebarBorder = Color(0xFF3D6354);
  static const sidebarWheat = Color(0xFFC9A84C);
}
