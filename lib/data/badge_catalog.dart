// lib/data/badge_catalog.dart
//
// unique source de vérité pour les badges et les rangs.
// Le ViewModel (déblocage), la page Badges (affichage) et l'écran de fin de
// partie (rang actuel) lisent tous cette liste : un seuil ne se change qu'ici.

enum BadgeKind { correct, sessions, score, streak }

enum BadgeCategory { correctAnswers, sessions, rank, streak }

class BadgeDefinition {
  final String code;
  final BadgeKind kind;

  /// Valeur à atteindre (réponses, sessions, points ou jours selon [kind]).
  final int threshold;
  final String emoji;
  final String title;
  final String description;

  /// Message affiché quand le badge vient d'être débloqué.
  final String message;

  const BadgeDefinition({
    required this.code,
    required this.kind,
    required this.threshold,
    required this.emoji,
    required this.title,
    required this.description,
    required this.message,
  });

  BadgeCategory get category {
    switch (kind) {
      case BadgeKind.correct:
        return BadgeCategory.correctAnswers;
      case BadgeKind.sessions:
        return BadgeCategory.sessions;
      case BadgeKind.score:
        return BadgeCategory.rank;
      case BadgeKind.streak:
        return BadgeCategory.streak;
    }
  }

  /// Texte « Comment débloquer ce badge ? » généré à partir du seuil.
  String get condition {
    final n = formatNumber(threshold);
    switch (kind) {
      case BadgeKind.correct:
        return 'Répondre correctement à au moins $n questions.';
      case BadgeKind.sessions:
        return 'Jouer au moins $n sessions (tous modes confondus).';
      case BadgeKind.score:
        return 'Atteindre au moins $n pts de score cumulé.';
      case BadgeKind.streak:
        return 'Jouer au moins $n jours consécutifs.';
    }
  }
}

String formatNumber(int n) {
  final s = n.toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
    buf.write(s[i]);
  }
  return buf.toString();
}

const List<BadgeDefinition> kBadgeCatalog = [
  // --- Réponses correctes cumulées ---
  BadgeDefinition(
    code: 'correct_10',
    kind: BadgeKind.correct,
    threshold: 10,
    emoji: '🎯',
    title: '10 réponses correctes',
    description: 'Premiers pas 🎯',
    message: '🎯 10 réponses correctes, nouveau badge débloqué !',
  ),
  BadgeDefinition(
    code: 'correct_50',
    kind: BadgeKind.correct,
    threshold: 50,
    emoji: '🏅',
    title: '50 réponses correctes',
    description: 'Tu prends le rythme !',
    message: '🏅 50 réponses correctes, nouveau badge débloqué !',
  ),
  BadgeDefinition(
    code: 'correct_100',
    kind: BadgeKind.correct,
    threshold: 100,
    emoji: '🏅',
    title: '100 réponses correctes',
    description: 'De plus en plus fort·e !',
    message: '🏅 100 réponses correctes, nouveau badge débloqué !',
  ),
  BadgeDefinition(
    code: 'correct_200',
    kind: BadgeKind.correct,
    threshold: 200,
    emoji: '🥇',
    title: '200 réponses correctes',
    description: 'Une puissance grammaticale !',
    message: '🥇 200 réponses correctes, incroyable progrès !',
  ),
  BadgeDefinition(
    code: 'correct_500',
    kind: BadgeKind.correct,
    threshold: 500,
    emoji: '🔥',
    title: '500 réponses correctes',
    description: 'Légende des verbes 💥',
    message: '🔥 500 réponses correctes, badge ultra rare débloqué !',
  ),

  // --- Sessions jouées ---
  BadgeDefinition(
    code: 'sessions_5',
    kind: BadgeKind.sessions,
    threshold: 5,
    emoji: '📚',
    title: '5 sessions jouées',
    description: 'Tu t’entraînes régulièrement !',
    message: '📚 5 sessions jouées, nouveau badge !',
  ),
  BadgeDefinition(
    code: 'sessions_20',
    kind: BadgeKind.sessions,
    threshold: 20,
    emoji: '📘',
    title: '20 sessions jouées',
    description: 'Une belle habitude !',
    message: '📘 20 sessions jouées, badge débloqué !',
  ),
  BadgeDefinition(
    code: 'sessions_50',
    kind: BadgeKind.sessions,
    threshold: 50,
    emoji: '📗',
    title: '50 sessions jouées',
    description: 'Tu es très constant·e !',
    message: '📗 50 sessions jouées, bravo !',
  ),

  // --- Rangs (score cumulé) ---
  BadgeDefinition(
    code: 'rank_1',
    kind: BadgeKind.score,
    threshold: 1000,
    emoji: '📘',
    title: 'Apprenti·e des verbes',
    description: 'Tu débutes ton aventure grammaticale.',
    message: '📘 Nouveau rang : Apprenti·e des verbes !',
  ),
  BadgeDefinition(
    code: 'rank_2',
    kind: BadgeKind.score,
    threshold: 5000,
    emoji: '📗',
    title: 'Conjugueur·se prometteur·se',
    description: 'Ton niveau monte en flèche !',
    message: '📗 Nouveau rang : Conjugueur·se prometteur·se !',
  ),
  BadgeDefinition(
    code: 'rank_3',
    kind: BadgeKind.score,
    threshold: 15000,
    emoji: '📙',
    title: 'Expert·e du français',
    description: 'Tu maîtrises de plus en plus de temps.',
    message: '📙 Nouveau rang : Expert·e du français !',
  ),
  BadgeDefinition(
    code: 'rank_4',
    kind: BadgeKind.score,
    threshold: 30000,
    emoji: '📕',
    title: 'Maître des conjugaisons',
    description: 'Une maîtrise exceptionnelle !',
    message: '📕 Nouveau rang : Maître des conjugaisons !',
  ),
  BadgeDefinition(
    code: 'rank_5',
    kind: BadgeKind.score,
    threshold: 50000,
    emoji: '📚✨',
    title: 'Grand Sage de la Langue Française',
    description: 'Le rang ultime. Respect éternel.',
    message: '📚✨ Nouveau rang : Grand Sage de la Langue Française !',
  ),

  // --- Séries de jours consécutifs ---
  BadgeDefinition(
    code: 'streak_3',
    kind: BadgeKind.streak,
    threshold: 3,
    emoji: '🔥',
    title: '🔥 Petit feu',
    description: 'Tu as joué 3 jours de suite. La flamme est allumée 🔥',
    message: '🔥 Nouveau badge : "Petit feu" (3 jours consécutifs).',
  ),
  BadgeDefinition(
    code: 'streak_7',
    kind: BadgeKind.streak,
    threshold: 7,
    emoji: '📅',
    title: '📅 Une semaine complète',
    description:
        "Tu as joué 7 jours d'affilée. Une semaine entière de conjugaison 👏",
    message: '📅 Nouveau badge : "Une semaine complète" (7 jours).',
  ),
  BadgeDefinition(
    code: 'streak_14',
    kind: BadgeKind.streak,
    threshold: 14,
    emoji: '⏳',
    title: '⏳ Deux semaines disciplinées',
    description: "14 jours d'affilée. Ta discipline fait peur aux verbes 😎",
    message: '⏳ Nouveau badge : "Deux semaines disciplinées" (14 jours).',
  ),
  BadgeDefinition(
    code: 'streak_30',
    kind: BadgeKind.streak,
    threshold: 30,
    emoji: '🌟',
    title: '🌟 Machine à conjugaison',
    description:
        "30 jours de suite. On ne sait plus si c'est toi ou l'app qui t'utilise.",
    message: '🌟 Nouveau badge : "Machine à conjugaison" (30 jours).',
  ),
  BadgeDefinition(
    code: 'streak_90',
    kind: BadgeKind.streak,
    threshold: 90,
    emoji: '👑',
    title: '👑 Roi/Reine des verbes',
    description: '90 jours consécutifs. À ce stade, tu ES la conjugaison.',
    message: '👑 Nouveau badge : "Roi/Reine des verbes" (90 jours).',
  ),
];

// ---------------------------------------------------------------------------
// Rangs (dérivés des badges de type score : aucun seuil n'est répété)
// ---------------------------------------------------------------------------

class RankStep {
  final int minScore;
  final String name;
  const RankStep(this.minScore, this.name);
}

/// Rang de départ + un rang par badge « score ».
final List<RankStep> kRankSteps = [
  const RankStep(0, 'Début du parcours'),
  for (final b in kBadgeCatalog)
    if (b.kind == BadgeKind.score) RankStep(b.threshold, b.title),
];

/// Situation d'un joueur sur l'échelle des rangs.
class RankProgress {
  final RankStep current;

  /// null si le rang maximum est atteint.
  final RankStep? next;

  /// Points restants avant le rang suivant (0 au rang maximum).
  final int remaining;

  /// Avancement de 0.0 à 1.0 entre le rang actuel et le suivant.
  final double fraction;

  const RankProgress({
    required this.current,
    required this.next,
    required this.remaining,
    required this.fraction,
  });

  bool get isMax => next == null;
}

RankProgress rankForScore(int score) {
  var index = 0;
  for (var i = 0; i < kRankSteps.length; i++) {
    if (score >= kRankSteps[i].minScore) index = i;
  }
  final current = kRankSteps[index];
  if (index == kRankSteps.length - 1) {
    return RankProgress(
      current: current,
      next: null,
      remaining: 0,
      fraction: 1.0,
    );
  }
  final next = kRankSteps[index + 1];
  final span = next.minScore - current.minScore;
  final gained = score - current.minScore;
  return RankProgress(
    current: current,
    next: next,
    remaining: (next.minScore - score).clamp(0, next.minScore),
    fraction: span == 0 ? 0.0 : (gained / span).clamp(0.0, 1.0),
  );
}
