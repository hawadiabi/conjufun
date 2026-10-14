// lib/config/levels_config.dart

import '../viewmodels/exercise_vm.dart' show GameLevel, Tense;

// Listes de verbes par niveau scolaire
import '../data/level_cycle1.dart' as cycle1;
import '../data/level_cycle2.dart' as cycle2;
import '../data/level_cycle3.dart' as cycle3;
import '../data/level_sec1.dart' as sec1;
import '../data/level_sec2.dart' as sec2;

/// Tous les temps que le jeu sait gérer
const List<Tense> kAllSupportedTenses = [
  Tense.present,
  Tense.imparfait,
  Tense.futur,
  Tense.conditionnel,
  Tense.subjonctif,
  Tense.subjonctifImparfait,
  Tense.passeSimple,
  Tense.plusQueParfait,
  Tense.passeCompose,
  Tense.futurAnterieur,
  Tense.conditionnelPasse,
  Tense.futurProche,
  Tense.imperatif,
  Tense.subjonctifPasse,
  Tense.passeAnterieur,
  Tense.gerondif,
  Tense.participePresent,
  Tense.participePasse,
  Tense.infinitif,
  Tense.infinitifPasse,
];

// ---------------------------------------------------------------------------
// Informations d'un niveau : une seule source (nom affiché, clé enregistrée
// en base, points par bonne réponse).
// ---------------------------------------------------------------------------

extension GameLevelInfo on GameLevel {
  /// Clé enregistrée dans la base (colonne runs.level) : ne jamais la changer,
  /// sinon l'historique existant ne serait plus reconnu.
  String get key => name;

  /// Nom affiché partout dans l'application.
  String get label {
    switch (this) {
      case GameLevel.level_cycle1:
        return 'Niveau 1 (Cycle 1)';
      case GameLevel.level_cycle2:
        return 'Niveau 2 (Cycle 2)';
      case GameLevel.level_cycle3:
        return 'Niveau 3 (Cycle 3)';
      case GameLevel.level_sec1:
        return 'Niveau 4 (Sec 1)';
      case GameLevel.level_sec2:
        return 'Niveau 5 (Sec 2)';
      case GameLevel.expert:
        return 'Niveau Expert';
    }
  }

  /// Points gagnés pour une bonne réponse.
  int get pointsPerAnswer {
    switch (this) {
      case GameLevel.level_cycle1:
        return 5;
      case GameLevel.level_cycle2:
        return 8;
      case GameLevel.level_cycle3:
        return 11;
      case GameLevel.level_sec1:
        return 14;
      case GameLevel.level_sec2:
        return 17;
      case GameLevel.expert:
        return 20;
    }
  }
}

/// Retrouve un niveau depuis la clé enregistrée en base. Accepte aussi les
/// anciens noms (level1 à level5, level_expert). Retourne null si inconnu.
GameLevel? gameLevelFromKey(String? key) {
  switch (key) {
    case 'level_cycle1':
    case 'level1':
      return GameLevel.level_cycle1;
    case 'level_cycle2':
    case 'level2':
      return GameLevel.level_cycle2;
    case 'level_cycle3':
    case 'level3':
      return GameLevel.level_cycle3;
    case 'level_sec1':
    case 'level4':
      return GameLevel.level_sec1;
    case 'level_sec2':
    case 'level5':
      return GameLevel.level_sec2;
    case 'expert':
    case 'level_expert':
      return GameLevel.expert;
  }
  return null;
}

/// Nom affiché pour une clé de la base ; une clé inconnue est affichée telle
/// quelle.
String levelLabelFromKey(String key) => gameLevelFromKey(key)?.label ?? key;

/// Verbes autorisés par niveau
const Map<GameLevel, List<String>> kLevelVerbs = {
  GameLevel.level_cycle1: cycle1.kCycle1Verbs,

  GameLevel.level_cycle2: [...cycle1.kCycle1Verbs, ...cycle2.kCycle2Verbs],

  GameLevel.level_cycle3: [
    ...cycle1.kCycle1Verbs,
    ...cycle2.kCycle2Verbs,
    ...cycle3.kCycle3Verbs,
  ],

  GameLevel.level_sec1: [
    ...cycle1.kCycle1Verbs,
    ...cycle2.kCycle2Verbs,
    ...cycle3.kCycle3Verbs,
    ...sec1.kSec1Verbs,
  ],

  GameLevel.level_sec2: [
    ...cycle1.kCycle1Verbs,
    ...cycle2.kCycle2Verbs,
    ...cycle3.kCycle3Verbs,
    ...sec1.kSec1Verbs,
    ...sec2.kSec2Verbs,
  ],

  // Expert: géré à part avec LEFFF
  GameLevel.expert: [],
};

/// Temps autorisés par niveau
const Map<GameLevel, List<Tense>> kLevelTenses = {
  GameLevel.level_cycle1: [Tense.present, Tense.futurProche, Tense.imperatif],

  GameLevel.level_cycle2: [
    Tense.present,
    Tense.passeCompose,
    Tense.futurProche,
    Tense.imparfait,
    Tense.futur,
    Tense.imperatif,
  ],

  GameLevel.level_cycle3: [
    Tense.present,
    Tense.passeCompose,
    Tense.futurProche,
    Tense.imparfait,
    Tense.futur,
    Tense.imperatif,
  ],

  GameLevel.level_sec1: [
    Tense.present,
    Tense.passeCompose,
    Tense.futurProche,
    Tense.imparfait,
    Tense.futur,
    Tense.imperatif,
    Tense.conditionnel,
    Tense.passeSimple,
    Tense.subjonctif,
  ],

  GameLevel.level_sec2: [
    Tense.present,
    Tense.passeCompose,
    Tense.futurProche,
    Tense.imparfait,
    Tense.futur,
    Tense.imperatif,
    Tense.conditionnel,
    Tense.plusQueParfait,
    Tense.passeSimple,
    Tense.subjonctif,
    Tense.conditionnelPasse,
    Tense.futurAnterieur,
  ],
  GameLevel.expert: [],
};
