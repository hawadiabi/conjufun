import 'package:flutter/material.dart';
import '../ui/app_colors.dart';
import '../main.dart' show brandBlue, brandYellow;
import 'exercise_page.dart';
import 'dashboard_page.dart';
import '../viewmodels/exercise_vm.dart' as vm;
import '../config/levels_config.dart' show GameLevelInfo, gameLevelFromKey;
import '../data/app_db.dart';
import 'level_test_page.dart';
import 'creator_home_page.dart';
import '../widgets/auth_sheet.dart';
import '../data/auth_repo.dart';
import '../data/sync_service.dart';
import '../session_notifier.dart';

enum SessionMode { unlimited, fixed }

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  // --- paramètres de partie ---
  SessionMode _mode = SessionMode.unlimited;
  int _fixedCount = 10;
  vm.GameLevel _level = vm.GameLevel.level_cycle1;

  bool _hasDoneLevelTest = false;

  // true dès que l'élève choisit un niveau lui-même : le rechargement de la
  // session ne doit plus l'écraser avec le niveau recommandé.
  bool _levelChosenByUser = false;

  // niveau recommandé (test de niveau)
  bool _hasRecommendedLevel = false;
  vm.GameLevel? _recommendedLevel;
  String? _recommendedLevelLabel;

  // --- session ---
  bool _isLoggedIn = false;
  String _displayName = '';
  String _userEmail = '';
  bool _hasAnyRun = false;

  // --- streak ---
  int _currentStreak = 0;
  int _bestStreak = 0;
  late AnimationController _flameController;
  late Animation<double> _flameAnimation;

  @override
  void initState() {
    super.initState();
    _flameController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _flameAnimation = Tween<double>(begin: 0.85, end: 1.15).animate(
      CurvedAnimation(parent: _flameController, curve: Curves.easeInOut),
    );
    // La page reste en vie dans l'IndexedStack : elle se recharge quand le
    // compte change ou que des parties/badges sont enregistrés.
    appStateChanged.addListener(_loadSession);
    _loadSession();
  }

  @override
  void dispose() {
    appStateChanged.removeListener(_loadSession);
    _flameController.dispose();
    super.dispose();
  }

  /// Recharge tout ce qui dépend du compte et des données de jeu.
  Future<void> _loadSession() async {
    final user = await AuthRepo.instance.getCurrentUser();
    final userId = user == null ? null : user['id'] as int;

    // userId == null : parties de l'invité uniquement.
    final totalScore = await AppDb.instance.getTotalScore(userId: userId);

    bool hasDoneTest = false;
    vm.GameLevel? recommended;
    int currentStreak = 0;
    int bestStreak = 0;

    if (userId != null) {
      final info = await AppDb.instance.getUserLevelTestResult(userId);
      if (info != null) {
        hasDoneTest = (info['has_done_level_test'] as int? ?? 0) == 1;
        if (hasDoneTest) {
          recommended = gameLevelFromKey(
            info['last_recommended_level'] as String?,
          );
        }
      }
      final streakData = await AppDb.instance.getStreakForUser(userId);
      currentStreak = streakData['current'] ?? 0;
      bestStreak = streakData['best'] ?? 0;
    }

    if (!mounted) return;
    setState(() {
      _isLoggedIn = user != null;
      _displayName = (user?['display_name'] as String?) ?? '';
      _userEmail = (user?['email'] as String?) ?? '';
      _hasAnyRun = totalScore > 0;
      _hasDoneLevelTest = hasDoneTest;
      _hasRecommendedLevel = hasDoneTest && recommended != null;
      _recommendedLevel = recommended;
      _recommendedLevelLabel = recommended?.label;
      _currentStreak = currentStreak;
      _bestStreak = bestStreak;

      // Le niveau recommandé n'est appliqué que si l'élève n'a pas déjà
      // choisi un niveau à la main.
      if (recommended != null && !_levelChosenByUser) {
        _level = recommended;
      }
    });
  }

  Future<void> _openLevelTest() async {
    final result = await Navigator.push<vm.GameLevel?>(
      context,
      MaterialPageRoute(builder: (_) => const LevelTestPage()),
    );

    if (result == null || !mounted) return;
    // LevelTestPage enregistre déjà le résultat pour un compte connecté.
    setState(() {
      _level = result;
      _levelChosenByUser = true;
      _hasDoneLevelTest = true;
      _hasRecommendedLevel = true;
      _recommendedLevel = result;
      _recommendedLevelLabel = result.label;
    });
  }

  Future<void> _onRetakeLevelTest() => _openLevelTest();

  Future<void> _signOut() async {
    await AuthRepo.instance.signOut();
    if (!mounted) return;
    setState(() => _levelChosenByUser = false);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Déconnecté.')));
  }

  /// Après une connexion / inscription : recharge puis synchronise en
  /// arrière-plan (une erreur réseau ne doit jamais gêner l'élève).
  Future<void> _afterAuth() async {
    await _loadSession();
    try {
      // ignore: unawaited_futures
      SyncService.instance.syncCustomSetsIfEnabled().catchError((_) {});
    } catch (_) {}
  }

  // ---------- Popover compte ----------
  Future<void> _showAccountMenu(BuildContext context) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    const panelWidth = 280.0;
    const rightPadding = 12.0;

    final top = kToolbarHeight + MediaQuery.of(context).padding.top;
    final left = overlay.size.width - panelWidth - rightPadding;
    final position = RelativeRect.fromLTRB(left, top, rightPadding, 0);

    final selected = await showMenu<int>(
      context: context,
      position: position,
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      constraints: const BoxConstraints.tightFor(width: panelWidth),
      items: <PopupMenuEntry<int>>[
        PopupMenuItem<int>(
          value: 1,
          padding: EdgeInsets.zero,
          child: ListTile(
            dense: true,
            leading: const Icon(Icons.account_circle),
            title: Text(
              _displayName.isEmpty ? 'Mon compte' : _displayName,
              style: const TextStyle(fontWeight: FontWeight.w700),
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: _userEmail.isEmpty
                ? null
                : Text(_userEmail, overflow: TextOverflow.ellipsis),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          ),
        ),
        const PopupMenuDivider(height: 8),
        PopupMenuItem<int>(
          value: 2,
          child: ListTile(
            dense: true,
            leading: const Icon(Icons.logout, color: Colors.redAccent),
            title: const Text(
              'Déconnecter',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600),
            ),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
    );

    switch (selected) {
      case 1:
        if (!context.mounted) return;
        await Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const DashboardPage()));
        break;
      case 2:
        await _signOut();
        break;
      default:
        break;
    }
  }

  // ---------- Guide des niveaux ----------
  void _showLevelGuide() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Guide des niveaux'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text('Cycle 1', style: TextStyle(fontWeight: FontWeight.w800)),
              SizedBox(height: 4),
              Text(
                '• Verbes adaptés au 1er cycle.\n• Temps : présent, futur proche, impératif.',
              ),
              SizedBox(height: 12),
              Text('Cycle 2', style: TextStyle(fontWeight: FontWeight.w800)),
              SizedBox(height: 4),
              Text(
                '• Verbes du cycle 1 + nouveaux verbes.\n• Temps : présent, passé composé, futur proche, imparfait, futur simple, impératif.',
              ),
              SizedBox(height: 12),
              Text('Cycle 3', style: TextStyle(fontWeight: FontWeight.w800)),
              SizedBox(height: 4),
              Text(
                '• Verbes des cycles précédents.\n• Temps : présent, passé composé, futur proche, imparfait, futur simple, impératif.',
              ),
              SizedBox(height: 12),
              Text(
                'Secondaire 1',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              SizedBox(height: 4),
              Text(
                '• Verbes du primaire + verbes spécifiques au secondaire 1.\n• Temps : présent, passé composé, futur proche, imparfait, futur simple, impératif, conditionnel présent, passé simple, subjonctif présent.',
              ),
              SizedBox(height: 12),
              Text(
                'Secondaire 2',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              SizedBox(height: 4),
              Text(
                '• Verbes du secondaire 1 + verbes spécifiques au secondaire 2.\n• Temps : présent, passé composé, futur proche, imparfait, futur simple, impératif, conditionnel présent, plus-que-parfait, passé simple, subjonctif présent, conditionnel passé, futur antérieur.',
              ),
              SizedBox(height: 12),
              Text('Expert', style: TextStyle(fontWeight: FontWeight.w800)),
              SizedBox(height: 4),
              Text(
                '• Tous les verbes du dictionnaire LEFFF.\n• Tous les temps supportés par le jeu.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Compris !'),
          ),
        ],
      ),
    );
  }

  // ---------- UI principale ----------
  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final bool isCompactAppBar = screenWidth < 380;

    final String helloName = _displayName.isNotEmpty
        ? _displayName
        : (_userEmail.isNotEmpty ? _userEmail : 'Mon compte');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bienvenue sur ConjuFun'),
        backgroundColor: brandBlue,
        foregroundColor: Colors.white,
        actions: [
          if (!_isLoggedIn) ...[
            TextButton(
              onPressed: () async {
                final ok = await showLoginSheet(context);
                if (ok == true) await _afterAuth();
              },
              child: const Text(
                'Se connecter',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: ElevatedButton(
                onPressed: () async {
                  final ok = await showSignupSheet(context);
                  if (ok == true) await _afterAuth();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: brandYellow,
                  foregroundColor: brandBlue,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(22),
                  ),
                  elevation: 0,
                ),
                child: const Text(
                  'Créer un compte',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ] else ...[
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: InkWell(
                onTap: () => _showAccountMenu(context),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.account_circle, color: Colors.white),
                    const SizedBox(width: 6),
                    SizedBox(
                      width: isCompactAppBar ? 150 : 240,
                      child: Text(
                        'Bonjour, $helloName !',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const Icon(Icons.arrow_drop_down, color: Colors.white),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
      body: Container(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(
              child: Column(
                children: [
                  if (!_isLoggedIn && _hasAnyRun) ...[
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 600),
                        child: Card(
                          surfaceTintColor: Colors.transparent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: const ListTile(
                            leading: Icon(
                              Icons.cloud_off_outlined,
                              color: brandBlue,
                            ),
                            title: Text(
                              'Ne perdez pas votre progression !',
                              style: TextStyle(fontWeight: FontWeight.w900),
                            ),
                            subtitle: Text(
                              'Connectez-vous ou créez un compte pour garder vos scores, badges et séries.',
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  if (_isLoggedIn)
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 600),
                        child: Card(
                          surfaceTintColor: Colors.transparent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: ListTile(
                            leading: const Icon(
                              Icons.cloud_done_outlined,
                              color: brandBlue,
                            ),
                            title: Text(
                              'Connecté en tant que ${_displayName.isNotEmpty ? _displayName : _userEmail}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: brandBlue,
                              ),
                            ),
                            subtitle: _userEmail.isEmpty
                                ? null
                                : Text(_userEmail),
                          ),
                        ),
                      ),
                    ),

                  const SizedBox(height: 12),

                  LayoutBuilder(
                    builder: (context, constraints) {
                      const double maxCardWidth = 400;

                      if (constraints.maxWidth > 950) {
                        return Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: maxCardWidth,
                              child: _buildModeCard(context),
                            ),
                            const SizedBox(width: 20),
                            SizedBox(
                              width: maxCardWidth,
                              child: _buildLevelCard(context),
                            ),
                          ],
                        );
                      } else {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: maxCardWidth,
                              child: _buildModeCard(context),
                            ),
                            const SizedBox(height: 16),
                            SizedBox(
                              width: maxCardWidth,
                              child: _buildLevelCard(context),
                            ),
                          ],
                        );
                      }
                    },
                  ),

                  const SizedBox(height: 20),
                  if (_isLoggedIn && _currentStreak > 0)
                    _buildStreakCard(context),
                  if (_isLoggedIn && _currentStreak > 0)
                    const SizedBox(height: 16),
                  _buildCreatorCard(context),
                  const SizedBox(height: 16),
                  _buildSummaryCard(context),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ---------- Carte streak animée ----------
  Widget _buildStreakCard(BuildContext context) {
    final bool isOnFire = _currentStreak >= 3;
    final Color flameColor = _currentStreak >= 30
        ? const Color(0xFFFF3D00)
        : _currentStreak >= 7
        ? const Color(0xFFFF6D00)
        : const Color(0xFFF59E0B);

    return Align(
      alignment: Alignment.center,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 750),
        child: Card(
          elevation: 3,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  flameColor.withValues(alpha: .12),
                  flameColor.withValues(alpha: .04),
                ],
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Row(
              children: [
                // Flamme animée
                AnimatedBuilder(
                  animation: _flameAnimation,
                  builder: (context, child) {
                    return Transform.scale(
                      scale: _flameAnimation.value,
                      child: child,
                    );
                  },
                  child: Text(
                    isOnFire ? '🔥' : '✨',
                    style: const TextStyle(fontSize: 36),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$_currentStreak jour${_currentStreak > 1 ? 's' : ''} de suite !',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: flameColor,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _currentStreak >= 30
                            ? 'Tu es une machine à conjugaison 💪'
                            : _currentStreak >= 7
                            ? 'Une semaine complète, continue comme ça !'
                            : _currentStreak >= 3
                            ? 'La flamme est allumée, ne l\'éteins pas !'
                            : 'Reviens demain pour continuer ta série !',
                        style: TextStyle(
                          fontSize: 13,
                          color: flameColor.withValues(alpha: .8),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                // Record
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Record',
                      style: TextStyle(
                        fontSize: 11,
                        color: flameColor.withValues(alpha: .6),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '$_bestStreak j',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: flameColor,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------- Cartes ----------
  Widget _buildModeCard(BuildContext context) {
    return Card(
      elevation: 3,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Mode de jeu',
              style: Theme.of(context).textTheme.titleMedium!.copyWith(
                color: brandBlue,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            RadioGroup<SessionMode>(
              groupValue: _mode,
              onChanged: (v) {
                if (v != null) setState(() => _mode = v);
              },
              child: Column(
                children: [
                  RadioListTile<SessionMode>(
                    title: const Text('Illimité (fin à la première erreur)'),
                    value: SessionMode.unlimited,
                    activeColor: brandBlue,
                  ),
                  RadioListTile<SessionMode>(
                    title: Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      children: [
                        const Text('Fixe'),
                        DropdownButton<int>(
                          value: _fixedCount,
                          items: const [
                            DropdownMenuItem(value: 10, child: Text('10')),
                            DropdownMenuItem(value: 15, child: Text('15')),
                            DropdownMenuItem(value: 25, child: Text('25')),
                          ],
                          onChanged: _mode == SessionMode.fixed
                              ? (v) => setState(() => _fixedCount = v!)
                              : null,
                        ),
                        const Text('questions'),
                      ],
                    ),
                    value: SessionMode.fixed,
                    activeColor: brandBlue,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLevelOption(vm.GameLevel level, String label) {
    final bool isRecommended =
        _hasRecommendedLevel && _recommendedLevel == level;
    final bool isSelected = _level == level;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: RadioListTile<vm.GameLevel>(
        value: level,
        dense: true,
        contentPadding: EdgeInsets.zero,
        activeColor: brandBlue,
        selected: isSelected,
        selectedTileColor: brandBlue.withValues(alpha: .04),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
            if (isRecommended)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: brandYellow.withValues(alpha: .9),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'Recommandé',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: brandBlue,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _onLevelChanged(vm.GameLevel? val) {
    if (val == null) return;
    setState(() {
      _level = val;
      _levelChosenByUser = true;
    });
  }

  Widget _buildLevelCard(BuildContext context) {
    final String? localRecommendedText = _hasDoneLevelTest
        ? 'Niveau recommandé : ${_recommendedLevelLabel ?? _level.label}'
        : null;

    return Card(
      elevation: 2,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final bool isNarrow = constraints.maxWidth < 420;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        'Niveau',
                        style: Theme.of(context).textTheme.titleMedium!
                            .copyWith(
                              color: brandBlue,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _showLevelGuide,
                      icon: const Icon(
                        Icons.help_outline,
                        size: 18,
                        color: brandBlue,
                      ),
                      label: const Text(
                        'Guide des niveaux',
                        style: TextStyle(
                          fontSize: 12,
                          color: brandBlue,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 0),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                if (localRecommendedText != null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: brandYellow.withValues(alpha: .18),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.star_rounded,
                          color: brandYellow,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            localRecommendedText,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                ],

                RadioGroup<vm.GameLevel>(
                  groupValue: _level,
                  onChanged: _onLevelChanged,
                  child: isNarrow
                      ? Column(
                          children: [
                            _buildLevelOption(
                              vm.GameLevel.level_cycle1,
                              'Primaire - Cycle 1 (Niveau 1)',
                            ),
                            _buildLevelOption(
                              vm.GameLevel.level_cycle2,
                              'Primaire - Cycle 2 (Niveau 2)',
                            ),
                            _buildLevelOption(
                              vm.GameLevel.level_cycle3,
                              'Primaire - Cycle 3 (Niveau 3)',
                            ),
                            _buildLevelOption(
                              vm.GameLevel.level_sec1,
                              'Secondaire 1 (Niveau 4)',
                            ),
                            _buildLevelOption(
                              vm.GameLevel.level_sec2,
                              'Secondaire 2 (Niveau 5)',
                            ),
                            _buildLevelOption(vm.GameLevel.expert, 'Expert'),
                          ],
                        )
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                children: [
                                  _buildLevelOption(
                                    vm.GameLevel.level_cycle1,
                                    'Cycle 1',
                                  ),
                                  _buildLevelOption(
                                    vm.GameLevel.level_cycle2,
                                    'Cycle 2',
                                  ),
                                  _buildLevelOption(
                                    vm.GameLevel.level_cycle3,
                                    'Cycle 3',
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                children: [
                                  _buildLevelOption(
                                    vm.GameLevel.level_sec1,
                                    'Secondaire 1',
                                  ),
                                  _buildLevelOption(
                                    vm.GameLevel.level_sec2,
                                    'Secondaire 2',
                                  ),
                                  _buildLevelOption(
                                    vm.GameLevel.expert,
                                    'Expert',
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                ),

                const SizedBox(height: 12),
                Center(
                  child: TextButton(
                    onPressed: _hasDoneLevelTest
                        ? _onRetakeLevelTest
                        : _openLevelTest,
                    child: Text(
                      _hasDoneLevelTest
                          ? 'Refaire le test de niveau'
                          : 'Vous ne savez pas quel niveau choisir ?\nPassez le test de niveau !',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: brandBlue,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildCreatorCard(BuildContext context) {
    return Align(
      alignment: Alignment.center,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 750),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final bool isNarrow = constraints.maxWidth < 420;

            return Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
              ),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF2E5BFF), Color(0xFF5F9BFF)],
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 18,
                  ),
                  child: isNarrow
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: .18),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: const Icon(
                                    Icons.auto_fix_high,
                                    color: Colors.white,
                                    size: 26,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: const [
                                      Text(
                                        'Mode créateur',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 18,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                      SizedBox(height: 4),
                                      Text(
                                        'Crée tes propres ensembles d’exercices : choisis les verbes, les temps et le nombre de questions pour fabriquer des parties sur mesure.',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 12.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => CreatorHomePage(
                                        mode: _mode,
                                        fixedCount: _fixedCount,
                                        level: _level,
                                      ),
                                    ),
                                  );
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: brandYellow,
                                  foregroundColor: brandBlue,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                ),
                                child: const Text(
                                  'Ouvrir',
                                  style: TextStyle(fontWeight: FontWeight.w800),
                                ),
                              ),
                            ),
                          ],
                        )
                      : Row(
                          children: [
                            Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: .18),
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: const Icon(
                                Icons.auto_fix_high,
                                color: Colors.white,
                                size: 30,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: const [
                                  Text(
                                    'Mode créateur',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    'Crée tes propres ensembles d’exercices : choisis les verbes, les temps et le nombre de questions pour fabriquer des parties sur mesure.',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            ElevatedButton(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => CreatorHomePage(
                                      mode: _mode,
                                      fixedCount: _fixedCount,
                                      level: _level,
                                    ),
                                  ),
                                );
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: brandYellow,
                                foregroundColor: brandBlue,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 10,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18),
                                ),
                              ),
                              child: const Text(
                                'Ouvrir',
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildSummaryCard(BuildContext context) {
    final levelText = () {
      switch (_level) {
        case vm.GameLevel.level_cycle1:
          return 'Niveau 1 (Cycle 1)';
        case vm.GameLevel.level_cycle2:
          return 'Niveau 2 (Cycle 2)';
        case vm.GameLevel.level_cycle3:
          return 'Niveau 3 (Cycle 3)';
        case vm.GameLevel.level_sec1:
          return 'Secondaire 1';
        case vm.GameLevel.level_sec2:
          return 'Secondaire 2';
        case vm.GameLevel.expert:
          return 'Expert';
      }
    }();

    return Align(
      alignment: Alignment.center,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 750),
        child: Card(
          elevation: 3,
          margin: const EdgeInsets.only(top: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: brandYellow.withValues(alpha: .3),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.play_circle_fill,
                        color: brandBlue,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Résumé de la session',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '${_mode == SessionMode.unlimited ? 'Illimité' : 'Fixe ($_fixedCount q.)'} • $levelText',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: brandBlue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ExercisePage(
                            mode: _mode,
                            fixedCount: _mode == SessionMode.fixed
                                ? _fixedCount
                                : null,
                            level: _level,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.play_arrow),
                    label: const Text(
                      'Commencer',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Commence une partie classique avec les paramètres ci-dessus.',
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: context.mutedText),
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
