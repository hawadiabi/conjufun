import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../config/levels_config.dart' show kLevelTenses, GameLevelInfo;
import '../data/app_db.dart';
import '../data/auth_repo.dart';
import '../ui/app_colors.dart';
import '../main.dart' show brandBlue, brandYellow;
import '../viewmodels/answer_utils.dart';
import '../viewmodels/exercise_vm.dart' as vm;

// Config interne pour le test de niveau
class _PlacementConfig {
  final vm.GameLevel level;
  final double minSuccessRate;

  const _PlacementConfig(this.level, this.minSuccessRate);
}

// 4 questions par niveau -> 5 niveaux = 20 questions
const Map<vm.GameLevel, int> _questionsPerLevel = {
  vm.GameLevel.level_cycle1: 4,
  vm.GameLevel.level_cycle2: 4,
  vm.GameLevel.level_cycle3: 4,
  vm.GameLevel.level_sec1: 4,
  vm.GameLevel.level_sec2: 4,
};

class _LevelTestQuestionSpec {
  final vm.GameLevel level;
  final vm.Tense tense;

  const _LevelTestQuestionSpec(this.level, this.tense);
}

// Temps qu'on veut ÉVITER dans le test de niveau
const Set<vm.Tense> _forbiddenPlacementTenses = {
  vm.Tense.passeCompose,
  vm.Tense.infinitif,
  vm.Tense.infinitifPasse,
  vm.Tense.gerondif,
  vm.Tense.participePresent,
  vm.Tense.participePasse,
};

// Temps "simples" prioritaires pour le test de niveau
const Set<vm.Tense> _corePlacementTenses = {
  vm.Tense.present,
  vm.Tense.futurProche,
  vm.Tense.imparfait,
  vm.Tense.futur,
  vm.Tense.imperatif,
  vm.Tense.conditionnel,
  vm.Tense.passeSimple,
  vm.Tense.subjonctif,
};

const List<_PlacementConfig> _placementConfigs = [
  _PlacementConfig(vm.GameLevel.level_cycle1, 0.75),
  _PlacementConfig(vm.GameLevel.level_cycle2, 0.75),
  _PlacementConfig(vm.GameLevel.level_cycle3, 0.75),
  _PlacementConfig(vm.GameLevel.level_sec1, 0.75),
  _PlacementConfig(vm.GameLevel.level_sec2, 0.75),
];

class LevelTestPage extends StatefulWidget {
  const LevelTestPage({super.key});

  @override
  State<LevelTestPage> createState() => _LevelTestPageState();
}

class _LevelTestPageState extends State<LevelTestPage>
    with SingleTickerProviderStateMixin {
  final vm.ExerciseViewModel _viewModel = vm.ExerciseViewModel();
  final TextEditingController _controller = TextEditingController();

  vm.Exercise? _currentExercise;
  String _feedback = '';
  bool _locked = false;
  bool _cancelled = false;

  bool _isLoading = true;
  bool _isFinished = false;
  vm.GameLevel? _recommendedLevel;

  Completer<bool>? _answerCompleter;
  bool? _lastAnswerCorrect;

  // --- progression ---
  int _totalQuestions = 0;
  int _questionsAsked = 0;

  // --- animation "shake" du TextField en cas d'erreur de saisie ---
  late AnimationController _shakeController;

  double get _progress =>
      _totalQuestions == 0 ? 0.0 : _questionsAsked / _totalQuestions;

  int _computeTotalQuestions() {
    int sum = 0;
    for (final config in _placementConfigs) {
      sum += _questionsPerLevel[config.level] ?? 2;
    }
    return sum;
  }

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _startTest();
  }

  @override
  void dispose() {
    _cancelled = true;
    // Débloque la boucle du test si on quitte pendant une question.
    final c = _answerCompleter;
    if (c != null && !c.isCompleted) c.complete(false);
    _controller.dispose();
    _shakeController.dispose();
    super.dispose();
  }

  Future<void> _startTest() async {
    await _viewModel.initForVerbList();
    if (_cancelled || !mounted) return;

    _totalQuestions = _computeTotalQuestions();
    setState(() => _isLoading = false);

    for (final config in _placementConfigs) {
      final ok = await _runLevel(config.level, config.minSuccessRate);
      if (_cancelled || !mounted) return;
      if (!ok) {
        // Réussite insuffisante : on recommande CE niveau.
        setState(() {
          _isFinished = true;
          _recommendedLevel = config.level;
          _currentExercise = null;
        });
        return;
      }
    }

    // Tous les niveaux réussis -> Expert
    setState(() {
      _isFinished = true;
      _recommendedLevel = vm.GameLevel.expert;
      _currentExercise = null;
    });
  }

  List<_LevelTestQuestionSpec> _buildSpecsForLevel(vm.GameLevel level) {
    final int currentIndex = _placementConfigs.indexWhere(
      (cfg) => cfg.level == level,
    );

    final List<vm.GameLevel> previousLevels = currentIndex <= 0
        ? const []
        : _placementConfigs.take(currentIndex).map((cfg) => cfg.level).toList();

    final List<vm.Tense> baseTenses = List<vm.Tense>.from(
      kLevelTenses[level] ?? const [],
    );

    final Set<vm.Tense> previousTenses = {};
    for (final lvl in previousLevels) {
      previousTenses.addAll(kLevelTenses[lvl] ?? const []);
    }

    // Temps vus pour la première fois à ce niveau
    List<vm.Tense> levelTenses = baseTenses
        .where((t) => !previousTenses.contains(t))
        .toList();

    if (levelTenses.isEmpty) {
      levelTenses = baseTenses;
    }

    levelTenses.removeWhere((t) => _forbiddenPlacementTenses.contains(t));

    if (levelTenses.isEmpty) {
      levelTenses = baseTenses
          .where((t) => !_forbiddenPlacementTenses.contains(t))
          .toList();
    }

    final List<vm.Tense> core = levelTenses
        .where((t) => _corePlacementTenses.contains(t))
        .toList();
    final List<vm.Tense> others = levelTenses
        .where((t) => !_corePlacementTenses.contains(t))
        .toList();

    core.shuffle();
    others.shuffle();

    final int targetCount = _questionsPerLevel[level] ?? 2;
    final List<_LevelTestQuestionSpec> specs = [];

    for (final t in core) {
      if (specs.length >= targetCount) break;
      specs.add(_LevelTestQuestionSpec(level, t));
    }
    for (final t in others) {
      if (specs.length >= targetCount) break;
      specs.add(_LevelTestQuestionSpec(level, t));
    }

    int i = 0;
    while (specs.length < targetCount && levelTenses.isNotEmpty) {
      specs.add(
        _LevelTestQuestionSpec(level, levelTenses[i % levelTenses.length]),
      );
      i++;
    }

    specs.shuffle();
    return specs;
  }

  Future<bool> _runLevel(vm.GameLevel level, double minSuccessRate) async {
    final specs = _buildSpecsForLevel(level);

    int correct = 0;
    int total = 0;

    for (final spec in specs) {
      if (_cancelled) return false;
      final ex = await _viewModel.generateExerciseForLevelAndTense(
        spec.level,
        spec.tense,
      );
      if (ex == null) continue;

      final isCorrect = await _askQuestion(ex);
      total++;
      if (isCorrect) correct++;
    }

    final rate = total == 0 ? 0.0 : correct / total;
    return rate >= minSuccessRate;
  }

  Future<bool> _askQuestion(vm.Exercise ex) async {
    if (_cancelled || !mounted) return false;
    setState(() {
      _currentExercise = ex;
      _feedback = '';
      _locked = false;
      _controller.clear();
      _lastAnswerCorrect = null;
      _questionsAsked++;
    });

    final completer = Completer<bool>();
    _answerCompleter = completer;
    return completer.future;
  }

  void _onNextQuestionPressed() {
    final c = _answerCompleter;
    if (c == null || c.isCompleted) return;
    c.complete(_lastAnswerCorrect ?? false);
  }

  Future<void> _triggerShake() async {
    _shakeController.forward(from: 0);
  }

  Future<void> _onValidatePressed() async {
    // Verrou pris dès le début : pas de double validation.
    if (_locked) return;
    final ex = _currentExercise;
    if (ex == null) return;

    final needsPronoun = vm.tenseNeedsPronoun(ex.tense);
    final rawAnswer = normalizeApostrophes(_controller.text).trim();

    if (rawAnswer.isEmpty) {
      setState(() {
        _feedback = needsPronoun
            ? 'Écris la forme conjuguée complète, avec le pronom qui l’accompagne.'
            : 'Écris la forme conjuguée.';
      });
      await _triggerShake();
      return;
    }

    String userPronoun = '';
    String userVerb = rawAnswer;
    if (needsPronoun) {
      final (p, v) = splitPronounAndVerb(rawAnswer);
      userPronoun = p;
      userVerb = v;
      if (userPronoun.isEmpty || userVerb.isEmpty) {
        setState(() {
          _feedback = 'Pense à écrire le pronom et la forme conjuguée.';
        });
        await _triggerShake();
        return;
      }
    }

    final matched = _viewModel.matchedAnswerIndex(ex, userVerb);
    final verbOk = matched >= 0;

    // Test de niveau : il = elle, ils = elles, je = j'.
    final pronounOk = !needsPronoun
        ? true
        : samePronoun(
            ex.pronoun,
            userPronoun,
            lenientJe: true,
            ignoreGender: true,
          );

    final isCorrect = pronounOk && verbOk;

    // On enregistre le résultat sans le montrer à l'élève.
    setState(() {
      _locked = true;
      _lastAnswerCorrect = isCorrect;
      _feedback = '';
    });
  }

  Future<void> _confirmQuit() async {
    final shouldQuit =
        await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Quitter le test ?'),
            content: const Text(
              'Si tu quittes maintenant, le test de niveau sera perdu.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Continuer'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text(
                  'Quitter',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
        ) ??
        false;

    if (shouldQuit && mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _saveAndClose(vm.GameLevel? level) async {
    if (level != null) {
      try {
        final userId = await AuthRepo.instance.getCurrentUserId();
        if (userId != null) {
          await AppDb.instance.setUserLevelTestResult(
            userId: userId,
            levelString: level.name,
          );
        }
      } catch (_) {}
    }
    if (!mounted) return;
    Navigator.pop(context, level);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (_isFinished) {
          await _saveAndClose(_recommendedLevel);
        } else {
          await _confirmQuit();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          centerTitle: true,
          backgroundColor: brandBlue,
          foregroundColor: Colors.white,
          title: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Test de niveau',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              if (!_isFinished && _totalQuestions > 0) ...[
                const SizedBox(height: 2),
                Text(
                  'Question $_questionsAsked / $_totalQuestions',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
        ),
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: context.pageGradient,
            ),
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 22, 16, 22),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (!_isFinished && _totalQuestions > 0) ...[
                            ClipRRect(
                              borderRadius: BorderRadius.circular(999),
                              child: LinearProgressIndicator(
                                value: _progress.clamp(0.0, 1.0),
                                minHeight: 8,
                                backgroundColor: Colors.grey.withValues(
                                  alpha: 0.2,
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 260),
                            transitionBuilder: (child, animation) {
                              final slideAnimation = Tween<Offset>(
                                begin: const Offset(0.05, 0),
                                end: Offset.zero,
                              ).animate(animation);

                              return FadeTransition(
                                opacity: animation,
                                child: SlideTransition(
                                  position: slideAnimation,
                                  child: child,
                                ),
                              );
                            },
                            child: _isFinished
                                ? _buildResultContent()
                                : _buildQuestionContent(),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildResultContent() {
    final level = _recommendedLevel;

    return Column(
      key: const ValueKey('result'),
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Résultat du test',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 16),
        if (level != null) ...[
          Text(
            'Niveau recommandé :',
            style: TextStyle(fontSize: 16, color: context.mutedText),
          ),
          const SizedBox(height: 8),
          Chip(
            label: Text(
              level.label,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            backgroundColor: brandYellow.withValues(alpha: .15),
          ),
        ],
        const SizedBox(height: 24),
        const Text(
          'Tu peux maintenant commencer une partie dans ce niveau. '
          'Tu pourras toujours changer de niveau plus tard depuis l’écran d’accueil.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => _saveAndClose(level),
            style: ElevatedButton.styleFrom(
              backgroundColor: brandBlue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: const Text('Retour à l’accueil'),
          ),
        ),
      ],
    );
  }

  Widget _buildQuestionContent() {
    final ex = _currentExercise;
    if (ex == null) {
      return const SizedBox(
        key: ValueKey('loading-question'),
        height: 120,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final bool needsPronoun = vm.tenseNeedsPronoun(ex.tense);

    final personDesc = personLabel(
      ex.pronoun.trim().isEmpty ? kNoPronoun : ex.pronoun.trim(),
      genderless: true,
    );

    final String headerText = (ex.tense == vm.Tense.imperatif || needsPronoun)
        ? 'Temps demandé : ${ex.tenseLabel} – $personDesc'
        : 'Temps demandé : ${ex.tenseLabel} (forme sans pronom)';

    return Column(
      key: ValueKey('q-${ex.verb}-${ex.tense}-$_questionsAsked'),
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 8),
        Text(
          'Conjugue le verbe suivant :',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          ex.verb,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          headerText,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 12),
        Text(
          needsPronoun
              ? 'Écris la forme conjuguée complète, avec le pronom qui l’accompagne.'
              : 'Écris seulement la forme conjuguée, sans pronom.',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13),
        ),
        const SizedBox(height: 18),
        AbsorbPointer(
          absorbing: _locked,
          child: AnimatedBuilder(
            animation: _shakeController,
            builder: (context, child) {
              final offsetX =
                  math.sin(_shakeController.value * math.pi * 4) * 8;
              return Transform.translate(
                offset: Offset(offsetX, 0),
                child: child,
              );
            },
            child: Opacity(
              opacity: _locked ? 0.7 : 1,
              child: TextField(
                controller: _controller,
                autofocus: true,
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _onValidatePressed(),
                decoration: InputDecoration(
                  hintText: needsPronoun
                      ? 'Ex. : je mange, tu finiras, j’irai…'
                      : 'Écris la forme conjuguée',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                ),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _locked ? null : _onValidatePressed,
            icon: const Icon(Icons.check),
            label: const Text('Valider'),
            style: ElevatedButton.styleFrom(
              backgroundColor: brandBlue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
        if (_locked) ...[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _onNextQuestionPressed,
              icon: const Icon(Icons.arrow_forward),
              label: const Text('Suivant'),
            ),
          ),
        ],
        if (_feedback.isNotEmpty) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: .06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.red, width: 1),
            ),
            child: Text(
              _feedback,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
        const SizedBox(height: 16),
        TextButton.icon(
          onPressed: _confirmQuit,
          icon: const Icon(Icons.exit_to_app),
          label: const Text('Quitter le test'),
          style: TextButton.styleFrom(foregroundColor: Colors.red[700]),
        ),
      ],
    );
  }
}
