import 'package:flutter/material.dart';
import '../data/auth_repo.dart';
import '../session_notifier.dart';

import '../ui/app_colors.dart';
import '../main.dart' show routeObserver;
import '../data/app_db.dart';
import '../config/levels_config.dart' show levelLabelFromKey;
import '../main.dart' show brandBlue, brandYellow;

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> with RouteAware {
  bool _loading = true;
  List<Map<String, dynamic>> _fixedRuns = [];
  List<Map<String, dynamic>> _unlimitedRuns = [];

  @override
  void initState() {
    super.initState();
    // Page gardée en vie : se recharge quand le compte ou les données changent.
    appStateChanged.addListener(_loadHistory);
    _loadHistory();
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
    appStateChanged.removeListener(_loadHistory);
    routeObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPopNext() {
    _loadHistory();
  }

  Future<void> reloadHistory() async {
    await _loadHistory();
  }

  Future<void> _loadHistory() async {
    if (!mounted) return;
    setState(() => _loading = true);

    try {
      final user = await AuthRepo.instance.getCurrentUser();
      final uid = user == null ? null : user['id'] as int;

      final fixedRows = await AppDb.instance.getRuns(
        mode: 'fixed',
        userId: uid,
      );
      final fixedRuns = List<Map<String, dynamic>>.from(fixedRows);

      final unlimitedRows = await AppDb.instance.getRuns(
        mode: 'unlimited',
        userId: uid,
      );
      final unlimitedRuns = List<Map<String, dynamic>>.from(unlimitedRows);

      int startedAt(Map<String, dynamic> r) =>
          ((r['started_at'] ?? 0) as num).toInt();

      fixedRuns.sort((a, b) => startedAt(b).compareTo(startedAt(a)));
      unlimitedRuns.sort((a, b) => startedAt(b).compareTo(startedAt(a)));

      if (!mounted) return;
      setState(() {
        _fixedRuns = fixedRuns;
        _unlimitedRuns = unlimitedRuns;
        _loading = false;
      });
    } catch (e, st) {
      debugPrint('History load error: $e\n$st');
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur de lecture de l’historique: $e')),
      );
    }
  }

  String _formatDate(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year} à ${two(d.hour)}:${two(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: brandBlue,
          foregroundColor: Colors.white,
          elevation: 0,
          title: const Text(
            'Historique des parties',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          bottom: const TabBar(
            indicatorColor: brandYellow,
            indicatorWeight: 3,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: [
              Tab(text: 'Fixe'),
              Tab(text: 'Illimité'),
            ],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                children: [
                  _buildRunsList(_fixedRuns, isFixed: true),
                  _buildRunsList(_unlimitedRuns, isFixed: false),
                ],
              ),
      ),
    );
  }

  Widget _buildRunsList(
    List<Map<String, dynamic>> runs, {
    required bool isFixed,
  }) {
    if (runs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.history_rounded,
                size: 56,
                color: brandBlue.withValues(alpha: .7),
              ),
              const SizedBox(height: 12),
              Text(
                isFixed
                    ? 'Aucune session fixe enregistrée.'
                    : 'Aucune session illimitée enregistrée.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Lance une nouvelle partie pour remplir ton historique 🎮',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: context.mutedText),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      itemCount: runs.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final r = runs[index];

        final levelKey = (r['level'] as String?) ?? 'level_cycle1';
        final levelLabel = levelLabelFromKey(levelKey);

        final modeLabel = isFixed ? 'Fixe' : 'Illimité';

        final startedMs = ((r['started_at'] ?? 0) as num).toInt();
        final date = DateTime.fromMillisecondsSinceEpoch(startedMs);

        final score = ((r['score'] ?? 0) as num).toInt();
        final correct = ((r['correct_count'] ?? 0) as num).toInt();
        final total = ((r['total_target'] ?? 0) as num).toInt();
        final pct = total <= 0 ? 0 : ((correct * 100) / total).round();

        // Couleurs selon mode
        final Color stripeColor = isFixed
            ? brandYellow
            : brandBlue.withValues(alpha: .7);
        final Color avatarBg = isFixed
            ? brandYellow.withValues(alpha: .20)
            : brandBlue.withValues(alpha: .10);

        return Align(
          alignment: Alignment.center,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Card(
              elevation: 3,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        width: 4,
                        decoration: BoxDecoration(
                          color: stripeColor,
                          borderRadius: const BorderRadius.horizontal(
                            left: Radius.circular(16),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        CircleAvatar(
                          radius: 24,
                          backgroundColor: avatarBg,
                          child: isFixed
                              ? Text(
                                  '$pct%',
                                  style: const TextStyle(
                                    color: brandBlue,
                                    fontWeight: FontWeight.w800,
                                  ),
                                )
                              : const Icon(Icons.flash_on, color: brandBlue),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '$modeLabel • $levelLabel',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 15,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: brandYellow.withValues(alpha: .85),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      'Score $score',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: brandBlue,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _formatDate(date),
                                style: TextStyle(
                                  fontSize: 13,
                                  color: context.mutedText,
                                ),
                              ),
                              const SizedBox(height: 6),
                              if (isFixed) ...[
                                Row(
                                  children: [
                                    Expanded(
                                      child: LinearProgressIndicator(
                                        value: total <= 0
                                            ? 0
                                            : (correct / total).clamp(0.0, 1.0),
                                        minHeight: 6,
                                        backgroundColor: brandBlue.withValues(
                                          alpha: .08,
                                        ),
                                        valueColor:
                                            const AlwaysStoppedAnimation(
                                              brandYellow,
                                            ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '$correct / $total',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ] else ...[
                                Text(
                                  'Score total de la session : $score pts',
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
