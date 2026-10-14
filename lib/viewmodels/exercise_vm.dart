// ignore_for_file: constant_identifier_names
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import '../models/custom_set.dart';
import '../data/app_db.dart';
import '../data/badge_catalog.dart';
import '../session_notifier.dart';
import '../config/levels_config.dart'
    show kLevelVerbs, kLevelTenses, kAllSupportedTenses, GameLevelInfo;
import 'answer_utils.dart';

// ------------------------------------------------------
// 1) Enum des temps + classe Exercise
// ------------------------------------------------------

enum Tense {
  present,
  imparfait,
  futur,
  conditionnel,
  subjonctif,
  subjonctifImparfait,
  passeSimple,
  plusQueParfait,
  passeCompose,
  futurAnterieur,
  conditionnelPasse,
  futurProche,
  imperatif,
  subjonctifPasse,
  passeAnterieur,
  gerondif,
  participePresent,
  infinitif,
  participePasse,
  infinitifPasse,
}

extension TenseLabel on Tense {
  String get label {
    switch (this) {
      case Tense.present:
        return 'présent';
      case Tense.imparfait:
        return 'imparfait';
      case Tense.futur:
        return 'futur simple';
      case Tense.conditionnel:
        return 'conditionnel présent';
      case Tense.subjonctif:
        return 'subjonctif présent';
      case Tense.subjonctifImparfait:
        return 'subjonctif imparfait';
      case Tense.passeSimple:
        return 'passé simple';
      case Tense.plusQueParfait:
        return 'plus-que-parfait';
      case Tense.passeCompose:
        return 'passé composé';
      case Tense.futurAnterieur:
        return 'futur antérieur';
      case Tense.conditionnelPasse:
        return 'conditionnel passé';
      case Tense.futurProche:
        return 'futur proche';
      case Tense.imperatif:
        return 'impératif';
      case Tense.subjonctifPasse:
        return 'subjonctif passé';
      case Tense.passeAnterieur:
        return 'passé antérieur';
      case Tense.gerondif:
        return 'gérondif';
      case Tense.participePresent:
        return 'participe présent';
      case Tense.infinitif:
        return 'infinitif';
      case Tense.participePasse:
        return 'participe passé';
      case Tense.infinitifPasse:
        return 'infinitif passé';
    }
  }
}

/// true si la réponse de l'élève doit commencer par un pronom sujet.
/// (Partagé par les pages d'exercice et le test de niveau.)
bool tenseNeedsPronoun(Tense t) {
  switch (t) {
    case Tense.imperatif:
    case Tense.infinitif:
    case Tense.infinitifPasse:
    case Tense.gerondif:
    case Tense.participePresent:
    case Tense.participePasse:
      return false;
    default:
      return true;
  }
}

class Exercise {
  final String infinitif;
  final String pronom;
  final String reponseAttendue;
  final Tense tense;

  /// Autres réponses acceptées : accords du participe passé avec « être »
  /// (je suis allé / allée) et double auxiliaire (j'ai sorti / je suis sorti).
  final List<String> alternatives;

  Exercise({
    required this.infinitif,
    required this.pronom,
    required this.reponseAttendue,
    required this.tense,
    this.alternatives = const [],
  });

  String get verb => infinitif;
  String get pronoun => pronom;
  String get correctAnswer => reponseAttendue;
  String get tenseLabel => tense.label;

  /// Réponse principale + alternatives.
  List<String> get answers => [reponseAttendue, ...alternatives];
}

// ------------------------------------------------------
// 3) Modes / niveaux
// ------------------------------------------------------

enum VmSessionMode { unlimited, fixed }

enum GameLevel {
  level_cycle1,
  level_cycle2,
  level_cycle3,
  level_sec1,
  level_sec2,
  expert,
}

// ------------------------------------------------------
// 4) ViewModel
// ------------------------------------------------------

class ExerciseViewModel extends ChangeNotifier {
  Exercise? _currentExercise;
  int _score = 0;
  int _highScore = 0;
  VmSessionMode _mode = VmSessionMode.unlimited;
  GameLevel _level = GameLevel.level_cycle1;
  CustomSet? _customSet;

  int? _userId;
  void setCurrentUserId(int? id) => _userId = id;
  int? get userId => _userId;

  /// Nombre de bonnes réponses de la session en cours.
  int correctCount = 0;

  DateTime _sessionStart = DateTime.now();

  /// Nombre de questions RÉPONDUES (bonnes ET mauvaises).
  int _askedCount = 0;
  int _targetCount = 0;

  int currentStreak = 0;
  int bestStreak = 0;

  /// true si aucun exercice n'a pu être généré (ex. ensemble créateur dont
  /// aucun temps ou verbe n'est utilisable).
  bool loadFailed = false;

  // Caches statiques : le gros JSON n'est décodé qu'une seule fois pour toute
  // l'application, quel que soit le nombre de ViewModels créés.
  static Map<String, dynamic>? _lefffCache;
  static Map<String, dynamic>? _grammarCache;

  Map<String, dynamic> _lefff = {};
  Map<String, dynamic>? _grammarModel;

  final _rng = Random();

  final List<String> _persons = const ['je', 'tu', 'il', 'nous', 'vous', 'ils'];

  String _randomPronounForIndex(int index, String verbForm) {
    final i = index.clamp(0, _persons.length - 1);
    switch (i) {
      case 0:
        return contractPronoun('je', verbForm);
      case 1:
        return 'tu';
      case 2:
        return _rng.nextBool() ? 'il' : 'elle';
      case 3:
        return 'nous';
      case 4:
        return 'vous';
      case 5:
        return _rng.nextBool() ? 'ils' : 'elles';
      default:
        return contractPronoun('je', verbForm);
    }
  }

  // Verbes qui prennent toujours « être » aux temps composés.
  static const Set<String> _etreVerbs = {
    'aller',
    'venir',
    'arriver',
    'partir',
    'repartir',
    'entrer',
    'naître',
    'mourir',
    'décéder',
    'devenir',
    'redevenir',
    'revenir',
    'parvenir',
    'survenir',
    'intervenir',
    'advenir',
    'tomber',
    'retomber',
    'rester',
  };

  // Verbes qui prennent « être » (sens intransitif) OU « avoir » (transitif).
  // On accepte les deux ; le premier de la liste est la réponse affichée.
  static const Set<String> _etreOrAvoirVerbs = {
    'rentrer',
    'sortir',
    'monter',
    'descendre',
    'retourner',
  };

  List<String> _auxChoices(String verb) {
    if (_etreVerbs.contains(verb)) return const ['être'];
    if (verb == 'passer') return const ['avoir', 'être'];
    if (_etreOrAvoirVerbs.contains(verb)) return const ['être', 'avoir'];
    return const ['avoir'];
  }

  Exercise? get currentExercise => _currentExercise;
  int get score => _score;
  int get highScore => _highScore;
  VmSessionMode get mode => _mode;
  GameLevel get level => _level;
  int get askedCount => _askedCount;
  int get targetCount => _targetCount;

  void resetScore() {
    _score = 0;
    notifyListeners();
  }

  String get levelString => _level.key;

  /// Taux de réussite = bonnes réponses / questions répondues.
  int get successPercent {
    if (_askedCount == 0) return 0;
    return ((correctCount / _askedCount) * 100).round();
  }

  String get progressLabel {
    if (_mode != VmSessionMode.fixed || _targetCount <= 0) return '';
    return '$_askedCount/$_targetCount';
  }

  // ------------------------------------------------------
  // 5) Mapping temps
  // ------------------------------------------------------

  String _tenseToSimpleCode(Tense t) {
    switch (t) {
      case Tense.present:
        return 'P';
      case Tense.imparfait:
        return 'I';
      case Tense.futur:
        return 'F';
      case Tense.conditionnel:
        return 'C';
      case Tense.subjonctif:
        return 'S';
      case Tense.subjonctifImparfait:
        return 'T';
      case Tense.passeSimple:
        return 'J';
      case Tense.participePasse:
        return 'K';
      default:
        return 'P';
    }
  }

  String? _tenseToCompoundCode(Tense t) {
    switch (t) {
      case Tense.passeCompose:
        return 'PC';
      case Tense.plusQueParfait:
        return 'PQP';
      case Tense.futurAnterieur:
        return 'FA';
      case Tense.conditionnelPasse:
        return 'CP';
      case Tense.subjonctifPasse:
        return 'SP';
      case Tense.passeAnterieur:
        return 'PA';
      case Tense.futurProche:
        return 'FP';
      default:
        return null;
    }
  }

  /// Retourne le temps correspondant à un libellé, ou null s'il est inconnu.
  Tense? _tenseFromLabel(String label) {
    final l = label.trim().toLowerCase();
    for (final t in Tense.values) {
      if (t.label == l) return t;
    }
    return null;
  }

  // ------------------------------------------------------
  // 6) Chargement données
  // ------------------------------------------------------

  static Future<Map<String, dynamic>> _ensureLefffCache() async {
    final cached = _lefffCache;
    if (cached != null) return cached;
    try {
      final raw = await rootBundle.loadString(
        'assets/data/lefff_conjugations.json',
      );
      return _lefffCache = json.decode(raw) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('Erreur chargement lefff_conjugations.json : $e');
      return {};
    }
  }

  Future<void> _loadLefff() async {
    if (_lefff.isNotEmpty) return;
    _lefff = await _ensureLefffCache();
  }

  /// Tous les verbes que le jeu sait conjuguer (triés). Sert au sélecteur de
  /// verbes du mode créateur, pour qu'il propose exactement ce que le jeu
  /// peut utiliser.
  static Future<List<String>> allKnownVerbs() async {
    final data = await _ensureLefffCache();
    return data.keys.toList()..sort();
  }

  /// Libellés des temps proposés dans le mode créateur.
  static List<String> allTenseLabels() =>
      kAllSupportedTenses.map((t) => t.label).toList();

  Future<void> _loadGrammarModel() async {
    if (_grammarModel != null) return;
    if (_grammarCache != null) {
      _grammarModel = _grammarCache;
      return;
    }
    try {
      final jsonStr = await rootBundle.loadString(
        'assets/data/grammar_rules.json',
      );
      _grammarCache = json.decode(jsonStr) as Map<String, dynamic>;
      _grammarModel = _grammarCache;
    } catch (e) {
      debugPrint('Erreur grammar_rules.json : $e');
      _grammarModel = {};
    }
  }

  Future<void> _loadRecord() async {
    final modeStr = (_mode == VmSessionMode.unlimited) ? 'unlimited' : 'fixed';
    _highScore = await AppDb.instance.getRecordByLevelAndMode(
      level: levelString,
      mode: modeStr,
      userId: _userId,
    );
  }

  /// Charge uniquement les données. Le record, les streaks et le premier
  /// exercice sont chargés après setCurrentUserId + configureSession.
  Future<void> init() async {
    await AppDb.instance.database;
    await _loadLefff();
    await _loadGrammarModel();
  }

  Future<void> initForVerbList() async {
    await _loadLefff();
    await _loadGrammarModel();
  }

  // ------------------------------------------------------
  // 7) Config session
  // ------------------------------------------------------

  Future<void> configureSession({
    required VmSessionMode mode,
    required int fixedCount,
    required GameLevel level,
    CustomSet? customSet,
  }) async {
    _customSet = customSet;

    // Un ensemble créateur qui définit un nombre de questions impose le mode
    // fixe avec ce nombre.
    final setMax = customSet?.maxQuestions ?? 0;
    if (setMax > 0) {
      _mode = VmSessionMode.fixed;
      _targetCount = setMax;
    } else {
      _mode = mode;
      _targetCount = (mode == VmSessionMode.fixed) ? fixedCount : 0;
    }

    _level = level;
    _score = 0;
    correctCount = 0;
    _askedCount = 0;
    _sessionStart = DateTime.now();

    await _loadRecord();
    notifyListeners();
  }

  @Deprecated('Utiliser registerCorrectAnswer() / registerWrongAnswer().')
  void incrementAskedIfFixed() {}

  // ------------------------------------------------------
  // 8) Génération exercices
  // ------------------------------------------------------

  Future<void> nextExercise() async {
    await _loadLefff();

    Exercise? ex;

    if (_customSet != null) {
      ex = _randomFromCustomSet();
    } else {
      // Plusieurs tentatives : certains couples verbe/temps n'ont pas de
      // données complètes dans le LEFFF.
      for (var i = 0; i < 30 && ex == null; i++) {
        ex = _randomFromLefff();
      }

      // Repli sur la base SQL uniquement si le LEFFF n'a pas pu être chargé.
      if (ex == null && _lefff.isEmpty) {
        final raw = await AppDb.instance.getRandomExerciseRaw();
        if (raw != null) {
          final t = _tenseFromLabel(raw['tense'] as String);
          if (t != null) {
            ex = Exercise(
              infinitif: raw['verb'] as String,
              pronom: raw['pronoun'] as String,
              reponseAttendue: raw['correct_answer'] as String,
              tense: t,
            );
          }
        }
      }
    }

    if (ex != null) {
      _currentExercise = ex;
      loadFailed = false;
    } else if (_currentExercise == null) {
      loadFailed = true;
    }
    notifyListeners();
  }

  bool _isNoPronounTense(Tense t) =>
      !tenseNeedsPronoun(t) && t != Tense.imperatif;

  /// Verbes et temps disponibles pour un niveau (sans doublons).
  (List<String>, List<Tense>) _poolForLevel(GameLevel level) {
    if (level == GameLevel.expert) {
      return (_lefff.keys.toList(), kAllSupportedTenses);
    }
    final configVerbs = kLevelVerbs[level] ?? const <String>[];
    final configTenses = kLevelTenses[level] ?? const <Tense>[];
    if (configVerbs.isEmpty || configTenses.isEmpty) {
      return (_lefff.keys.toList(), kAllSupportedTenses);
    }
    final verbs = configVerbs
        .where((v) => _lefff.containsKey(v))
        .toSet()
        .toList();
    return (verbs, configTenses);
  }

  Exercise? _randomFromLefff() {
    if (_lefff.isEmpty) return null;
    final (verbs, tenses) = _poolForLevel(_level);
    if (verbs.isEmpty || tenses.isEmpty) return null;
    return _buildExerciseFor(
      verbs[_rng.nextInt(verbs.length)],
      tenses[_rng.nextInt(tenses.length)],
    );
  }

  /// Mode créateur : même générateur que le mode normal (contraction j',
  /// il/elle, ils/elles, accords, temps composés, bon libellé de temps).
  Exercise? _randomFromCustomSet() {
    final set = _customSet;
    if (set == null || _lefff.isEmpty) return null;

    final verbs = set.verbs.where((v) => _lefff.containsKey(v)).toList();
    final tenses = set.tenses.map(_tenseFromLabel).whereType<Tense>().toList();
    if (verbs.isEmpty || tenses.isEmpty) return null;

    for (var i = 0; i < 40; i++) {
      final ex = _buildExerciseFor(
        verbs[_rng.nextInt(verbs.length)],
        tenses[_rng.nextInt(tenses.length)],
      );
      if (ex != null) return ex;
    }
    return null;
  }

  Future<Exercise?> generateExerciseForLevelAndTense(
    GameLevel level,
    Tense tense,
  ) async {
    await _loadLefff();
    if (_lefff.isEmpty) return null;

    final (verbs, _) = _poolForLevel(level);
    if (verbs.isEmpty) return null;

    for (var i = 0; i < 20; i++) {
      final ex = _buildExerciseFor(verbs[_rng.nextInt(verbs.length)], tense);
      if (ex != null) return ex;
    }
    return null;
  }

  /// Construit un exercice pour un verbe et un temps donnés, ou null si les
  /// données sont incomplètes.
  Exercise? _buildExerciseFor(String verb, Tense tense) {
    final rawEntry = _lefff[verb];
    if (rawEntry is! Map) return null;
    final verbTenses = rawEntry.cast<String, dynamic>();

    final forms = _buildFormsFor(
      verb: verb,
      tense: tense,
      verbTenses: verbTenses,
    );
    if (forms.isEmpty) return null;

    // Indices dont la forme existe vraiment (l'impératif n'a pas de « je »).
    final maxIdx = forms.length.clamp(0, 6);
    final valid = <int>[];
    for (var i = 0; i < maxIdx; i++) {
      final f = forms[i].toString().trim();
      if (f.isNotEmpty && f != 'NA') valid.add(i);
    }
    if (valid.isEmpty) return null;

    final idx = valid[_rng.nextInt(valid.length)];
    final form = forms[idx].toString().trim();

    final pronoun = _isNoPronounTense(tense)
        ? kNoPronoun
        : _randomPronounForIndex(idx, form);

    var answers = <String>[form];

    // Temps composés : accord du participe avec « être » selon le pronom,
    // et double auxiliaire pour les verbes ambigus.
    final compoundCode = _tenseToCompoundCode(tense);
    if (compoundCode != null && compoundCode != 'FP') {
      final built = _compoundAnswers(
        verb: verb,
        verbTenses: verbTenses,
        compoundCode: compoundCode,
        idx: idx,
        pronoun: pronoun,
      );
      if (built.isEmpty) return null;
      answers = built;
    }

    // Le « je » est contracté d'après la réponse principale.
    final finalPronoun = _isNoPronounTense(tense)
        ? kNoPronoun
        : (pronoun == 'je' || pronoun == "j'")
        ? contractPronoun('je', answers.first)
        : pronoun;

    return Exercise(
      infinitif: verb,
      pronom: finalPronoun,
      reponseAttendue: answers.first,
      tense: tense,
      alternatives: answers.skip(1).toList(),
    );
  }

  List<String> _buildFormsFor({
    required String verb,
    required Tense tense,
    required Map<String, dynamic> verbTenses,
  }) {
    if (tense == Tense.futurProche) {
      return _buildFuturProcheForms(verb: verb, allVerbs: _lefff);
    }

    if (tense == Tense.infinitif) {
      final rawW = verbTenses['W'];
      if (rawW is! List || rawW.isEmpty) return [];
      final inf = rawW.first.toString().trim();
      if (inf.isEmpty) return [];
      return List<String>.filled(6, inf);
    }

    if (tense == Tense.infinitifPasse) {
      return _buildInfinitifPasseForms(verb: verb, verbTenses: verbTenses);
    }

    if (tense == Tense.participePresent) {
      final rawG = verbTenses['G'];
      if (rawG is! List || rawG.isEmpty) return [];
      final gForm = rawG.first.toString().trim();
      if (gForm.isEmpty) return [];
      return List<String>.filled(6, gForm);
    }

    if (tense == Tense.gerondif) {
      final rawG = verbTenses['G'];
      if (rawG is! List || rawG.isEmpty) return [];
      final gForm = rawG.first.toString().trim();
      if (gForm.isEmpty) return [];
      return List<String>.filled(6, 'en $gForm');
    }

    // Participe passé : seule la forme de base (masculin singulier) est
    // demandée. Les autres formes du LEFFF (mangée, mangés...) n'ont aucun
    // contexte de genre/nombre dans la question.
    if (tense == Tense.participePasse) {
      final rawK = verbTenses['K'];
      if (rawK is! List || rawK.isEmpty) return [];
      final pp = rawK.first.toString().trim();
      if (pp.isEmpty) return [];
      return List<String>.filled(6, pp);
    }

    if (tense == Tense.imperatif) {
      final rawY = verbTenses['Y'];
      if (rawY is! List) return [];
      final yForms = List<String>.from(rawY);
      if (yForms.length < 6) return [];
      return yForms;
    }

    final compoundCode = _tenseToCompoundCode(tense);
    if (compoundCode != null) {
      // Pas de repli silencieux sur le présent : si les données manquent, on
      // renvoie une liste vide et l'appelant choisit un autre verbe.
      return _buildCompoundForms(
        verb: verb,
        verbTenses: verbTenses,
        compoundCode: compoundCode,
      );
    }

    final baseCode = _tenseToSimpleCode(tense);
    final rawForms = verbTenses[baseCode];
    if (rawForms is! List) return [];
    return List<String>.from(rawForms);
  }

  /// Auxiliaire conjugué + participe passé (non accordé) d'un temps composé.
  ({List<String> auxForms, String pp})? _compoundParts({
    required Map<String, dynamic> verbTenses,
    required String compoundCode,
    required String aux,
  }) {
    final ppRaw = verbTenses['K'];
    if (ppRaw is! List || ppRaw.isEmpty) return null;
    final pp = ppRaw.first.toString().trim();
    if (pp.isEmpty) return null;

    final auxRaw = _lefff[aux];
    if (auxRaw is! Map) return null;
    final auxTenses = auxRaw.cast<String, dynamic>();

    String baseCode;
    switch (compoundCode) {
      case 'PC':
        baseCode = 'P';
        break;
      case 'PQP':
        baseCode = 'I';
        break;
      case 'FA':
        baseCode = 'F';
        break;
      case 'CP':
        baseCode = 'C';
        break;
      case 'SP':
        baseCode = 'S';
        break;
      case 'PA':
        baseCode = 'J';
        break;
      default:
        return null;
    }

    final auxFormsRaw = auxTenses[baseCode];
    if (auxFormsRaw is! List) return null;
    final auxForms = auxFormsRaw.map((e) => e.toString().trim()).toList();
    if (auxForms.length < 6) return null;

    return (auxForms: auxForms, pp: pp);
  }

  /// Formes « de base » (participe non accordé, auxiliaire principal).
  /// Sert à valider que le temps existe et à l'affichage de la conjugaison.
  List<String> _buildCompoundForms({
    required String verb,
    required Map<String, dynamic> verbTenses,
    required String compoundCode,
  }) {
    final parts = _compoundParts(
      verbTenses: verbTenses,
      compoundCode: compoundCode,
      aux: _auxChoices(verb).first,
    );
    if (parts == null) return [];

    return List<String>.generate(6, (i) {
      final aux = parts.auxForms[i];
      return aux.isEmpty ? parts.pp : '$aux ${parts.pp}';
    });
  }

  /// Toutes les réponses acceptées (la première est la réponse affichée).
  List<String> _compoundAnswers({
    required String verb,
    required Map<String, dynamic> verbTenses,
    required String compoundCode,
    required int idx,
    required String pronoun,
  }) {
    final answers = <String>[];

    for (final aux in _auxChoices(verb)) {
      final parts = _compoundParts(
        verbTenses: verbTenses,
        compoundCode: compoundCode,
        aux: aux,
      );
      if (parts == null || idx >= parts.auxForms.length) continue;

      final auxForm = parts.auxForms[idx];
      if (auxForm.isEmpty) continue;

      final participles = aux == 'être'
          ? _agreementVariants(parts.pp, pronoun)
          : [parts.pp];

      for (final p in participles) {
        final full = '$auxForm $p';
        if (!answers.contains(full)) answers.add(full);
      }
    }
    return answers;
  }

  String _agree(String pp, {required bool feminine, required bool plural}) {
    var r = pp;
    if (feminine) r += 'e';
    if (plural && !(r.endsWith('s') || r.endsWith('x'))) r += 's';
    return r;
  }

  /// Accords possibles du participe avec « être » (le premier est affiché).
  /// Pour je/tu/nous/vous, le genre est inconnu : on accepte masculin et féminin.
  List<String> _agreementVariants(String pp, String pronoun) {
    switch (normalizeApostrophes(pronoun).trim().toLowerCase()) {
      case 'il':
        return [pp];
      case 'elle':
        return [_agree(pp, feminine: true, plural: false)];
      case 'ils':
        return [_agree(pp, feminine: false, plural: true)];
      case 'elles':
        return [_agree(pp, feminine: true, plural: true)];
      case 'nous':
        return [
          _agree(pp, feminine: false, plural: true),
          _agree(pp, feminine: true, plural: true),
        ];
      case 'vous':
        return [
          _agree(pp, feminine: false, plural: true),
          pp,
          _agree(pp, feminine: true, plural: false),
          _agree(pp, feminine: true, plural: true),
        ];
      default: // je, j', tu
        return [pp, _agree(pp, feminine: true, plural: false)];
    }
  }

  List<String> _buildFuturProcheForms({
    required String verb,
    required Map<String, dynamic> allVerbs,
  }) {
    final rawAller = allVerbs['aller'];
    if (rawAller is! Map) return [];
    final allerTenses = rawAller.cast<String, dynamic>();

    final presentRaw = allerTenses['P'];
    if (presentRaw is! List) return [];
    final presentForms = List<String>.from(presentRaw);
    if (presentForms.length < 6) return [];

    return List<String>.generate(6, (i) {
      final aux = presentForms[i].toString().trim();
      if (aux.isEmpty) return verb;
      return '$aux $verb';
    });
  }

  List<String> _buildInfinitifPasseForms({
    required String verb,
    required Map<String, dynamic> verbTenses,
  }) {
    final ppRaw = verbTenses['K'];
    if (ppRaw is! List || ppRaw.isEmpty) return [];
    final pp = ppRaw.first.toString().trim();
    if (pp.isEmpty) return [];

    final form = '${_auxChoices(verb).first} $pp';
    return List<String>.filled(6, form);
  }

  // ------------------------------------------------------
  // 10) Conjugaison complète (explications)
  // ------------------------------------------------------

  Map<String, String> getFullConjugationForCurrent() {
    if (_currentExercise == null) return {};
    return getFullConjugationForExercise(_currentExercise!);
  }

  Map<String, String> getFullConjugationForExercise(Exercise ex) {
    if (_lefff.isEmpty) return {ex.pronoun: ex.correctAnswer};

    final rawEntry = _lefff[ex.verb];
    if (rawEntry is! Map) {
      return {ex.pronoun: ex.correctAnswer};
    }
    final verbTenses = rawEntry.cast<String, dynamic>();

    final forms = _buildFormsFor(
      verb: ex.verb,
      tense: ex.tense,
      verbTenses: verbTenses,
    );
    if (forms.isEmpty) {
      return {ex.pronoun: ex.correctAnswer};
    }

    final result = <String, String>{};
    final max = forms.length.clamp(0, _persons.length);
    for (int i = 0; i < max; i++) {
      final form = forms[i].trim();
      if (form.isEmpty || form == 'NA') continue;

      final displayPronoun = contractPronoun(_persons[i], form);
      result[displayPronoun] = form;
    }

    if (result.isEmpty) {
      return {ex.pronoun: ex.correctAnswer};
    }
    return result;
  }

  // ------------------------------------------------------
  // 11) Explications grammaticales
  // ------------------------------------------------------

  String _findVerbGroupKey(String verb) {
    if (_grammarModel == null || !_grammarModel!.containsKey('verb_families')) {
      if (verb.endsWith('er')) return 'er';
      if (verb.endsWith('ir')) return 'ir_finir';
      return 'er';
    }

    final families = _grammarModel!['verb_families'] as Map<String, dynamic>;

    for (final entry in families.entries) {
      final key = entry.key;
      final list = (entry.value as List).cast<String>();
      if (list.contains(verb)) {
        return key;
      }
    }

    if (verb.endsWith('er')) return 'er';
    if (verb.endsWith('ir')) return 'ir_finir';
    return 'er';
  }

  String _withPronoun(String pronoun, String form) {
    final p = pronoun.trim();
    if (p.isEmpty || p == kNoPronoun) return form;
    return p.endsWith("'") ? '$p$form' : '$p $form';
  }

  /// Réponse attendue prête à afficher : « elle est allée », « j'ai sorti /
  /// je suis sorti », « en mangeant »...
  String expectedDisplay(Exercise ex) {
    final answers = ex.answers;
    if (!tenseNeedsPronoun(ex.tense)) return answers.join(' / ');

    final p = ex.pronoun.trim();
    return answers
        .map((a) {
          final pron = (p == 'je' || p == "j'") ? contractPronoun('je', a) : p;
          return _withPronoun(pron, a);
        })
        .join(' / ');
  }

  String _computeRadical(String verb, String groupKey) {
    if (groupKey == 'er') {
      if (verb.endsWith('er')) {
        return verb.substring(0, verb.length - 2);
      }
    } else if (groupKey == 'ir_finir') {
      if (verb.endsWith('ir')) {
        return verb.substring(0, verb.length - 2);
      }
    }
    if (verb.length > 2) {
      return verb.substring(0, verb.length - 2);
    }
    return verb;
  }

  String _buildExampleConjugation(
    String verb,
    Map<String, String> endings,
    String pattern,
    String groupKey,
  ) {
    String formFor(String label, String pronoun) {
      final base = pattern == 'infinitive_plus_ending'
          ? verb
          : _computeRadical(verb, groupKey);
      final ending = endings[label] ?? '';
      final verbForm = base + ending;
      return _withPronoun(contractPronoun(pronoun, verbForm), verbForm);
    }

    final forms = <String>[
      formFor('je', 'je'),
      formFor('tu', 'tu'),
      formFor('il/elle', 'il/elle'),
      formFor('nous', 'nous'),
      formFor('vous', 'vous'),
      formFor('ils/elles', 'ils/elles'),
    ];

    return 'Exemple avec « $verb » : ${forms.join(', ')}.';
  }

  /// Explication affichée après une erreur. Basée sur l'enum du temps (et non
  /// plus sur des morceaux de libellé : « futur » captait aussi futur proche
  /// et futur antérieur, « subjonctif présent » tombait sur « présent », et
  /// plusieurs temps retombaient sur le présent par défaut).
  String getExplanationForCurrent() {
    final ex = _currentExercise;
    if (ex == null) return '';

    final b = StringBuffer();
    b.writeln(
      'Rappel : « ${ex.verb} » au ${ex.tenseLabel} → ${expectedDisplay(ex)}.',
    );

    // Temps sans tableau de terminaisons dans grammar_rules.json
    switch (ex.tense) {
      case Tense.futurProche:
        b.writeln();
        b.writeln(
          "Futur proche : le verbe « aller » au présent + le verbe à l'infinitif.",
        );
        return b.toString().trim();
      case Tense.imperatif:
        b.writeln();
        b.writeln(
          "À l'impératif, on n'écrit pas le pronom sujet (tu, nous, vous seulement).",
        );
        return b.toString().trim();
      case Tense.passeCompose:
        try {
          final generic = _grammarModel?['passe_compose_generic'] as String?;
          if (generic != null) {
            b.writeln();
            b.writeln(generic);
          }
        } catch (_) {}
        if (_auxChoices(ex.verb).first == 'être') {
          b.writeln(
            "Avec « être », le participe passé s'accorde avec le sujet.",
          );
        }
        return b.toString().trim();
      default:
        break;
    }

    final String? tenseKey;
    switch (ex.tense) {
      case Tense.present:
        tenseKey = 'present';
        break;
      case Tense.imparfait:
        tenseKey = 'imparfait';
        break;
      case Tense.futur:
        tenseKey = 'futur';
        break;
      case Tense.conditionnel:
        tenseKey = 'conditional';
        break;
      default:
        tenseKey = null;
    }

    // Autres temps : le rappel suffit.
    if (tenseKey == null || _grammarModel == null || _grammarModel!.isEmpty) {
      return b.toString().trim();
    }

    try {
      final groupKey = _findVerbGroupKey(ex.verb.toLowerCase());
      final groups = _grammarModel!['groups'] as Map<String, dynamic>;
      final group = groups[groupKey] as Map<String, dynamic>;
      final groupName = group['name'] as String;
      final exampleVerb = group['example'] as String;

      if (!group.containsKey(tenseKey)) {
        b.writeln();
        b.writeln(
          "Ce temps n'est pas encore détaillé pour le groupe « $groupName ».",
        );
        return b.toString().trim();
      }

      final tenseData = group[tenseKey] as Map<String, dynamic>;
      final pattern =
          (tenseData['pattern'] as String?) ?? 'radical_plus_ending';

      final tenses = _grammarModel!['tenses'] as Map<String, dynamic>;
      final tenseMeta = tenses[tenseKey] as Map<String, dynamic>;
      final tenseNiceLabel = tenseMeta['label'] as String;

      b.writeln();
      b.writeln('Groupe : $groupName.');
      b.writeln('Temps : $tenseNiceLabel.');

      if (pattern == 'custom_example') {
        b.writeln(tenseData['example_line'] as String);
      } else {
        final endingsRaw = tenseData['endings'] as Map<String, dynamic>;
        final endings = endingsRaw.map((k, v) => MapEntry(k, v as String));
        b.writeln(
          _buildExampleConjugation(exampleVerb, endings, pattern, groupKey),
        );
      }
    } catch (e) {
      debugPrint('Explication grammaticale indisponible : $e');
    }

    return b.toString().trim();
  }

  // ------------------------------------------------------
  // 12) Vérification / score / badges
  // ------------------------------------------------------

  /// Index de la réponse acceptée correspondant à [userAnswer] (sans le
  /// pronom) : 0 = réponse principale, 1.. = alternatives, -1 = aucune.
  int matchedAnswerIndex(Exercise ex, String userAnswer) {
    final u = normalizeAnswerText(userAnswer);
    if (u.isEmpty) return -1;
    final answers = ex.answers;
    for (var i = 0; i < answers.length; i++) {
      if (u == normalizeAnswerText(answers[i])) return i;
    }
    return -1;
  }

  /// Vérifie une réponse (sans le pronom) contre l'exercice donné.
  bool isAnswerCorrectFor(Exercise ex, String userAnswer) =>
      matchedAnswerIndex(ex, userAnswer) >= 0;

  bool isAnswerCorrect(String userAnswer) {
    final ex = _currentExercise;
    if (ex == null) return false;
    return isAnswerCorrectFor(ex, userAnswer);
  }

  int pointsForCurrent() => _level.pointsPerAnswer;

  /// Enregistre une bonne réponse : points + bonnes réponses + questions
  /// répondues.
  void registerCorrectAnswer() {
    _score += pointsForCurrent();
    correctCount++;
    _askedCount++;
    notifyListeners();
  }

  /// Enregistre une mauvaise réponse.
  void registerWrongAnswer() {
    _askedCount++;
    notifyListeners();
  }

  void addPointsForCurrent() => registerCorrectAnswer();

  Future<void> _logCurrentRun() async {
    final totalTarget = (_mode == VmSessionMode.fixed)
        ? _targetCount
        : _askedCount;

    await AppDb.instance.insertRun(
      startedAt: _sessionStart,
      mode: (_mode == VmSessionMode.unlimited) ? 'unlimited' : 'fixed',
      level: levelString,
      totalTarget: totalTarget < 0 ? 0 : totalTarget,
      correctCount: correctCount < 0 ? 0 : correctCount,
      score: _score < 0 ? 0 : _score,
      userId: _userId,
    );

    // Le streak n'est mis à jour que lorsqu'une partie est réellement
    // enregistrée (jamais en quittant sans avoir joué).
    if (_userId != null) {
      final streaks = await AppDb.instance.updateStreakAfterSession(
        userId: _userId!,
        sessionTime: DateTime.now(),
      );
      currentStreak = streaks['current'] ?? 0;
      bestStreak = streaks['best'] ?? 0;
    }

    notifyListeners();
    notifyDataChanged();
  }

  /// Mode illimité : fin de partie à la première erreur.
  Future<bool> onWrongAnswerAndMaybeUpdateRecord() async {
    final prevBest = await AppDb.instance.getRecordByLevelAndMode(
      level: levelString,
      mode: 'unlimited',
      userId: _userId,
    );
    await _logCurrentRun();
    // Le tout premier score n'est pas un « record » à fêter.
    final isNew = prevBest > 0 && _score > prevBest;
    _highScore = _score > prevBest ? _score : prevBest;
    return isNew;
  }

  Future<bool> finalizeAndMaybeRecord() async {
    final prevBest = await AppDb.instance.getRecordByLevelAndMode(
      level: levelString,
      mode: 'fixed',
      userId: _userId,
    );
    await _logCurrentRun();
    final isNew = prevBest > 0 && _score > prevBest;
    _highScore = _score > prevBest ? _score : prevBest;
    return isNew;
  }

  /// Rang actuel du joueur (null pour un invité) et points avant le suivant.
  Future<RankProgress?> computeGlobalRank() async {
    if (_userId == null) return null;

    final total = await AppDb.instance.getTotalScoreForUser(_userId);
    return rankForScore(total);
  }

  /// Débloque tous les badges dont la condition est remplie et qui ne sont
  /// pas déjà possédés. Retourne les messages à afficher.
  Future<List<String>> checkForNewBadges() async {
    if (_userId == null) return [];

    final userId = _userId!;

    // Assure que les streaks à jour sont utilisés pour les badges de séries.
    await refreshStreaks();

    final fixed = await AppDb.instance.getRunsSuccess('fixed', userId: userId);
    final unlimited = await AppDb.instance.getRunsSuccess(
      'unlimited',
      userId: userId,
    );

    final totalCorrect =
        (fixed['correct'] ?? 0).toInt() + (unlimited['correct'] ?? 0).toInt();

    final totalSessions =
        (fixed['runs'] ?? 0).toInt() + (unlimited['runs'] ?? 0).toInt();

    final totalScore = await AppDb.instance.getTotalScoreForUser(userId);

    int valueFor(BadgeKind kind) {
      switch (kind) {
        case BadgeKind.correct:
          return totalCorrect;
        case BadgeKind.sessions:
          return totalSessions;
        case BadgeKind.score:
          return totalScore;
        case BadgeKind.streak:
          return bestStreak;
      }
    }

    final messages = <String>[];
    for (final def in kBadgeCatalog) {
      if (valueFor(def.kind) < def.threshold) continue;
      if (await AppDb.instance.userHasBadge(userId, def.code)) continue;

      await AppDb.instance.insertBadge(
        userId: userId,
        code: def.code,
        title: def.title,
        description: def.description,
      );
      messages.add(def.message);
    }

    if (messages.isNotEmpty) notifyDataChanged();
    return messages;
  }

  /// Démarre une nouvelle manche (même niveau, même mode).
  Future<void> startNewRound() async {
    _score = 0;
    correctCount = 0;
    _askedCount = 0;
    _sessionStart = DateTime.now();
    await _loadRecord(); // le record a pu changer à la fin de la manche
    await nextExercise();
  }

  // ------------------------------------------------------
  // 14) Streaks journaliers
  // ------------------------------------------------------

  Future<void> refreshStreaks() async {
    if (_userId == null) {
      currentStreak = 0;
      bestStreak = 0;
      notifyListeners();
      return;
    }

    final s = await AppDb.instance.getStreakForUser(_userId!);
    currentStreak = s['current'] ?? 0;
    bestStreak = s['best'] ?? 0;
    notifyListeners();
  }

  // ------------------------------------------------------
  // 15) OUTILS pour VerbListPage (tout lefff)
  // ------------------------------------------------------

  /// Tous les verbes connus par lefff.
  List<String> getAllVerbs() {
    final list = _lefff.keys.toList();
    list.sort((a, b) => a.compareTo(b));
    return list;
  }

  /// Nom de groupe pour VerbListPage.
  String groupLabelForVerb(String verb) {
    if (_grammarModel != null &&
        _grammarModel!.containsKey('verb_families') &&
        _grammarModel!.containsKey('groups')) {
      final families = (_grammarModel!['verb_families'] as Map)
          .cast<String, dynamic>();
      final groups = (_grammarModel!['groups'] as Map).cast<String, dynamic>();

      for (final entry in families.entries) {
        final key = entry.key;
        final verbs = List<String>.from(entry.value as List);
        if (verbs.contains(verb)) {
          final meta = groups[key] as Map<String, dynamic>?;
          return meta?['name'] as String? ?? key;
        }
      }
    }

    if (verb.endsWith('er')) return '1er groupe';
    if (verb.endsWith('ir')) return '2e groupe';
    return '3e groupe';
  }

  /// Toutes les conjugaisons (pour les temps supportés) d'un verbe via lefff.
  Map<String, Map<String, String>> getAllConjugationsForVerb(String verb) {
    if (_lefff.isEmpty) return {};
    final raw = _lefff[verb];
    if (raw is! Map) return {};
    final verbTenses = raw.cast<String, dynamic>();

    final result = <String, Map<String, String>>{};

    for (final tense in kAllSupportedTenses) {
      final forms = _buildFormsFor(
        verb: verb,
        tense: tense,
        verbTenses: verbTenses,
      );
      if (forms.isEmpty) continue;

      final formsMap = <String, String>{};
      final max = forms.length.clamp(0, _persons.length);
      for (int i = 0; i < max; i++) {
        final form = forms[i].trim();
        if (form.isEmpty || form == 'NA') continue;
        formsMap[_persons[i]] = form;
      }

      if (formsMap.isNotEmpty) {
        result[tense.label] = formsMap;
      }
    }

    return result;
  }
}
