import 'package:flutter/material.dart';

/// Couleurs qui s'adaptent au mode clair et au mode sombre.
/// À utiliser à la place de Colors.white, Colors.black87 ou d'un fond clair
/// écrit en dur : sinon la page reste claire quand on active le mode sombre.
extension AppColors on BuildContext {
  bool get isDarkMode => Theme.of(this).brightness == Brightness.dark;

  /// Fond d'une carte, d'une boîte de dialogue ou d'une pastille.
  Color get cardBackground =>
      isDarkMode ? const Color(0xFF1F2937) : Colors.white;

  /// Fond d'un encadré légèrement teinté.
  Color get softPanel =>
      isDarkMode ? const Color(0xFF374151) : const Color(0xFFF3F4FF);

  /// Texte secondaire (légendes, descriptions).
  Color get mutedText => isDarkMode ? Colors.white70 : Colors.black54;

  /// Dégradé de fond des pages de jeu.
  List<Color> get pageGradient => isDarkMode
      ? const [Color(0xFF111827), Color(0xFF0B1220)]
      : const [Color(0xFFEFF3FF), Color(0xFFF7F8FC)];
}
