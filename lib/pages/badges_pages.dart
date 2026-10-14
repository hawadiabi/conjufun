import 'package:flutter/material.dart';
import '../data/auth_repo.dart';
import '../session_notifier.dart';
import '../ui/app_colors.dart';
import '../main.dart' show brandBlue, brandYellow;
import '../data/app_db.dart';
import '../data/badge_catalog.dart';

class BadgesPage extends StatefulWidget {
  const BadgesPage({super.key});

  @override
  State<BadgesPage> createState() => _BadgesPageState();
}

class _BadgesPageState extends State<BadgesPage> {
  bool _loading = true;
  Set<String> _unlockedCodes = {};

  // Profil joueur
  int _globalScore = 0;
  int _streak = 0;
  bool _isGuest = false;

  @override
  void initState() {
    super.initState();
    appStateChanged.addListener(_loadBadgesAndProfile);
    _loadBadgesAndProfile();
  }

  @override
  void dispose() {
    appStateChanged.removeListener(_loadBadgesAndProfile);
    super.dispose();
  }

  Future<void> _loadBadgesAndProfile() async {
    final user = await AuthRepo.instance.getCurrentUser();
    final userId = user == null ? null : user['id'] as int;

    if (userId == null) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _isGuest = true;
        _unlockedCodes = {};
        _globalScore = 0;
        _streak = 0;
      });
      return;
    }

    // --- Badges débloqués ---
    final rows = await AppDb.instance.getBadgesForUser(userId);
    final codes = rows
        .map((row) => (row['code'] as String?) ?? '')
        .where((c) => c.isNotEmpty)
        .toSet();

    // --- Profil joueur (global) ---
    final fixedRows = await AppDb.instance.getRuns(
      mode: 'fixed',
      userId: userId,
    );
    final unlimitedRows = await AppDb.instance.getRuns(
      mode: 'unlimited',
      userId: userId,
    );

    final fixedScoreSum = fixedRows.fold<int>(
      0,
      (s, r) => s + ((r['score'] ?? 0) as num).toInt(),
    );
    final unlimitedScoreSum = unlimitedRows.fold<int>(
      0,
      (s, r) => s + ((r['score'] ?? 0) as num).toInt(),
    );

    final globalScore = fixedScoreSum + unlimitedScoreSum;

    // Streak global
    final streak = await AppDb.instance.getStreakForUser(userId);
    final current = streak['current'] ?? 0;

    if (!mounted) return;
    setState(() {
      _isGuest = false;
      _unlockedCodes = codes;
      _globalScore = globalScore;
      _streak = current;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Badges'),
        backgroundColor: brandBlue,
        foregroundColor: Colors.white,
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: context.pageGradient,
                ),
              ),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: [
                  if (_isGuest) ...[
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            const Icon(Icons.info_outline),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Text(
                                'Les badges et les rangs sont réservés aux comptes. '
                                'Crée un compte ou connecte-toi : tes parties '
                                'd’invité seront rattachées automatiquement.',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final isWide = constraints.maxWidth >= 720;
                      if (isWide) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 380,
                                ),
                                child: _buildBadgesHeaderCard(),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(child: _buildPlayerHeader()),
                          ],
                        );
                      } else {
                        return Column(
                          children: [
                            Center(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 380,
                                ),
                                child: _buildBadgesHeaderCard(),
                              ),
                            ),
                            const SizedBox(height: 16),
                            _buildPlayerHeader(),
                          ],
                        );
                      }
                    },
                  ),

                  const SizedBox(height: 20),

                  _buildCategorySection(
                    context,
                    title: 'Badges – réponses correctes',
                    category: BadgeCategory.correctAnswers,
                  ),
                  const SizedBox(height: 16),
                  _buildCategorySection(
                    context,
                    title: 'Badges – sessions jouées',
                    category: BadgeCategory.sessions,
                  ),
                  const SizedBox(height: 16),
                  _buildCategorySection(
                    context,
                    title: 'Badges – rangs atteints',
                    category: BadgeCategory.rank,
                  ),
                  const SizedBox(height: 16),
                  _buildCategorySection(
                    context,
                    title: 'Badges – streaks de jours',
                    category: BadgeCategory.streak,
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildPlayerHeader() {
    final int score = _globalScore;

    final rank = rankForScore(score);
    final currentStep = rank.current;
    final double progress = rank.fraction;
    final String progressText = rank.isMax
        ? 'Tu as atteint le rang maximal 🎉 Continue à jouer pour rester au top !'
        : 'Encore ${rank.remaining} pts avant "${rank.next!.name}".';

    return Card(
      elevation: 3,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final bool isCompact = constraints.maxWidth < 380;

            // --- VERSION COMPACTE (mobile étroit) ---
            if (isCompact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: brandYellow.withValues(alpha: .2),
                        child: const Text('🎮', style: TextStyle(fontSize: 24)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Rang actuel : ${currentStep.name}',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Score cumulé : $score pts',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Progression vers le prochain rang',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 8,
                      backgroundColor: brandBlue.withValues(alpha: .12),
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        brandYellow,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(progressText, style: const TextStyle(fontSize: 11)),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: context.cardBackground.withValues(alpha: .9),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.local_fire_department,
                            color: Colors.orange,
                            size: 16,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Série : $_streak j',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            }

            // --- VERSION LARGE (tablette / desktop / mobile large) ---
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: brandYellow.withValues(alpha: .2),
                  child: Text(
                    '🎮',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Rang actuel : ${currentStep.name}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Score cumulé : $score pts',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Progression vers le prochain rang',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 10,
                          backgroundColor: brandBlue.withValues(alpha: .12),
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            brandYellow,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(progressText, style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Streak global
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: context.cardBackground.withValues(alpha: .9),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.local_fire_department,
                        color: Colors.orange,
                        size: 18,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Série : $_streak j',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  // --- Carte "Tes badges" ---
  Widget _buildBadgesHeaderCard() {
    final unlockedCount = _unlockedCodes.length;
    final total = kBadgeCatalog.length;

    return Card(
      elevation: 2,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: brandYellow.withValues(alpha: .2),
              child: const Text('🏅', style: TextStyle(fontSize: 26)),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Tes badges',
                    style: Theme.of(context).textTheme.titleMedium!.copyWith(
                      fontWeight: FontWeight.w800,
                      color: brandBlue,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$unlockedCount / $total débloqués',
                    style: TextStyle(
                      color: context.mutedText,
                      fontWeight: FontWeight.w500,
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

  Widget _buildCategorySection(
    BuildContext context, {
    required String title,
    required BadgeCategory category,
  }) {
    final badges = kBadgeCatalog.where((b) => b.category == category).toList();

    if (badges.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium!.copyWith(
            fontWeight: FontWeight.w800,
            color: brandBlue,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: badges.map((b) => _buildBadgeCard(context, b)).toList(),
        ),
      ],
    );
  }

  Widget _buildBadgeCard(BuildContext context, BadgeDefinition badge) {
    final unlocked = _unlockedCodes.contains(badge.code);

    final Color baseColor = unlocked
        ? context.cardBackground
        : (context.isDarkMode ? Colors.grey.shade800 : Colors.grey.shade200);
    final Color borderColor = unlocked
        ? brandYellow.withValues(alpha: .8)
        : Colors.grey.shade400;
    final Color textColor = unlocked
        ? Theme.of(context).colorScheme.onSurface
        : Colors.grey.shade500;
    final emoji = unlocked ? badge.emoji : '🔒';

    return SizedBox(
      width: 185,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _showBadgeDetails(badge, unlocked),
        child: Card(
          elevation: unlocked ? 3 : 0,
          color: baseColor,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: borderColor),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Opacity(
              opacity: unlocked ? 1.0 : 0.6,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(emoji, style: const TextStyle(fontSize: 20)),
                      const Spacer(),
                      if (unlocked)
                        const Icon(
                          Icons.check_circle,
                          size: 18,
                          color: Colors.green,
                        )
                      else
                        const Icon(Icons.lock_outline, size: 18),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    badge.title,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    badge.description,
                    style: TextStyle(
                      fontSize: 11,
                      color: textColor.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showBadgeDetails(BadgeDefinition badge, bool unlocked) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        final condition = badge.condition;
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Text(badge.emoji, style: const TextStyle(fontSize: 40)),
              ),
              const SizedBox(height: 8),
              Text(
                badge.title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(badge.description, style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(
                    unlocked ? Icons.check_circle : Icons.lock_outline,
                    color: unlocked ? Colors.green : Colors.grey,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    unlocked ? 'Badge débloqué 🎉' : 'Badge verrouillé',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'Comment débloquer ce badge ?',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
              const SizedBox(height: 4),
              Text(condition, style: const TextStyle(fontSize: 13)),
            ],
          ),
        );
      },
    );
  }
}
