import 'package:flutter/material.dart';
import '../data/auth_repo.dart';
import '../session_notifier.dart';
import 'package:fl_chart/fl_chart.dart';
import '../data/app_db.dart';
import '../config/levels_config.dart' show levelLabelFromKey;
import '../ui/app_colors.dart';
import '../main.dart' show brandBlue, brandYellow, routeObserver;
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:open_filex/open_filex.dart';

class StatsOverviewContent extends StatefulWidget {
  const StatsOverviewContent({super.key});

  @override
  State<StatsOverviewContent> createState() => _StatsOverviewContentState();
}

class _ModeStats {
  final String mode;
  final int runs;
  final int correct;
  final int total;

  int get percent => total == 0 ? 0 : ((correct * 100) / total).round();

  _ModeStats({
    required this.mode,
    required this.runs,
    required this.correct,
    required this.total,
  });
}

class _LevelStats {
  final String levelKey;
  int runs = 0;
  int correct = 0;
  int total = 0;

  _LevelStats({required this.levelKey});

  int get percent => total == 0 ? 0 : ((correct * 100) / total).round();

  String get label => levelLabelFromKey(levelKey);
}

class _TenseStats {
  final String tense;
  final int correct;
  final int wrong;

  _TenseStats({
    required this.tense,
    required this.correct,
    required this.wrong,
  });

  int get total => correct + wrong;
  int get percent => total == 0 ? 0 : ((correct * 100) / total).round();
}

class _StatsData {
  final bool hasUserId;
  final List<_ModeStats> byMode;
  final List<_LevelStats> byLevel;
  final List<_TenseStats> byTense;

  // Records
  final int fixedRecord;
  final int unlimitedRecord;
  final int globalRecord;

  // Niveau issu du test de niveau (optionnel)
  final String? placementLevelKey;

  // Streak courant
  final int currentStreak;

  _StatsData({
    required this.hasUserId,
    required this.byMode,
    required this.byLevel,
    required this.byTense,
    required this.fixedRecord,
    required this.unlimitedRecord,
    required this.globalRecord,
    required this.placementLevelKey,
    required this.currentStreak,
  });
}

class _StatsOverviewContentState extends State<StatsOverviewContent>
    with RouteAware {
  final GlobalKey _exportKey = GlobalKey();
  late Future<_StatsData> _future;

  int _selectedSectionIndex = 0;

  @override
  void initState() {
    super.initState();
    _future = _loadStats();
    appStateChanged.addListener(_reload);
  }

  void _reload() {
    if (!mounted) return;
    setState(() {
      _future = _loadStats();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null) {
      routeObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    appStateChanged.removeListener(_reload);
    routeObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPopNext() {
    setState(() {
      _future = _loadStats();
    });
  }

  String? _normalizePlacementKey(String? raw) {
    if (raw == null) return null;
    if (raw.startsWith('GameLevel.')) {
      return raw.substring('GameLevel.'.length);
    }
    return raw;
  }

  Future<pw.Font> _loadFont(String path) async {
    final data = await rootBundle.load(path);
    return pw.Font.ttf(data);
  }

  Future<void> _exportStatsAsPdf() async {
    try {
      // 1. Récupérer les stats déjà chargées par la page
      final data = await _future;

      // 2. Charger les polices
      final fontRegular = await _loadFont('assets/fonts/Roboto-Regular.ttf');
      final fontBold = await _loadFont('assets/fonts/Roboto-Bold.ttf');

      // 3. Raccourcis sur les stats par mode
      final fixed = data.byMode.firstWhere(
        (m) => m.mode == 'fixed',
        orElse: () => _ModeStats(mode: 'fixed', runs: 0, correct: 0, total: 0),
      );
      final unlimited = data.byMode.firstWhere(
        (m) => m.mode == 'unlimited',
        orElse: () =>
            _ModeStats(mode: 'unlimited', runs: 0, correct: 0, total: 0),
      );

      // 4. Styles
      final titleStyle = pw.TextStyle(font: fontBold, fontSize: 24);
      final sectionTitleStyle = pw.TextStyle(font: fontBold, fontSize: 16);
      final labelStyle = pw.TextStyle(font: fontBold, fontSize: 12);
      final valueStyle = pw.TextStyle(font: fontRegular, fontSize: 12);
      final smallStyle = pw.TextStyle(font: fontRegular, fontSize: 10);

      pw.Widget statLine(String label, String value) {
        return pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 2),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(label, style: labelStyle),
              pw.Text(value, style: valueStyle),
            ],
          ),
        );
      }

      final pdf = pw.Document();

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          build: (context) => [
            // ===== Titre =====
            pw.Text('Statistiques ConjuFun', style: titleStyle),
            pw.SizedBox(height: 4),
            pw.Text(
              'Résumé de ta progression dans le jeu de conjugaison.',
              style: smallStyle,
            ),
            pw.SizedBox(height: 24),

            // ===== Section : Résumé global =====
            pw.Container(
              padding: const pw.EdgeInsets.all(14),
              decoration: pw.BoxDecoration(
                borderRadius: pw.BorderRadius.circular(10),
                border: pw.Border.all(color: PdfColors.grey300),
                color: PdfColors.grey50,
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  pw.Text('Résumé global', style: sectionTitleStyle),
                  pw.SizedBox(height: 10),
                  statLine('Sessions fixes', fixed.runs.toString()),
                  statLine('Sessions illimitées', unlimited.runs.toString()),
                  pw.SizedBox(height: 6),
                  statLine('Record mode fixe', data.fixedRecord.toString()),
                  statLine('Record illimité', data.unlimitedRecord.toString()),
                  statLine('Record global', data.globalRecord.toString()),
                  pw.SizedBox(height: 6),
                  statLine(
                    'Série actuelle',
                    '${data.currentStreak} jour${data.currentStreak > 1 ? "s" : ""}',
                  ),
                ],
              ),
            ),

            pw.SizedBox(height: 24),

            // ===== Section : Statistiques par niveau =====
            pw.Text('Statistiques par niveau', style: sectionTitleStyle),
            pw.SizedBox(height: 8),
            if (data.byLevel.isEmpty)
              pw.Text(
                'Aucune donnée par niveau pour le moment.',
                style: valueStyle,
              )
            else
              pw.TableHelper.fromTextArray(
                headerStyle: pw.TextStyle(font: fontBold, fontSize: 11),
                cellStyle: valueStyle,
                headerDecoration: const pw.BoxDecoration(
                  color: PdfColor.fromInt(0xFFE0E7FF),
                ),
                cellAlignment: pw.Alignment.centerLeft,
                columnWidths: {
                  0: const pw.FlexColumnWidth(3),
                  1: const pw.FlexColumnWidth(2),
                  2: const pw.FlexColumnWidth(2),
                  3: const pw.FlexColumnWidth(2),
                },
                headers: const ['Niveau', 'Bonnes', 'Total', 'Taux'],
                data: data.byLevel
                    .map(
                      (lvl) => [
                        lvl.label,
                        lvl.correct.toString(),
                        lvl.total.toString(),
                        '${lvl.percent} %',
                      ],
                    )
                    .toList(),
              ),

            pw.SizedBox(height: 24),

            // ===== Section : Statistiques par temps =====
            pw.Text('Statistiques par temps', style: sectionTitleStyle),
            pw.SizedBox(height: 8),
            if (data.byTense.isEmpty)
              pw.Text(
                'Aucune donnée par temps pour le moment.',
                style: valueStyle,
              )
            else
              pw.TableHelper.fromTextArray(
                headerStyle: pw.TextStyle(font: fontBold, fontSize: 11),
                cellStyle: valueStyle,
                headerDecoration: const pw.BoxDecoration(
                  color: PdfColor.fromInt(0xFFFFF7CC),
                ),
                cellAlignment: pw.Alignment.centerLeft,
                columnWidths: {
                  0: const pw.FlexColumnWidth(3),
                  1: const pw.FlexColumnWidth(2),
                  2: const pw.FlexColumnWidth(2),
                  3: const pw.FlexColumnWidth(2),
                },
                headers: const ['Temps', 'Correct', 'Incorrect', 'Taux'],
                data: data.byTense
                    .map(
                      (t) => [
                        t.tense,
                        t.correct.toString(),
                        t.wrong.toString(),
                        '${t.percent} %',
                      ],
                    )
                    .toList(),
              ),
          ],
        ),
      );

      // 5. Sauvegarde + partage / ouverture
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/conjufun_stats.pdf');
      await file.writeAsBytes(await pdf.save());

      await OpenFilex.open(file.path);
    } catch (e, st) {
      debugPrint('Erreur lors de l’export PDF : $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur lors de l’export PDF : $e')),
      );
    }
  }

  Future<_StatsData> _loadStats() async {
    final user = await AuthRepo.instance.getCurrentUser();
    final uid = user == null ? null : user['id'] as int;

    String? placementLevelKey;
    int currentStreak = 0;

    if (uid != null) {
      final levelRow = await AppDb.instance.getUserLevelTestResult(uid);
      if (levelRow != null &&
          (levelRow['has_done_level_test'] as int? ?? 0) == 1) {
        final raw = levelRow['last_recommended_level'] as String?;
        placementLevelKey = _normalizePlacementKey(raw);
      }
      final streak = await AppDb.instance.getStreakForUser(uid);
      currentStreak = streak['current'] ?? 0;
    }

    // ---------------- STATS PAR MODE ----------------
    final fixedSummary = await AppDb.instance.getRunsSuccess(
      'fixed',
      userId: uid,
    );
    final unlimitedSummary = await AppDb.instance.getRunsSuccess(
      'unlimited',
      userId: uid,
    );

    final modeStats = <_ModeStats>[
      _ModeStats(
        mode: 'fixed',
        runs: (fixedSummary['runs'] as int? ?? 0),
        correct: (fixedSummary['correct'] as int? ?? 0),
        total: (fixedSummary['total'] as int? ?? 0),
      ),
      _ModeStats(
        mode: 'unlimited',
        runs: (unlimitedSummary['runs'] as int? ?? 0),
        correct: (unlimitedSummary['correct'] as int? ?? 0),
        total: (unlimitedSummary['total'] as int? ?? 0),
      ),
    ];

    // ---------------- STATS PAR NIVEAU ----------------
    final levelMap = <String, _LevelStats>{};

    Future<void> accumulateRunsForMode(String mode) async {
      final rows = await AppDb.instance.getRuns(mode: mode, userId: uid);
      for (final r in rows) {
        final levelKey = (r['level'] as String?) ?? 'inconnu';
        final correct = (r['correct_count'] as int?) ?? 0;
        final total = (r['total_target'] as int?) ?? 0;

        final ls = levelMap.putIfAbsent(
          levelKey,
          () => _LevelStats(levelKey: levelKey),
        );
        ls.runs += 1;
        ls.correct += correct;
        ls.total += total;
      }
    }

    await accumulateRunsForMode('fixed');
    await accumulateRunsForMode('unlimited');

    final levelStats = levelMap.values.toList()
      ..sort((a, b) => a.levelKey.compareTo(b.levelKey));

    // ---------------- STATS PAR TEMPS ----------------
    final tenseRows = await AppDb.instance.getStatsByTense(userId: uid);
    final tenseStats = tenseRows.map((row) {
      final tense = (row['tense'] as String?) ?? '';
      final correct = (row['correct'] as int?) ?? 0;
      final wrong = (row['wrong'] as int?) ?? 0;
      return _TenseStats(tense: tense, correct: correct, wrong: wrong);
    }).toList()..sort((a, b) => a.tense.compareTo(b.tense));

    // ---------------- RECORDS ----------------
    int fixedRecord = 0;
    int unlimitedRecord = 0;
    int globalRecord = 0;

    final fixedRows = await AppDb.instance.getRuns(mode: 'fixed', userId: uid);
    for (final r in fixedRows) {
      final score = (r['score'] as int?) ?? 0;
      if (score > fixedRecord) fixedRecord = score;
    }

    unlimitedRecord = await AppDb.instance.getUnlimitedRecord(userId: uid);

    globalRecord = fixedRecord > unlimitedRecord
        ? fixedRecord
        : unlimitedRecord;

    return _StatsData(
      hasUserId: uid != null,
      byMode: modeStats,
      byLevel: levelStats,
      byTense: tenseStats,
      fixedRecord: fixedRecord,
      unlimitedRecord: unlimitedRecord,
      globalRecord: globalRecord,
      placementLevelKey: placementLevelKey,
      currentStreak: currentStreak,
    );
  }

  String _shortLabelForTense(String tense) {
    switch (tense.toLowerCase()) {
      case 'présent':
      case 'present':
        return 'présent';
      case 'imparfait':
        return 'imparf.';
      case 'futur':
      case 'futur simple':
        return 'futur';
      case 'conditionnel présent':
      case 'conditionnel':
        return 'cond.';
      case 'subjonctif présent':
        return 'subj.';
      case 'subjonctif imparfait':
        return 'subj. imp.';
      case 'passé simple':
        return 'p. simple';
      case 'passé composé':
        return 'p. comp.';
      case 'futur proche':
        return 'futur pr.';
      default:
        return tense.length > 10 ? '${tense.substring(0, 10)}…' : tense;
    }
  }

  String _shortLabelForLevelKey(String key) {
    switch (key) {
      case 'level_cycle1':
        return 'Niv 1';
      case 'level_cycle2':
        return 'Niv 2';
      case 'level_cycle3':
        return 'Niv 3';
      case 'level_sec1':
        return 'Niv 4';
      case 'level_sec2':
        return 'Niv 5';
      case 'expert':
      case 'level_expert':
        return 'Expert';
      default:
        return key;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Tes statistiques',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
              ),
              TextButton.icon(
                onPressed: _exportStatsAsPdf,
                icon: const Icon(Icons.download),
                label: const Text('Exporter'),
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 4),

        Expanded(
          child: RepaintBoundary(
            key: _exportKey,
            child: FutureBuilder<_StatsData>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'Erreur lors du chargement des statistiques :\n${snapshot.error}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  );
                }

                final data = snapshot.data!;
                final byMode = data.byMode;
                final byLevel = data.byLevel;
                final byTense = data.byTense;

                if (byMode.every((m) => m.runs == 0) &&
                    byLevel.isEmpty &&
                    byTense.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'Aucune statistique pour le moment.\n'
                        'Fais d’abord quelques sessions de conjugaison 🙂',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }

                final fixed = byMode.firstWhere(
                  (m) => m.mode == 'fixed',
                  orElse: () =>
                      _ModeStats(mode: 'fixed', runs: 0, correct: 0, total: 0),
                );
                final unlimited = byMode.firstWhere(
                  (m) => m.mode == 'unlimited',
                  orElse: () => _ModeStats(
                    mode: 'unlimited',
                    runs: 0,
                    correct: 0,
                    total: 0,
                  ),
                );

                final width = MediaQuery.of(context).size.width;
                final isSmall = width < 650;

                if (isSmall) {
                  // --- Version petit écran ---
                  Widget section;
                  switch (_selectedSectionIndex) {
                    case 1:
                      section = _buildLevelTab(byLevel, data.placementLevelKey);
                      break;
                    case 2:
                      section = _buildTenseTab(byTense);
                      break;
                    case 0:
                    default:
                      section = _buildGeneralTab(
                        fixed: fixed,
                        unlimited: unlimited,
                        fixedRecord: data.fixedRecord,
                        unlimitedRecord: data.unlimitedRecord,
                        globalRecord: data.globalRecord,
                        currentStreak: data.currentStreak,
                      );
                  }

                  return Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: DropdownButtonFormField<int>(
                            initialValue: _selectedSectionIndex,
                            decoration: InputDecoration(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              filled: true,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide(
                                  color: Colors.grey.shade300,
                                ),
                              ),
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 0,
                                child: Text('Statistiques générales'),
                              ),
                              DropdownMenuItem(
                                value: 1,
                                child: Text('Statistiques par niveau'),
                              ),
                              DropdownMenuItem(
                                value: 2,
                                child: Text('Statistiques par temps'),
                              ),
                            ],
                            onChanged: (val) {
                              if (val == null) return;
                              setState(() {
                                _selectedSectionIndex = val;
                              });
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Expanded(child: section),
                    ],
                  );
                }

                // --- Version grand écran ---
                return DefaultTabController(
                  length: 3,
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: const Align(
                          alignment: Alignment.centerLeft,
                          child: TabBar(
                            isScrollable: true,
                            indicatorColor: brandYellow,
                            labelColor: brandYellow,
                            unselectedLabelColor: Colors.grey,
                            labelStyle: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                            tabs: [
                              Tab(text: 'Statistiques générales'),
                              Tab(text: 'Statistiques par niveau'),
                              Tab(text: 'Statistiques par temps'),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Expanded(
                        child: TabBarView(
                          children: [
                            _buildGeneralTab(
                              fixed: fixed,
                              unlimited: unlimited,
                              fixedRecord: data.fixedRecord,
                              unlimitedRecord: data.unlimitedRecord,
                              globalRecord: data.globalRecord,
                              currentStreak: data.currentStreak,
                            ),
                            _buildLevelTab(byLevel, data.placementLevelKey),
                            _buildTenseTab(byTense),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  // =================== Onglet "Statistiques générales" ===================

  Widget _buildGeneralTab({
    required _ModeStats fixed,
    required _ModeStats unlimited,
    required int fixedRecord,
    required int unlimitedRecord,
    required int globalRecord,
    required int currentStreak,
  }) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 800),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            _buildGeneralStatsSection(
              fixed: fixed,
              unlimited: unlimited,
              fixedRecord: fixedRecord,
              unlimitedRecord: unlimitedRecord,
              globalRecord: globalRecord,
              currentStreak: currentStreak,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGeneralStatsSection({
    required _ModeStats fixed,
    required _ModeStats unlimited,
    required int fixedRecord,
    required int unlimitedRecord,
    required int globalRecord,
    required int currentStreak,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Ligne sessions fixes / illimitées
        Row(
          children: [
            Expanded(
              child: _smallStatCard(
                icon: Icons.check_box_outlined,
                title: 'Sessions fixes',
                value: fixed.runs.toString(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _smallStatCard(
                icon: Icons.all_inclusive,
                title: 'Sessions illimitées',
                value: unlimited.runs.toString(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // Ligne records
        Row(
          children: [
            Expanded(
              child: _smallStatCard(
                icon: Icons.star_border,
                title: 'Record mode fixe',
                value: fixedRecord.toString(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _smallStatCard(
                icon: Icons.flash_on_outlined,
                title: 'Record illimité',
                value: unlimitedRecord.toString(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // Record global + streak courant
        Row(
          children: [
            Expanded(
              child: _smallStatCard(
                icon: Icons.workspace_premium,
                title: 'Record global du jeu',
                value: globalRecord.toString(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _smallStatCard(
                icon: Icons.local_fire_department_outlined,
                title: 'Série actuelle',
                value: '$currentStreak j',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Jauge % fixe
        Card(
          elevation: 2,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Taux de bonnes réponses en mode fixe',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: LinearProgressIndicator(
                    value: (fixed.percent.clamp(0, 100)) / 100,
                    minHeight: 12,
                    backgroundColor: brandBlue.withValues(alpha: .12),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      brandYellow,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${fixed.percent} % de bonnes réponses en mode fixe',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _smallStatCard({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return Card(
      elevation: 2,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: brandYellow.withValues(alpha: .18),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: Theme.of(context).colorScheme.primary,
                size: 22,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _smallHighlightCard({
    required String label,
    required String tenseLabel,
    required int percent,
    required IconData icon,
    required Color iconColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: context.softPanel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$tenseLabel • $percent %',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // =================== Tab "Stats par niveau" ===================

  Widget _buildLevelTab(List<_LevelStats> byLevel, String? placementLevelKey) {
    if (byLevel.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Aucune statistique par niveau pour le moment.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    // Niveau actuel (test de niveau)
    String? placementLabel;
    if (placementLevelKey != null) {
      final matches = byLevel
          .where((lvl) => lvl.levelKey == placementLevelKey)
          .toList();
      if (matches.isNotEmpty) {
        placementLabel = matches.first.label;
      } else {
        placementLabel = _shortLabelForLevelKey(placementLevelKey);
      }
    }

    // Niveau le plus fort / à travailler
    _LevelStats? best;
    _LevelStats? weakest;
    for (final lvl in byLevel) {
      if (lvl.total == 0) continue;
      if (best == null || lvl.percent > best.percent) best = lvl;
      if (weakest == null || lvl.percent < weakest.percent) weakest = lvl;
    }

    Widget levelListCard = Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Statistiques par niveau',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            const SizedBox(height: 8),
            const Text(
              'Performance globale par niveau scolaire (tous les modes confondus).',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 16),
            for (final lvl in byLevel)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          lvl.label,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          '${lvl.percent} %',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: lvl.total == 0 ? 0 : lvl.percent / 100.0,
                        minHeight: 10,
                        backgroundColor: Colors.grey.withValues(alpha: 0.2),
                        valueColor: const AlwaysStoppedAnimation(brandYellow),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${lvl.correct} bonnes réponses '
                      'sur ${lvl.total} questions '
                      '(${lvl.runs} session${lvl.runs > 1 ? "s" : ""})',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );

    Widget levelChartCard = Card(
      elevation: 2,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
        child: SizedBox(
          height: 260,
          child: byLevel.isEmpty
              ? const Center(child: Text('Pas encore de données par niveau.'))
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Vue d’ensemble par niveau',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: BarChart(
                        BarChartData(
                          maxY: 100,
                          minY: 0,
                          gridData: FlGridData(
                            show: true,
                            drawVerticalLine: false,
                            getDrawingHorizontalLine: (value) {
                              return FlLine(
                                color: Colors.grey.withValues(alpha: .25),
                                strokeWidth: 1,
                                dashArray: [4, 4],
                              );
                            },
                          ),
                          borderData: FlBorderData(show: false),
                          titlesData: FlTitlesData(
                            topTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false),
                            ),
                            rightTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false),
                            ),
                            leftTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 30,
                                interval: 25,
                                getTitlesWidget: (value, meta) {
                                  if (value % 25 != 0) {
                                    return const SizedBox.shrink();
                                  }
                                  return Text(
                                    '${value.toInt()}%',
                                    style: const TextStyle(fontSize: 11),
                                  );
                                },
                              ),
                            ),
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                getTitlesWidget: (value, meta) {
                                  final index = value.toInt();
                                  if (index < 0 || index >= byLevel.length) {
                                    return const SizedBox.shrink();
                                  }
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      _shortLabelForLevelKey(
                                        byLevel[index].levelKey,
                                      ),
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                          barGroups: List.generate(byLevel.length, (i) {
                            final lvl = byLevel[i];
                            return BarChartGroupData(
                              x: i,
                              barRods: [
                                BarChartRodData(
                                  toY: lvl.percent.toDouble(),
                                  width: 18,
                                  borderRadius: BorderRadius.circular(8),
                                  color: brandYellow,
                                  borderSide: BorderSide(
                                    color: brandBlue.withValues(alpha: .7),
                                    width: 1.5,
                                  ),
                                ),
                              ],
                            );
                          }),
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 900;

        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (placementLabel != null)
                    Card(
                      elevation: 2,
                      surfaceTintColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: brandBlue.withValues(alpha: .08),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Icon(
                                Icons.gamepad_outlined,
                                color: brandBlue,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Niveau actuel (test de niveau)',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    placementLabel,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  if (placementLabel != null) const SizedBox(height: 12),

                  if (best != null && weakest != null)
                    Card(
                      elevation: 2,
                      surfaceTintColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Niveau le plus fort 💪',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${best.label} – ${best.percent} %',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Niveau à travailler 🎯',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${weakest.label} – ${weakest.percent} %',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  if (best != null && weakest != null)
                    const SizedBox(height: 12),

                  if (isWide)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 3, child: levelListCard),
                        const SizedBox(width: 16),
                        Expanded(flex: 2, child: levelChartCard),
                      ],
                    )
                  else ...[
                    levelListCard,
                    const SizedBox(height: 16),
                    levelChartCard,
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // =================== Tab "Stats par temps" ===================

  Widget _buildTenseTab(List<_TenseStats> byTense) {
    if (byTense.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Aucune statistique par temps pour le moment.\n'
            'Fais quelques exercices pour voir ta performance par temps.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final validTenses = byTense.where((t) => t.total >= 5).toList();
    validTenses.sort((a, b) => b.percent.compareTo(a.percent));

    // Meilleur & pire
    _TenseStats? best = validTenses.isNotEmpty ? validTenses.first : null;
    _TenseStats? weakest = validTenses.isNotEmpty ? validTenses.last : null;
    final topFive = validTenses.take(5).toList();

    // --- Tenses restants pour "voir plus" ---
    final rest = byTense.where((t) => !topFive.contains(t)).toList()
      ..sort((a, b) => a.percent.compareTo(b.percent));

    bool showAll = false;

    return StatefulBuilder(
      builder: (context, setState) {
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                // ---- Résumé : temps fort / temps à travailler ----
                if (best != null && weakest != null)
                  Card(
                    elevation: 2,
                    surfaceTintColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Résumé par temps',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Les temps où tu performes le mieux et ceux à travailler davantage.',
                            style: TextStyle(fontSize: 13),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _smallHighlightCard(
                                  label: 'Temps le plus fort',
                                  tenseLabel: _shortLabelForTense(best.tense),
                                  percent: best.percent,
                                  icon: Icons.trending_up,
                                  iconColor: Colors.green,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _smallHighlightCard(
                                  label: 'Temps à travailler',
                                  tenseLabel: _shortLabelForTense(
                                    weakest.tense,
                                  ),
                                  percent: weakest.percent,
                                  icon: Icons.flag_outlined,
                                  iconColor: Colors.orange,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                const SizedBox(height: 12),

                // ---- Graphique top 5 ----
                Card(
                  elevation: 2,
                  surfaceTintColor: Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                    child: SizedBox(
                      height: 260,
                      child: topFive.isEmpty
                          ? const Center(child: Text('Pas assez de données.'))
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Top 5 des temps maîtrisés',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Expanded(
                                  child: BarChart(
                                    BarChartData(
                                      maxY: 100,
                                      minY: 0,
                                      gridData: FlGridData(
                                        show: true,
                                        drawVerticalLine: false,
                                        getDrawingHorizontalLine: (value) {
                                          return FlLine(
                                            color: Colors.grey.withValues(
                                              alpha: .25,
                                            ),
                                            strokeWidth: 1,
                                            dashArray: [4, 4],
                                          );
                                        },
                                      ),
                                      borderData: FlBorderData(show: false),
                                      titlesData: FlTitlesData(
                                        topTitles: const AxisTitles(
                                          sideTitles: SideTitles(
                                            showTitles: false,
                                          ),
                                        ),
                                        rightTitles: const AxisTitles(
                                          sideTitles: SideTitles(
                                            showTitles: false,
                                          ),
                                        ),
                                        leftTitles: AxisTitles(
                                          sideTitles: SideTitles(
                                            showTitles: true,
                                            reservedSize: 30,
                                            interval: 25,
                                            getTitlesWidget: (value, meta) {
                                              if (value % 25 != 0) {
                                                return const SizedBox.shrink();
                                              }
                                              return Text(
                                                '${value.toInt()}%',
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                ),
                                              );
                                            },
                                          ),
                                        ),
                                        bottomTitles: AxisTitles(
                                          sideTitles: SideTitles(
                                            showTitles: true,
                                            getTitlesWidget: (value, meta) {
                                              final index = value.toInt();
                                              if (index < 0 ||
                                                  index >= topFive.length) {
                                                return const SizedBox.shrink();
                                              }
                                              return Padding(
                                                padding: const EdgeInsets.only(
                                                  top: 4,
                                                ),
                                                child: Text(
                                                  _shortLabelForTense(
                                                    topFive[index].tense,
                                                  ),
                                                  style: const TextStyle(
                                                    fontSize: 11,
                                                  ),
                                                ),
                                              );
                                            },
                                          ),
                                        ),
                                      ),
                                      barGroups: List.generate(topFive.length, (
                                        i,
                                      ) {
                                        final t = topFive[i];
                                        return BarChartGroupData(
                                          x: i,
                                          barRods: [
                                            BarChartRodData(
                                              toY: t.percent.toDouble(),
                                              width: 18,
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              color: brandBlue,
                                              borderSide: BorderSide(
                                                color: brandYellow.withValues(
                                                  alpha: .8,
                                                ),
                                                width: 1.5,
                                              ),
                                            ),
                                          ],
                                        );
                                      }),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // ---- Liste détaillée ----
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Détail par temps',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 12),

                        // --- top 5 visibles en premier ---
                        for (final t in topFive) _buildTenseRow(t),

                        const SizedBox(height: 8),

                        // --- Voir plus / Voir moins ---
                        if (!showAll && rest.isNotEmpty)
                          TextButton(
                            onPressed: () => setState(() => showAll = true),
                            child: const Text('Voir plus'),
                          ),

                        if (showAll)
                          Column(
                            children: [
                              for (final t in rest) _buildTenseRow(t),
                              TextButton(
                                onPressed: () =>
                                    setState(() => showAll = false),
                                child: const Text('Voir moins'),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // widget ligne détaillée pour un temps
  Widget _buildTenseRow(_TenseStats t) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _shortLabelForTense(t.tense),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              Text(
                '${t.percent}% (${t.total} réponses)',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: t.total == 0 ? 0 : t.percent / 100.0,
              minHeight: 10,
              backgroundColor: Colors.grey.withValues(alpha: 0.2),
              valueColor: AlwaysStoppedAnimation<Color>(
                Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
