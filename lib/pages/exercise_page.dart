import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';

import '../data/app_db.dart';
import '../data/auth_repo.dart';
import '../ui/app_colors.dart';
import '../main.dart' show brandBlue;
import '../models/custom_set.dart';
import '../session_notifier.dart';
import '../viewmodels/answer_utils.dart';
import '../viewmodels/exercise_vm.dart' as vm;
import 'home_page.dart' show SessionMode;

class ShakeAnimation extends StatelessWidget {
  final Animation<double> animation;
  final Widget child;

  const ShakeAnimation({
    super.key,
    required this.animation,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final double offset = 10 * (animation.value - 0.5);
    return Transform.translate(offset: Offset(offset, 0), child: child);
  }
}

class PopAnimation extends StatelessWidget {
  final Animation<double> animation;
  final Widget child;

  const PopAnimation({super.key, required this.animation, required this.child});

  @override
  Widget build(BuildContext context) {
    final double scale = 1 + (0.15 * animation.value);
    return Transform.scale(scale: scale, child: child);
  }
}

class FlashBackground extends StatelessWidget {
  final Animation<double> animation;
  final bool isCorrect;
  final Widget child;

  const FlashBackground({
    super.key,
    required this.animation,
    required this.isCorrect,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final color = isCorrect ? Colors.green : Colors.red;

    return Stack(
      alignment: Alignment.center,
      children: [
        Opacity(
          opacity: animation.value * 0.25,
          child: Container(
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        child,
      ],
    );
  }
}

class ExercisePage extends StatefulWidget {
  const ExercisePage({
    super.key,
    this.mode = SessionMode.unlimited,
    this.fixedCount,
    required this.level,
    this.customSet,
  });

  final SessionMode mode;
  final int? fixedCount;
  final vm.GameLevel level;
  final CustomSet? customSet;

  @override
  State<ExercisePage> createState() => _ExercisePageState();
}

enum _AnswerFeedback { none, correct, wrong }

/// Choix fait par l'élève dans la fenêtre de fin de partie.
/// Les boutons ne font que renvoyer ce choix : toute la logique est exécutée
/// après la fermeture de la fenêtre (et après l'affichage des badges).
enum _EndChoice { again, home }

class _ExercisePageState extends State<ExercisePage> {
  final vm.ExerciseViewModel _viewModel = vm.ExerciseViewModel();
  final TextEditingController _controller = TextEditingController();

  final AudioPlayer _badgePlayer = AudioPlayer();
  final AudioPlayer _fxPlayer = AudioPlayer();
  late ConfettiController _confettiController;

  String _feedback = '';
  String _explanation = '';
  _AnswerFeedback _answerState = _AnswerFeedback.none;
  bool _locked = false; // la question a reçu sa réponse
  bool _busy = false; // une validation est en cours (anti double clic)
  bool _emptyShake = false;
  bool _initDone = false;

  @override
  void initState() {
    super.initState();
    _confettiController = ConfettiController(
      duration: const Duration(seconds: 2),
    );
    _init();
  }

  Future<void> _init() async {
    await _viewModel.init();

    final user = await AuthRepo.instance.getCurrentUser();
    _viewModel.setCurrentUserId(user == null ? null : user['id'] as int);

    await _viewModel.configureSession(
      mode: widget.mode == SessionMode.unlimited
          ? vm.VmSessionMode.unlimited
          : vm.VmSessionMode.fixed,
      fixedCount: widget.mode == SessionMode.fixed
          ? (widget.fixedCount ?? 10)
          : 0,
      level: widget.level,
      customSet: widget.customSet,
    );

    await _viewModel.nextExercise();

    if (mounted) setState(() => _initDone = true);
  }

  @override
  void dispose() {
    _controller.dispose();
    _badgePlayer.dispose();
    _fxPlayer.dispose();
    _confettiController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------
  // Sons
  // ---------------------------------------------------------------------

  Future<void> _playCorrectFx() async {
    try {
      await _fxPlayer.play(AssetSource('sounds/correct.mp3'));
    } catch (_) {}
  }

  Future<void> _playWrongFx() async {
    try {
      await _fxPlayer.play(AssetSource('sounds/wrong.mp3'));
    } catch (_) {}
  }

  Future<void> _playBadgeSound() async {
    try {
      await _badgePlayer.play(AssetSource('sounds/badge.mp3'));
    } catch (_) {}
  }

  // ---------------------------------------------------------------------
  // Quitter
  // ---------------------------------------------------------------------

  Future<bool> _confirmQuit() async {
    final shouldQuit =
        await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Quitter la partie ?'),
            content: const Text(
              'Si tu quittes maintenant, cette partie ne sera pas enregistrée.',
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
    return shouldQuit;
  }

  Future<void> _onQuitPressed() async {
    final ok = await _confirmQuit();
    if (!ok || !mounted) return;
    Navigator.pop(context, true);
  }

  // ---------------------------------------------------------------------
  // Réinitialisation de l'affichage
  // ---------------------------------------------------------------------

  void _resetQuestionUi() {
    _locked = false;
    _busy = false;
    _answerState = _AnswerFeedback.none;
    _feedback = '';
    _explanation = '';
    _controller.clear();
  }

  // ---------------------------------------------------------------------
  // Badges
  // ---------------------------------------------------------------------

  Future<void> _showBadgeDialog(List<String> badges) async {
    if (!mounted || badges.isEmpty) return;

    await _playBadgeSound();
    if (!mounted) return;

    await showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'badge',
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (dialogContext, _, _) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: context.cardBackground,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: Colors.amber,
                        child: Icon(
                          Icons.emoji_events,
                          color: Colors.white,
                          size: 26,
                        ),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Nouveau badge débloqué !',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ...badges.map(
                    (b) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        '• $b',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: brandBlue,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('OK'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
      transitionBuilder: (_, anim, _, child) {
        return Transform.scale(
          scale: Curves.easeOutBack.transform(anim.value),
          child: Opacity(opacity: anim.value, child: child),
        );
      },
    );
  }

  // ---------------------------------------------------------------------
  // Fin de partie (commune aux deux modes)
  // ---------------------------------------------------------------------

  /// Ordre unique : 1) fenêtre de résultats, 2) badges, 3) action choisie.
  /// Les badges sont donc toujours affichés, même si l'élève choisit
  /// « Accueil ».
  Future<void> _finishGame({
    required bool newRecord,
    required String title,
    required Widget content,
    required vm.Exercise? lastWrong,
  }) async {
    final newBadges = await _viewModel.checkForNewBadges();
    notifyDataChanged();

    if (newRecord ||
        (_viewModel.askedCount > 0 &&
            _viewModel.successPercent == 100 &&
            _viewModel.mode == vm.VmSessionMode.fixed)) {
      _confettiController.play();
    }

    if (!mounted) return;
    final choice = await showDialog<_EndChoice>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(child: content),
        actions: [
          if (lastWrong != null)
            TextButton(
              onPressed: () => _showFullConjugation(lastWrong),
              child: const Text('Conjugaison complète'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, _EndChoice.again),
            child: const Text('Recommencer'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, _EndChoice.home),
            child: const Text('Accueil'),
          ),
        ],
      ),
    );

    if (newBadges.isNotEmpty) {
      await _showBadgeDialog(newBadges);
    }
    if (!mounted) return;

    if (choice == _EndChoice.home) {
      Navigator.pop(context, true);
      return;
    }

    await _viewModel.startNewRound();
    if (!mounted) return;
    setState(_resetQuestionUi);
  }

  Future<void> _showFixedSummary() async {
    final newRecord = await _viewModel.finalizeAndMaybeRecord();

    final finalScore = _viewModel.score;
    final record = _viewModel.highScore;
    final rank = await _viewModel.computeGlobalRank();

    final lines = StringBuffer()
      ..writeln('Score : $finalScore')
      ..writeln('Réussite : ${_viewModel.successPercent} %')
      ..writeln('Record : $record');
    if (rank != null) {
      lines.writeln();
      lines.writeln('Rang : ${rank.current.name}');
      lines.write(
        rank.isMax
            ? 'Rang maximum atteint.'
            : 'Prochain rang dans ${rank.remaining} pts : ${rank.next!.name}.',
      );
    }

    await _finishGame(
      newRecord: newRecord,
      title: newRecord ? 'Nouveau record !' : 'Fin de la session',
      content: Text(lines.toString().trim()),
      lastWrong: null,
    );
  }

  // ---------------------------------------------------------------------
  // Bonne / mauvaise réponse
  // ---------------------------------------------------------------------

  Future<void> _onCorrect(vm.Exercise ex) async {
    try {
      await AppDb.instance.incrementStat(
        ex.tenseLabel,
        correct: true,
        userId: _viewModel.userId,
      );
    } catch (_) {}

    _viewModel.registerCorrectAnswer();
    final pts = _viewModel.pointsForCurrent();

    if (!mounted) return;
    setState(() {
      _locked = true;
      _answerState = _AnswerFeedback.correct;
      _feedback = 'Bonne réponse (+$pts pts)';
      _explanation = '';
    });

    unawaited(_playCorrectFx());
  }

  Future<void> _onWrong(
    vm.Exercise ex, {
    required String expected,
    required String explanation,
    required String errorHint,
  }) async {
    try {
      await AppDb.instance.incrementStat(
        ex.tenseLabel,
        correct: false,
        userId: _viewModel.userId,
      );
    } catch (_) {}

    _viewModel.registerWrongAnswer();

    // Mode fixe : on affiche la correction et on attend « Suivant ».
    if (_viewModel.mode == vm.VmSessionMode.fixed) {
      if (!mounted) return;
      final buffer = StringBuffer()
        ..writeln('Mauvaise réponse.')
        ..write('Réponse attendue : $expected');
      if (errorHint.isNotEmpty) {
        buffer
          ..writeln()
          ..writeln()
          ..write(errorHint);
      }
      setState(() {
        _locked = true;
        _answerState = _AnswerFeedback.wrong;
        _feedback = buffer.toString();
        _explanation = explanation;
      });
      unawaited(_playWrongFx());
      return;
    }

    // Mode illimité : fin de partie à la première erreur.
    unawaited(_playWrongFx());
    if (!mounted) return;
    setState(() {
      _locked = true;
      _answerState = _AnswerFeedback.wrong;
    });

    final newRecord = await _viewModel.onWrongAnswerAndMaybeUpdateRecord();
    final finalScore = _viewModel.score;
    final record = _viewModel.highScore;

    await _finishGame(
      newRecord: newRecord,
      title: newRecord ? 'Nouveau record !' : 'Fin de la partie',
      lastWrong: ex,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Score : $finalScore\nRecord : $record'),
          const SizedBox(height: 12),
          Text('Réponse attendue : $expected'),
          if (errorHint.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(errorHint, style: const TextStyle(fontSize: 14)),
          ],
          if (explanation.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(explanation, style: const TextStyle(fontSize: 14)),
          ],
        ],
      ),
    );
  }

  String _buildErrorHint({
    required bool pronounOk,
    required bool verbOk,
    required String expectedPronoun,
  }) {
    final noPronoun = expectedPronoun == kNoPronoun || expectedPronoun.isEmpty;
    if (pronounOk && !verbOk) {
      return 'Le pronom est bon, mais la forme conjuguée est incorrecte.';
    } else if (!pronounOk && verbOk) {
      if (noPronoun) {
        return 'La forme est bonne, mais aucun pronom n’était attendu.';
      }
      return 'La forme est bonne, mais le pronom attendu était « $expectedPronoun ».';
    } else if (!pronounOk && !verbOk) {
      if (noPronoun) {
        return 'Le pronom et la forme sont incorrects. Aucun pronom n’était attendu.';
      }
      return 'Le pronom et la forme sont incorrects. Pronom attendu : « $expectedPronoun ».';
    }
    return '';
  }

  // ---------------------------------------------------------------------
  // Validation
  // ---------------------------------------------------------------------

  Future<void> _checkAnswer() async {
    // Le verrou est pris tout de suite : un double clic ou « Entrée » suivie
    // d'un clic ne peuvent plus valider deux fois la même question.
    if (_locked || _busy) return;
    final ex = _viewModel.currentExercise;
    if (ex == null) return;
    _busy = true;

    try {
      final raw = normalizeApostrophes(_controller.text).trim();
      if (raw.isEmpty) {
        setState(() {
          _emptyShake = true;
          _answerState = _AnswerFeedback.none;
          _feedback = 'Écris une réponse avant de valider.';
          _explanation = '';
        });
        await Future.delayed(const Duration(milliseconds: 250));
        if (mounted) setState(() => _emptyShake = false);
        _busy = false;
        return;
      }

      final explanation = _viewModel.getExplanationForCurrent();
      final expectedText = _viewModel.expectedDisplay(ex);

      // --- Impératif : pas de pronom ---
      if (ex.tense == vm.Tense.imperatif) {
        final (givenPronoun, rest) = splitPronounAndVerb(raw);
        const subjects = {
          'je',
          "j'",
          'tu',
          'il',
          'elle',
          'nous',
          'vous',
          'ils',
          'elles',
        };
        if (givenPronoun.isNotEmpty &&
            rest.isNotEmpty &&
            subjects.contains(givenPronoun.toLowerCase())) {
          setState(() {
            _answerState = _AnswerFeedback.none;
            _feedback =
                'À l’impératif, pas de pronom. Écris seulement la forme verbale.';
            _explanation = '';
          });
          _busy = false;
          return;
        }

        if (_viewModel.isAnswerCorrectFor(ex, raw)) {
          await _onCorrect(ex);
        } else {
          await _onWrong(
            ex,
            expected: expectedText,
            explanation: explanation,
            errorHint: 'Forme attendue : « $expectedText » (sans pronom).',
          );
        }
        return;
      }

      // --- Temps sans pronom (infinitif, participes, gérondif) ---
      if (!vm.tenseNeedsPronoun(ex.tense)) {
        if (_viewModel.isAnswerCorrectFor(ex, raw)) {
          await _onCorrect(ex);
        } else {
          await _onWrong(
            ex,
            expected: expectedText,
            explanation: explanation,
            errorHint: '',
          );
        }
        return;
      }

      // --- Temps avec pronom ---
      final (userPronoun, userVerb) = splitPronounAndVerb(raw);
      final matched = _viewModel.matchedAnswerIndex(ex, userVerb);
      final verbOk = matched >= 0;

      // Pronom attendu : « je » devient « j' » selon la forme choisie.
      final basePronoun = ex.pronoun.trim();
      var expectedPronoun = basePronoun;
      if (basePronoun == 'je' || basePronoun == "j'") {
        final form = verbOk ? ex.answers[matched] : ex.correctAnswer;
        expectedPronoun = contractPronoun('je', form);
      }
      final pronounOk = samePronoun(expectedPronoun, userPronoun);

      if (pronounOk && verbOk) {
        await _onCorrect(ex);
        return;
      }

      await _onWrong(
        ex,
        expected: expectedText,
        explanation: explanation,
        errorHint: _buildErrorHint(
          pronounOk: pronounOk,
          verbOk: verbOk,
          expectedPronoun: expectedPronoun.isEmpty
              ? kNoPronoun
              : expectedPronoun,
        ),
      );
    } finally {
      // En mode illimité après une erreur, _finishGame remet l'écran à zéro.
      // Dans les autres cas, _locked prend le relais.
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------------------------------------------------------------------
  // Suivant
  // ---------------------------------------------------------------------

  bool get _isLastFixedQuestion =>
      _viewModel.mode == vm.VmSessionMode.fixed &&
      _viewModel.targetCount > 0 &&
      _viewModel.askedCount >= _viewModel.targetCount;

  Future<void> _onNext() async {
    if (_busy) return;
    _busy = true;
    try {
      if (_isLastFixedQuestion) {
        await _showFixedSummary();
        return;
      }
      await _viewModel.nextExercise();
      if (!mounted) return;
      setState(_resetQuestionUi);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showFullConjugation(vm.Exercise ex) {
    final full = _viewModel.getFullConjugationForExercise(ex);

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('Conjugaison de « ${ex.verb} » (${ex.tenseLabel})'),
          content: full.isEmpty
              ? const Text(
                  'Conjugaison complète non disponible pour ce verbe/temps.',
                )
              : SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: full.entries
                        .map((e) => Text('${e.key} → ${e.value}'))
                        .toList(),
                  ),
                ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Fermer'),
            ),
          ],
        );
      },
    );
  }

  String _levelChipLabel() {
    switch (_viewModel.level) {
      case vm.GameLevel.level_cycle1:
        return 'Niveau 1';
      case vm.GameLevel.level_cycle2:
        return 'Niveau 2';
      case vm.GameLevel.level_cycle3:
        return 'Niveau 3';
      case vm.GameLevel.level_sec1:
        return 'Niveau 4';
      case vm.GameLevel.level_sec2:
        return 'Niveau 5';
      case vm.GameLevel.expert:
        return 'Expert';
    }
  }

  // ---------------------------------------------------------------------
  // Interface
  // ---------------------------------------------------------------------

  Widget _buildLoading() {
    final failed = _initDone && _viewModel.loadFailed;
    return Scaffold(
      appBar: AppBar(backgroundColor: brandBlue, foregroundColor: Colors.white),
      body: Center(
        child: failed
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, size: 40),
                    const SizedBox(height: 12),
                    const Text(
                      'Impossible de charger un exercice pour ce niveau.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () async {
                        setState(() => _initDone = false);
                        await _viewModel.nextExercise();
                        if (mounted) setState(() => _initDone = true);
                      },
                      child: const Text('Réessayer'),
                    ),
                  ],
                ),
              )
            : const CircularProgressIndicator(),
      ),
    );
  }

  Widget _buildFeedbackBox() {
    final isCorrect = _answerState == _AnswerFeedback.correct;
    final isWrong = _answerState == _AnswerFeedback.wrong;
    final color = isCorrect
        ? Colors.green
        : isWrong
        ? Colors.red
        : Colors.blueGrey;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      transitionBuilder: (child, animation) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOut,
        );
        if (isCorrect) {
          return FlashBackground(
            animation: curved,
            isCorrect: true,
            child: PopAnimation(animation: curved, child: child),
          );
        } else if (isWrong) {
          return FlashBackground(
            animation: curved,
            isCorrect: false,
            child: ShakeAnimation(animation: curved, child: child),
          );
        }
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.95, end: 1).animate(curved),
            child: child,
          ),
        );
      },
      child: _feedback.isEmpty
          ? const SizedBox.shrink()
          : Container(
              key: ValueKey<String>(_feedback + _answerState.toString()),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: .10),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: color, width: 1),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    isCorrect
                        ? Icons.check_circle
                        : isWrong
                        ? Icons.cancel
                        : Icons.info_outline,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      _feedback,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ex = _viewModel.currentExercise;
    if (ex == null) return _buildLoading();

    final needsPronoun = vm.tenseNeedsPronoun(ex.tense);
    final personDesc = personLabel(
      ex.pronoun.trim().isEmpty ? kNoPronoun : ex.pronoun.trim(),
    );

    final String headerText = (ex.tense == vm.Tense.imperatif || needsPronoun)
        ? 'Temps demandé : ${ex.tenseLabel} – $personDesc'
        : 'Temps demandé : ${ex.tenseLabel}';

    final isFixed = _viewModel.mode == vm.VmSessionMode.fixed;
    final showProgress = isFixed && _viewModel.targetCount > 0;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final ok = await _confirmQuit();
        if (ok && context.mounted) Navigator.pop(context, true);
      },
      child: Scaffold(
        appBar: AppBar(
          centerTitle: true,
          backgroundColor: brandBlue,
          foregroundColor: Colors.white,
          title: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (isFixed) ...[
                  Text(
                    'Réussite : ${_viewModel.successPercent} %',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(width: 16),
                  if (showProgress) ...[
                    Text(
                      _viewModel.progressLabel,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(width: 16),
                  ],
                ],
                Text(
                  'Score : ${_viewModel.score}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
        body: Stack(
          children: [
            Container(
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
                              Chip(label: Text(_levelChipLabel())),
                              const SizedBox(height: 8),
                              Text(
                                needsPronoun
                                    ? 'Écris le pronom et conjugue le verbe suivant :'
                                    : 'Conjugue le verbe suivant :',
                                style: Theme.of(context).textTheme.titleMedium,
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                ex.verb,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                headerText,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 28),
                              AbsorbPointer(
                                absorbing: _locked,
                                child: Opacity(
                                  opacity: _locked ? 0.7 : 1,
                                  child: AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 200),
                                    transitionBuilder: (child, animation) {
                                      if (_emptyShake) {
                                        return ShakeAnimation(
                                          animation: animation,
                                          child: child,
                                        );
                                      }
                                      return FadeTransition(
                                        opacity: animation,
                                        child: child,
                                      );
                                    },
                                    child: TextField(
                                      key: ValueKey<bool>(_emptyShake),
                                      controller: _controller,
                                      autofocus: true,
                                      autocorrect: false,
                                      enableSuggestions: false,
                                      textInputAction: TextInputAction.done,
                                      onSubmitted: (_) => _checkAnswer(),
                                      decoration: InputDecoration(
                                        hintText:
                                            'Exemple : il fait, j’aime, tu es allé…',
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                        ),
                                        contentPadding:
                                            const EdgeInsets.symmetric(
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
                                  onPressed: (_locked || _busy)
                                      ? null
                                      : _checkAnswer,
                                  icon: const Icon(Icons.check),
                                  label: const Text('Valider'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: brandBlue,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 14,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              _buildFeedbackBox(),
                              if (_explanation.isNotEmpty) ...[
                                const SizedBox(height: 10),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: brandBlue.withValues(alpha: .06),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    _explanation,
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                ),
                              ],
                              if (_locked && isFixed) ...[
                                const SizedBox(height: 8),
                                TextButton(
                                  onPressed: () => _showFullConjugation(ex),
                                  child: const Text(
                                    'Voir la conjugaison complète',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: brandBlue,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: ElevatedButton.icon(
                                    onPressed: _busy ? null : _onNext,
                                    icon: Icon(
                                      _isLastFixedQuestion
                                          ? Icons.flag
                                          : Icons.arrow_forward,
                                    ),
                                    label: Text(
                                      _isLastFixedQuestion
                                          ? 'Voir le résultat'
                                          : 'Suivant',
                                    ),
                                  ),
                                ),
                              ],
                              if (_locked &&
                                  _answerState == _AnswerFeedback.correct &&
                                  !isFixed) ...[
                                const SizedBox(height: 12),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: ElevatedButton.icon(
                                    onPressed: _busy ? null : _onNext,
                                    icon: const Icon(Icons.arrow_forward),
                                    label: const Text('Suivant'),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 16),
                              TextButton.icon(
                                onPressed: _onQuitPressed,
                                icon: const Icon(Icons.exit_to_app),
                                label: const Text('Quitter la partie'),
                                style: TextButton.styleFrom(
                                  foregroundColor: Colors.red,
                                ),
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
            Align(
              alignment: Alignment.topCenter,
              child: ConfettiWidget(
                confettiController: _confettiController,
                blastDirectionality: BlastDirectionality.explosive,
                shouldLoop: false,
                emissionFrequency: 0.05,
                numberOfParticles: 25,
                maxBlastForce: 30,
                minBlastForce: 10,
                gravity: 0.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
