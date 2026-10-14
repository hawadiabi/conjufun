import 'package:flutter_test/flutter_test.dart';
import 'package:conjufun/config/levels_config.dart';
import 'package:conjufun/data/app_db.dart';
import 'package:conjufun/data/badge_catalog.dart';
import 'package:conjufun/models/custom_set.dart';
import 'package:conjufun/session_notifier.dart';
import 'package:conjufun/viewmodels/answer_utils.dart';
import 'package:conjufun/viewmodels/exercise_vm.dart';

import 'helpers/test_db.dart';

Exercise _ex({
  String answer = 'mange',
  List<String> alt = const [],
  Tense tense = Tense.present,
}) => Exercise(
  infinitif: 'manger',
  pronom: 'il',
  reponseAttendue: answer,
  tense: tense,
  alternatives: alt,
);

Future<ExerciseViewModel> _vm({
  int? userId,
  VmSessionMode mode = VmSessionMode.unlimited,
  int fixedCount = 10,
  GameLevel level = GameLevel.level_cycle1,
  CustomSet? set,
}) async {
  final vm = ExerciseViewModel();
  vm.setCurrentUserId(userId);
  await vm.configureSession(
    mode: mode,
    fixedCount: fixedCount,
    level: level,
    customSet: set,
  );
  return vm;
}

Future<int> _newUser() => AppDb.instance.insertUser(
  email: uniqueEmail('vm'),
  passwordHash: 'h',
  salt: 's',
);

void main() {
  setUpAll(initTestDb);
  setUp(resetTestData);
  tearDownAll(disposeTestDb);

  group('Vérification des réponses', () {
    final vm = ExerciseViewModel();

    test('réponse exacte, casse et espaces ignorés', () {
      final ex = _ex(answer: 'mange');
      expect(vm.isAnswerCorrectFor(ex, 'mange'), isTrue);
      expect(vm.isAnswerCorrectFor(ex, '  MANGE '), isTrue);
      expect(vm.isAnswerCorrectFor(ex, 'manges'), isFalse);
    });

    test('apostrophes typographiques et droites équivalentes', () {
      final ex = _ex(answer: "s'en va");
      expect(vm.isAnswerCorrectFor(ex, 's’en va'), isTrue);
      expect(vm.isAnswerCorrectFor(ex, "s'en  va"), isTrue);
    });

    test('les accents comptent', () {
      final ex = _ex(answer: 'mangé');
      expect(vm.isAnswerCorrectFor(ex, 'mange'), isFalse);
      expect(vm.isAnswerCorrectFor(ex, 'mangé'), isTrue);
    });

    test('alternatives acceptées et index retourné', () {
      final ex = _ex(answer: 'est sorti', alt: ['a sorti']);
      expect(vm.matchedAnswerIndex(ex, 'est sorti'), 0);
      expect(vm.matchedAnswerIndex(ex, 'a sorti'), 1);
      expect(vm.matchedAnswerIndex(ex, 'sortit'), -1);
    });

    test('réponse vide refusée', () {
      expect(vm.matchedAnswerIndex(_ex(), ''), -1);
      expect(vm.matchedAnswerIndex(_ex(), '   '), -1);
    });

    test('Exercise.answers = principale puis alternatives', () {
      expect(_ex(answer: 'a', alt: ['b', 'c']).answers, ['a', 'b', 'c']);
    });

    test('sans exercice courant, isAnswerCorrect est faux', () {
      expect(ExerciseViewModel().isAnswerCorrect('mange'), isFalse);
    });
  });

  group('Temps', () {
    test('tenseNeedsPronoun', () {
      expect(tenseNeedsPronoun(Tense.present), isTrue);
      expect(tenseNeedsPronoun(Tense.passeCompose), isTrue);
      for (final t in [
        Tense.imperatif,
        Tense.infinitif,
        Tense.infinitifPasse,
        Tense.gerondif,
        Tense.participePresent,
        Tense.participePasse,
      ]) {
        expect(tenseNeedsPronoun(t), isFalse, reason: '$t');
      }
    });

    test('libellés uniques pour tous les temps', () {
      final labels = Tense.values.map((t) => t.label).toList();
      expect(labels.toSet().length, labels.length);
      expect(
        ExerciseViewModel.allTenseLabels(),
        hasLength(kAllSupportedTenses.length),
      );
    });
  });

  group('Configuration de la session', () {
    test('mode illimité', () async {
      final vm = await _vm();
      expect(vm.mode, VmSessionMode.unlimited);
      expect(vm.targetCount, 0);
      expect(vm.progressLabel, '');
      expect(vm.score, 0);
    });

    test('mode fixe', () async {
      final vm = await _vm(mode: VmSessionMode.fixed, fixedCount: 15);
      expect(vm.mode, VmSessionMode.fixed);
      expect(vm.targetCount, 15);
      expect(vm.progressLabel, '0/15');
    });

    test('un ensemble avec nombre de questions impose le mode fixe', () async {
      final vm = await _vm(
        mode: VmSessionMode.unlimited,
        set: CustomSet.newLocal(
          name: 'S',
          tenses: ['présent'],
          verbs: ['aimer'],
          maxQuestions: 7,
        ),
      );
      expect(vm.mode, VmSessionMode.fixed);
      expect(vm.targetCount, 7);
    });
  });

  group('Points et compteurs', () {
    test('points par bonne réponse selon le niveau', () async {
      for (final level in GameLevel.values) {
        final vm = await _vm(level: level);
        vm.registerCorrectAnswer();
        vm.registerCorrectAnswer();
        expect(vm.score, 2 * level.pointsPerAnswer, reason: '$level');
        expect(vm.correctCount, 2);
      }
    });

    test(
      'une mauvaise réponse compte comme question répondue, sans points',
      () async {
        final vm = await _vm(mode: VmSessionMode.fixed, fixedCount: 10);
        vm.registerCorrectAnswer();
        vm.registerWrongAnswer();
        vm.registerWrongAnswer();
        expect(vm.score, GameLevel.level_cycle1.pointsPerAnswer);
        expect(vm.askedCount, 3);
        expect(vm.correctCount, 1);
        expect(vm.progressLabel, '3/10');
        expect(vm.successPercent, 33);
      },
    );

    test('taux de réussite sans réponse', () async {
      expect((await _vm()).successPercent, 0);
    });
  });

  group('Fin de partie et enregistrement', () {
    test(
      'mode illimité : la partie est enregistrée, premier score pas un record',
      () async {
        final uid = await _newUser();
        final vm = await _vm(userId: uid);
        vm.registerCorrectAnswer();
        vm.registerCorrectAnswer();
        vm.registerWrongAnswer();

        final before = dataVersion.value;
        final isRecord = await vm.onWrongAnswerAndMaybeUpdateRecord();

        expect(isRecord, isFalse);
        expect(dataVersion.value, greaterThan(before));
        final runs = await AppDb.instance.getRuns(
          mode: 'unlimited',
          userId: uid,
        );
        expect(runs, hasLength(1));
        expect(runs.first['level'], 'level_cycle1');
        expect(runs.first['correct_count'], 2);
        expect(runs.first['score'], 2 * GameLevel.level_cycle1.pointsPerAnswer);
        expect(runs.first['total_target'], 3); // questions répondues
      },
    );

    test('mode illimité : battre son record est détecté', () async {
      final uid = await _newUser();

      var vm = await _vm(userId: uid);
      vm.registerCorrectAnswer();
      vm.registerWrongAnswer();
      await vm.onWrongAnswerAndMaybeUpdateRecord();

      await Future<void>.delayed(const Duration(milliseconds: 5));
      vm = await _vm(userId: uid);
      for (var i = 0; i < 3; i++) {
        vm.registerCorrectAnswer();
      }
      vm.registerWrongAnswer();
      expect(await vm.onWrongAnswerAndMaybeUpdateRecord(), isTrue);
      expect(vm.highScore, 3 * GameLevel.level_cycle1.pointsPerAnswer);

      await Future<void>.delayed(const Duration(milliseconds: 5));
      vm = await _vm(userId: uid);
      vm.registerCorrectAnswer();
      vm.registerWrongAnswer();
      expect(await vm.onWrongAnswerAndMaybeUpdateRecord(), isFalse);
    });

    test('mode fixe : total visé enregistré', () async {
      final uid = await _newUser();
      final vm = await _vm(
        userId: uid,
        mode: VmSessionMode.fixed,
        fixedCount: 10,
      );
      for (var i = 0; i < 7; i++) {
        vm.registerCorrectAnswer();
      }
      for (var i = 0; i < 3; i++) {
        vm.registerWrongAnswer();
      }
      await vm.finalizeAndMaybeRecord();

      final runs = await AppDb.instance.getRuns(mode: 'fixed', userId: uid);
      expect(runs, hasLength(1));
      expect(runs.first['total_target'], 10);
      expect(runs.first['correct_count'], 7);
    });

    test(
      'un invité : partie enregistrée côté invité, sans série ni rang',
      () async {
        final vm = await _vm(userId: null);
        vm.registerCorrectAnswer();
        await vm.onWrongAnswerAndMaybeUpdateRecord();

        expect(
          await AppDb.instance.getRuns(mode: 'unlimited', userId: null),
          hasLength(1),
        );
        expect(vm.currentStreak, 0);
        expect(await vm.computeGlobalRank(), isNull);
        expect(await vm.checkForNewBadges(), isEmpty);
      },
    );

    test('un compte : la série démarre à 1 après une partie', () async {
      final uid = await _newUser();
      final vm = await _vm(userId: uid);
      vm.registerCorrectAnswer();
      await vm.onWrongAnswerAndMaybeUpdateRecord();
      expect(vm.currentStreak, 1);
      expect(vm.bestStreak, 1);
    });

    test('rang global = rang du score total du compte', () async {
      final uid = await _newUser();
      final vm = await _vm(userId: uid, level: GameLevel.expert);
      for (var i = 0; i < 3; i++) {
        vm.registerCorrectAnswer();
      }
      await vm.finalizeAndMaybeRecord();

      final rank = await vm.computeGlobalRank();
      final expected = rankForScore(3 * GameLevel.expert.pointsPerAnswer);
      expect(rank!.current.name, expected.current.name);
      expect(rank.remaining, expected.remaining);
    });
  });

  group('Badges', () {
    test(
      'débloque exactement les badges dont la condition est remplie, une seule fois',
      () async {
        final uid = await _newUser();
        final vm = await _vm(userId: uid, level: GameLevel.expert);
        const good = 12;
        for (var i = 0; i < good; i++) {
          vm.registerCorrectAnswer();
        }
        vm.registerWrongAnswer();
        await vm.onWrongAnswerAndMaybeUpdateRecord();

        final score = good * GameLevel.expert.pointsPerAnswer;
        final expectedCodes = kBadgeCatalog
            .where((b) {
              switch (b.kind) {
                case BadgeKind.correct:
                  return good >= b.threshold;
                case BadgeKind.sessions:
                  return 1 >= b.threshold;
                case BadgeKind.score:
                  return score >= b.threshold;
                case BadgeKind.streak:
                  return 1 >= b.threshold;
              }
            })
            .map((b) => b.code)
            .toSet();

        final messages = await vm.checkForNewBadges();
        final owned = (await AppDb.instance.getBadgesForUser(
          uid,
        )).map((r) => r['code'] as String).toSet();

        expect(owned, expectedCodes);
        expect(messages, hasLength(expectedCodes.length));
        expect(owned, contains('correct_10'));

        // Deuxième appel : rien de nouveau.
        expect(await vm.checkForNewBadges(), isEmpty);
      },
    );
  });

  group('Génération d\'exercices (vrais fichiers LEFFF)', () {
    late ExerciseViewModel vm;

    setUp(() async {
      vm = await _vm(level: GameLevel.level_cycle1);
      await vm.init();
    });

    test(
      'chaque exercice du niveau 1 est valide et accepte sa propre réponse',
      () async {
        final allowed = kLevelVerbs[GameLevel.level_cycle1]!.toSet();
        final tenses = kLevelTenses[GameLevel.level_cycle1]!
            .map((t) => t.label)
            .toSet();

        for (var i = 0; i < 60; i++) {
          await vm.nextExercise();
          final ex = vm.currentExercise;
          expect(vm.loadFailed, isFalse);
          expect(ex, isNotNull);
          expect(allowed, contains(ex!.verb), reason: 'verbe hors niveau');
          expect(tenses, contains(ex.tense.label), reason: 'temps hors niveau');
          expect(ex.reponseAttendue.trim(), isNotEmpty);
          expect(vm.isAnswerCorrect(ex.reponseAttendue), isTrue);
          for (final alt in ex.alternatives) {
            expect(vm.isAnswerCorrect(alt), isTrue);
          }
        }
      },
    );

    test('le pronom est cohérent avec le temps', () async {
      for (var i = 0; i < 60; i++) {
        await vm.nextExercise();
        final ex = vm.currentExercise!;
        if (!tenseNeedsPronoun(ex.tense) && ex.tense != Tense.imperatif) {
          expect(ex.pronom, kNoPronoun, reason: ex.tense.label);
        } else {
          expect(ex.pronom, isNot(kNoPronoun), reason: ex.tense.label);
        }
      }
    });

    test('« je » est contracté d\'après la forme attendue', () async {
      for (var i = 0; i < 200; i++) {
        await vm.nextExercise();
        final ex = vm.currentExercise!;
        if (ex.pronom == 'je' || ex.pronom == "j'") {
          expect(
            ex.pronom,
            contractPronoun('je', ex.reponseAttendue),
            reason: '${ex.verb} ${ex.tense.label} ${ex.reponseAttendue}',
          );
        }
      }
    });

    test('exercice pour un niveau et un temps donnés', () async {
      for (final t in [Tense.present, Tense.imparfait, Tense.futur]) {
        final ex = await vm.generateExerciseForLevelAndTense(
          GameLevel.level_cycle1,
          t,
        );
        expect(ex, isNotNull, reason: t.label);
        expect(ex!.tense, t);
      }
    });

    test('ensemble personnalisé : seulement ses verbes et ses temps', () async {
      final verbs = kLevelVerbs[GameLevel.level_cycle1]!.take(3).toList();
      final set = CustomSet.newLocal(
        name: 'Perso',
        tenses: [Tense.present.label, Tense.futur.label],
        verbs: verbs,
      );
      final custom = await _vm(set: set);
      await custom.init();

      for (var i = 0; i < 40; i++) {
        await custom.nextExercise();
        final ex = custom.currentExercise!;
        expect(verbs, contains(ex.verb));
        expect([Tense.present, Tense.futur], contains(ex.tense));
      }
    });

    test('ensemble personnalisé inutilisable : loadFailed', () async {
      final set = CustomSet.newLocal(
        name: 'Vide',
        tenses: ['temps inventé'],
        verbs: ['verbe-inventé'],
      );
      final custom = await _vm(set: set);
      await custom.init();
      await custom.nextExercise();
      expect(custom.loadFailed, isTrue);
      expect(custom.currentExercise, isNull);
    });

    test('conjugaison complète disponible pour l\'exercice courant', () async {
      await vm.nextExercise();
      final full = vm.getFullConjugationForCurrent();
      expect(full, isNotEmpty);
    });
  });
}
