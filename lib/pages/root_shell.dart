import 'package:flutter/material.dart';
import 'home_page.dart';
import 'verb_list_page.dart';
import 'history_page.dart';
import 'dashboard_page.dart';
import 'settings_page.dart';
import '../data/sync_service.dart';

class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _NavItem {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  const _NavItem(this.icon, this.selectedIcon, this.label);
}

class _RootShellState extends State<RootShell> {
  /// Au-delà de cette largeur, la barre du bas devient un menu latéral.
  static const double _railBreakpoint = 800;

  /// Largeur maximale du contenu : sur un grand écran, les pages restent
  /// lisibles au lieu de s'étirer sur toute la fenêtre.
  static const double _maxContentWidth = 1100;

  int _index = 0;

  final _pages = const [
    HomePage(),
    HistoryPage(),
    VerbListPage(),
    DashboardPage(),
    SettingsPage(),
  ];

  static const _items = [
    _NavItem(Icons.home_outlined, Icons.home, 'Accueil'),
    _NavItem(Icons.history_outlined, Icons.history, 'Historique'),
    _NavItem(Icons.menu_book_outlined, Icons.menu_book, 'Verbes'),
    _NavItem(Icons.dashboard_outlined, Icons.dashboard, 'Tableau de bord'),
    _NavItem(Icons.settings_outlined, Icons.settings, 'Paramètres'),
  ];

  @override
  void initState() {
    super.initState();
    _triggerInitialSync();
  }

  Future<void> _triggerInitialSync() async {
    // La synchro est facultative : si le serveur est absent ou injoignable,
    // l'application continue de fonctionner en local sans erreur.
    try {
      await SyncService.instance.syncCustomSetsIfEnabled();
    } catch (e) {
      debugPrint('Synchro ignorée : $e');
    }
  }

  void _select(int i) => setState(() => _index = i);

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= _railBreakpoint;

    final content = Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _maxContentWidth),
        child: IndexedStack(index: _index, children: _pages),
      ),
    );

    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _index,
              onDestinationSelected: _select,
              labelType: NavigationRailLabelType.all,
              destinations: [
                for (final item in _items)
                  NavigationRailDestination(
                    icon: Icon(item.icon),
                    selectedIcon: Icon(item.selectedIcon),
                    label: Text(item.label),
                  ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: content),
          ],
        ),
      );
    }

    return Scaffold(
      body: content,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _select,
        destinations: [
          for (final item in _items)
            NavigationDestination(
              icon: Icon(item.icon),
              selectedIcon: Icon(item.selectedIcon),
              label: item.label,
            ),
        ],
      ),
    );
  }
}
