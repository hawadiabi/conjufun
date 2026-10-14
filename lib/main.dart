import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'pages/root_shell.dart';
import 'theme_notifier.dart';

// Palette ConjuFun
const brandBlue = Color(0xFF1E40AF);
const brandYellow = Color(0xFFF59E0B);

// Bleu clair lisible sur fond sombre (le bleu de marque y est trop foncé).
const brandBlueOnDark = Color(0xFF93C5FD);

final RouteObserver<ModalRoute<dynamic>> routeObserver =
    RouteObserver<ModalRoute<dynamic>>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();
  final savedDark = prefs.getBool('dark_mode_enabled') ?? false;
  themeModeNotifier.value = savedDark ? ThemeMode.dark : ThemeMode.light;

  runApp(const ConjuFunApp());
}

class ConjuFunApp extends StatefulWidget {
  const ConjuFunApp({super.key});

  @override
  State<ConjuFunApp> createState() => _ConjuFunAppState();
}

class _ConjuFunAppState extends State<ConjuFunApp> {
  @override
  void initState() {
    super.initState();
    // Reconstruire MaterialApp chaque fois que le mode change
    themeModeNotifier.addListener(_onThemeChanged);
  }

  @override
  void dispose() {
    themeModeNotifier.removeListener(_onThemeChanged);
    super.dispose();
  }

  void _onThemeChanged() => setState(() {});

  ThemeData _buildTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    // Couleurs qui changent selon le mode.
    final surfaceColor = isDark ? const Color(0xFF1F2937) : Colors.white;
    final pageColor = isDark
        ? const Color(0xFF111827)
        : const Color(0xFFF7F8FC);
    final accent = isDark ? brandBlueOnDark : brandBlue;

    final baseScheme = ColorScheme.fromSeed(
      seedColor: brandBlue,
      brightness: brightness,
    );
    final scheme = baseScheme.copyWith(
      primary: isDark ? brandBlueOnDark : brandBlue,
      onPrimary: isDark ? const Color(0xFF0B1220) : Colors.white,
      secondary: brandYellow,
      tertiary: brandYellow,
      surfaceTint: brandBlue,
    );

    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      visualDensity: VisualDensity.adaptivePlatformDensity,
      scaffoldBackgroundColor: pageColor,

      appBarTheme: const AppBarTheme(
        backgroundColor: brandBlue,
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 20,
          color: Colors.white,
        ),
      ),

      textTheme: const TextTheme(
        headlineSmall: TextStyle(fontWeight: FontWeight.w800),
        titleMedium: TextStyle(fontWeight: FontWeight.w700),
      ),

      cardTheme: CardThemeData(
        elevation: 2,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        surfaceTintColor: Colors.transparent,
        color: surfaceColor,
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surfaceColor,
        surfaceTintColor: Colors.transparent,
        indicatorColor: brandYellow.withValues(alpha: isDark ? .35 : .28),
        labelTextStyle: WidgetStateProperty.resolveWith<TextStyle>(
          (states) => TextStyle(
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w800
                : FontWeight.w600,
            color: states.contains(WidgetState.selected)
                ? accent
                : scheme.onSurfaceVariant,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith<IconThemeData>(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? accent
                : scheme.onSurfaceVariant,
          ),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: surfaceColor,
        indicatorColor: brandYellow.withValues(alpha: isDark ? .35 : .28),
        selectedIconTheme: IconThemeData(color: accent),
        unselectedIconTheme: IconThemeData(color: scheme.onSurfaceVariant),
        selectedLabelTextStyle: TextStyle(
          color: accent,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
        unselectedLabelTextStyle: TextStyle(
          color: scheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: surfaceColor,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surfaceColor,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: brandYellow,
        foregroundColor: brandBlue,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        space: 1,
        thickness: 1,
      ),

      chipTheme: ChipThemeData(
        backgroundColor: brandYellow.withValues(alpha: .20),
        selectedColor: brandYellow.withValues(alpha: .30),
        labelStyle: TextStyle(color: accent, fontWeight: FontWeight.w800),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: brandBlue,
          foregroundColor: Colors.white,
          minimumSize: const Size(120, 44),
          shape: buttonShape,
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          backgroundColor: brandYellow.withValues(alpha: 0.15),
          side: const BorderSide(color: brandYellow, width: 1.5),
          foregroundColor: accent,
          minimumSize: const Size(120, 44),
          shape: buttonShape,
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accent,
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? const Color(0xFF374151) : Colors.white,
        labelStyle: TextStyle(color: accent.withValues(alpha: .9)),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: accent.withValues(alpha: .25)),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
          borderSide: BorderSide(color: brandYellow, width: 2),
        ),
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: brandYellow,
        linearTrackColor: accent.withValues(alpha: .15),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ConjuFun',
      themeMode: themeModeNotifier.value,
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      home: const RootShell(),
      navigatorObservers: [routeObserver],
    );
  }
}
