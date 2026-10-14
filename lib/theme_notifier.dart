import 'package:flutter/material.dart';

// Fichier dédié au ValueNotifier du thème pour éviter les imports circulaires.
// main.dart et settings_page.dart importent tous les deux ce fichier,
// sans se référencer mutuellement.
final ValueNotifier<ThemeMode> themeModeNotifier = ValueNotifier(
  ThemeMode.light,
);
