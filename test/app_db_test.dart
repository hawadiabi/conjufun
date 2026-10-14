import 'package:flutter_test/flutter_test.dart';
import 'package:conjufun/data/app_db.dart';
import 'package:conjufun/models/custom_set.dart';

import 'helpers/test_db.dart';

CustomSet _set(String name, {int? maxQuestions}) => CustomSet.newLocal(
  name: name,
  schoolLevel: 'level_cycle1',
  tenses: ['présent'],
  verbs: ['aimer'],
  maxQuestions: maxQuestions,
);

Future<int> _user(String prefix) async => AppDb.instance.insertUser(
  email: uniqueEmail(prefix),
  passwordHash: 'h',
  salt: 's',
  displayName: prefix,
);

Future<void> _run(
  int? userId, {
  String mode = 'fixed',
  String level = 'level_cycle1',
  int correct = 5,
  int score = 25,
  int target = 10,
  DateTime? at,
}) => AppDb.instance.insertRun(
  startedAt: at ?? DateTime.now(),
  mode: mode,
  level: level,
  totalTarget: target,
  correctCount: correct,
  score: score,
  userId: userId,
);

void main() {
  final db = AppDb.instance;

  setUpAll(initTestDb);
  setUp(resetTestData);
  tearDownAll(disposeTestDb);

  group('Utilisateurs', () {
    test('insertion, lecture par courriel et par id', () async {
      final email = uniqueEmail();
      final id = await db.insertUser(
        email: '  ${email.toUpperCase()}',
        passwordHash: 'h',
        salt: 's',
        displayName: 'Test',
      );
      expect((await db.getUserByEmail(email))!['id'], id);
      expect((await db.getUserById(id))!['email'], email);
      expect(await db.getUserById(id + 1000), isNull);
    });

    test('courriel unique', () async {
      final email = uniqueEmail();
      await db.insertUser(email: email, passwordHash: 'h', salt: 's');
      expect(
        () => db.insertUser(email: email, passwordHash: 'h', salt: 's'),
        throwsA(anything),
      );
    });

    test('résultat du test de niveau', () async {
      final id = await _user('niveau');
      await db.setUserLevelTestResult(userId: id, levelString: 'level_sec1');
      final r = await db.getUserLevelTestResult(id);
      expect(r!['has_done_level_test'], 1);
      expect(r['last_recommended_level'], 'level_sec1');
    });
  });

  group('Parties : isolation par utilisateur', () {
    test('score total, records et historique sont séparés', () async {
      final a = await _user('a');
      final b = await _user('b');
      await _run(null, score: 10, at: DateTime(2026, 1, 1));
      await _run(a, score: 40, at: DateTime(2026, 1, 2));
      await _run(a, score: 60, at: DateTime(2026, 1, 3));
      await _run(b, score: 500, at: DateTime(2026, 1, 4));

      expect(await db.getTotalScore(userId: null), 10);
      expect(await db.getTotalScore(userId: a), 100);
      expect(await db.getTotalScore(userId: b), 500);
      expect(await db.getTotalScoreForUser(a), 100);
      expect(await db.getTotalScoreForUser(null), 0);

      expect(
        await db.getRecordByLevelAndMode(
          level: 'level_cycle1',
          mode: 'fixed',
          userId: a,
        ),
        60,
      );
      expect(
        await db.getRecordByLevelAndMode(
          level: 'level_cycle1',
          mode: 'fixed',
          userId: null,
        ),
        10,
      );
      expect(await db.getRuns(mode: 'fixed', userId: a), hasLength(2));
      expect(await db.getRuns(mode: 'fixed', userId: b), hasLength(1));
      expect(await db.getRuns(mode: 'fixed', userId: null), hasLength(1));
    });

    test('record du mode illimité : seulement ce mode et ce niveau', () async {
      final a = await _user('rec');
      await _run(
        a,
        mode: 'unlimited',
        level: 'expert',
        score: 80,
        at: DateTime(2026, 1, 1),
      );
      await _run(
        a,
        mode: 'fixed',
        level: 'expert',
        score: 999,
        at: DateTime(2026, 1, 2),
      );
      expect(await db.getUnlimitedRecord(userId: a), 80);
      expect(await db.getRecordByLevel('expert', userId: a), 80);
      expect(await db.getRecordByLevel('level_cycle1', userId: a), 0);
    });

    test('taux de réussite par mode', () async {
      final a = await _user('succes');
      await _run(a, correct: 7, target: 10, at: DateTime(2026, 1, 1));
      await _run(a, correct: 3, target: 10, at: DateTime(2026, 1, 2));
      final s = await db.getRunsSuccess('fixed', userId: a);
      expect(s['runs'], 2);
      expect(s['correct'], 10);
      expect(s['total'], 20);
      expect(await db.getTotalCorrectAnswers(a), 10);
      expect(await db.getTotalSessions(a), 2);
    });

    test('userHasPlayedExpert', () async {
      final a = await _user('exp');
      expect(await db.userHasPlayedExpert(a), isFalse);
      await _run(a, level: 'expert');
      expect(await db.userHasPlayedExpert(a), isTrue);
    });
  });

  group('Statistiques par temps', () {
    test('incrémentation et séparation invité / compte', () async {
      final a = await _user('stats');
      await db.incrementStat('présent', correct: true, userId: a);
      await db.incrementStat('présent', correct: true, userId: a);
      await db.incrementStat('présent', correct: false, userId: a);
      await db.incrementStat('présent', correct: true); // invité

      final byTense = await db.getStatsByTense(userId: a);
      expect(byTense, hasLength(1));
      expect(byTense.first['correct'], 2);
      expect(byTense.first['wrong'], 1);

      final global = await db.getGlobalStats(userId: a);
      expect(global['correct'], 2);
      expect(global['wrong'], 1);
      expect((await db.getGlobalStats(userId: null))['correct'], 1);
    });
  });

  group('Rattachement des données de l\'invité', () {
    test('fusion des statistiques avec celles du compte', () async {
      final a = await _user('fusion');
      await db.incrementStat('présent', correct: true, userId: a);
      await db.incrementStat('présent', correct: false, userId: a);
      await db.incrementStat('présent', correct: true); // invité
      await db.incrementStat('présent', correct: true); // invité
      await db.incrementStat('imparfait', correct: false); // invité

      await db.attachGuestRunsToUser(a);

      final byTense = {
        for (final r in await db.getStatsByTense(userId: a)) r['tense']: r,
      };
      expect(byTense['présent']!['correct'], 3);
      expect(byTense['présent']!['wrong'], 1);
      expect(byTense['imparfait']!['wrong'], 1);
      expect(await db.getStatsByTense(userId: null), isEmpty);
    });

    test(
      'parties et ensembles de l\'invité passent au compte, à synchroniser',
      () async {
        final a = await _user('attach');
        await _run(null, score: 20);
        final keep = await db.insertCustomSet(_set('Garde'), userId: null);
        final gone = await db.insertCustomSet(_set('Supprimé'), userId: null);
        await db.deleteCustomSet(gone);

        await db.attachGuestRunsToUser(a);

        expect(await db.getTotalScore(userId: a), 20);
        expect(await db.getTotalScore(userId: null), 0);
        final sets = await db.getCustomSets(userId: a);
        expect(sets.map((s) => s.name), ['Garde']);
        expect(sets.first.id, keep);
        expect(sets.first.needsSync, isTrue);
      },
    );
  });

  group('Séries de jours (streak)', () {
    test('premier jour, même jour, jour suivant, jour sauté', () async {
      final a = await _user('streak');
      Future<Map<String, int>> play(DateTime d) =>
          db.updateStreakAfterSession(userId: a, sessionTime: d);

      expect(await play(DateTime(2020, 1, 1, 23, 50)), {
        'current': 1,
        'best': 1,
      });
      expect(await play(DateTime(2020, 1, 1, 23, 59)), {
        'current': 1,
        'best': 1,
      });
      // Deux minutes plus tard, mais jour calendaire suivant.
      expect(await play(DateTime(2020, 1, 2, 0, 1)), {'current': 2, 'best': 2});
      expect(await play(DateTime(2020, 1, 3, 12)), {'current': 3, 'best': 3});
      // Un jour entier sauté : retour à 1, le meilleur est conservé.
      expect(await play(DateTime(2020, 1, 5, 12)), {'current': 1, 'best': 3});
    });

    test('une série ancienne est expirée à la lecture', () async {
      final a = await _user('expire');
      await db.updateStreakAfterSession(
        userId: a,
        sessionTime: DateTime(2020, 1, 1),
      );
      await db.updateStreakAfterSession(
        userId: a,
        sessionTime: DateTime(2020, 1, 2),
      );
      final s = await db.getStreakForUser(a);
      expect(s['current'], 0);
      expect(s['best'], 2);
    });

    test('une série du jour est conservée', () async {
      final a = await _user('aujourdhui');
      await db.updateStreakAfterSession(userId: a, sessionTime: DateTime.now());
      expect((await db.getStreakForUser(a))['current'], 1);
    });

    test('utilisateur inconnu', () async {
      expect(await db.getStreakForUser(424242), {'current': 0, 'best': 0});
    });
  });

  group('Badges', () {
    test(
      'un badge ne s\'obtient qu\'une fois et appartient à un seul compte',
      () async {
        final a = await _user('b1');
        final b = await _user('b2');
        expect(await db.userHasBadge(a, 'correct_10'), isFalse);

        await db.insertBadge(userId: a, code: 'correct_10', title: 'Dix');
        await db.insertBadge(userId: a, code: 'correct_10', title: 'Dix');

        expect(await db.userHasBadge(a, 'correct_10'), isTrue);
        expect(await db.userHasBadge(b, 'correct_10'), isFalse);
        expect(await db.getBadgesForUser(a), hasLength(1));
        expect(await db.getBadgesForUser(b), isEmpty);
      },
    );
  });

  group('Ensembles du mode créateur', () {
    test('isolation invité / comptes', () async {
      final a = await _user('c1');
      final b = await _user('c2');
      await db.insertCustomSet(_set('Invité'), userId: null);
      await db.insertCustomSet(_set('A'), userId: a);
      await db.insertCustomSet(_set('B'), userId: b);

      expect((await db.getCustomSets(userId: null)).map((s) => s.name), [
        'Invité',
      ]);
      expect((await db.getCustomSets(userId: a)).map((s) => s.name), ['A']);
      expect((await db.getCustomSets(userId: b)).map((s) => s.name), ['B']);
    });

    test('un nouvel ensemble est à synchroniser', () async {
      final a = await _user('c3');
      await db.insertCustomSet(_set('Neuf'), userId: a);
      final toSync = await db.getCustomSetsToSync(userId: a);
      expect(toSync, hasLength(1));
      expect(toSync.first.name, 'Neuf');
    });

    test('modification', () async {
      final a = await _user('c4');
      final id = await db.insertCustomSet(
        _set('Avant', maxQuestions: 5),
        userId: a,
      );
      final stored = (await db.getCustomSets(userId: a)).first;
      expect(stored.id, id);

      await db.updateCustomSet(
        stored.copyWith(name: 'Après', maxQuestions: 12),
      );

      final after = (await db.getCustomSets(userId: a)).first;
      expect(after.name, 'Après');
      expect(after.maxQuestions, 12);
      expect(after.needsSync, isTrue);
    });

    test(
      'suppression logique : cachée mais conservée pour la synchro',
      () async {
        final a = await _user('c5');
        final id = await db.insertCustomSet(_set('À supprimer'), userId: a);

        await db.deleteCustomSet(id);

        expect(await db.getCustomSets(userId: a), isEmpty);
        final toSync = await db.getCustomSetsToSync(userId: a);
        expect(toSync, hasLength(1));
        expect(toSync.first.isDeleted, isTrue);
        expect(toSync.first.deletedAt, isNotNull);
      },
    );

    test('markCustomSetSynced', () async {
      final a = await _user('c6');
      final id = await db.insertCustomSet(_set('Sync'), userId: a);
      await db.markCustomSetSynced(
        localId: id,
        remoteId: 'srv-1',
        remoteUpdatedAt: DateTime.utc(2026, 6, 1),
      );
      expect(await db.getCustomSetsToSync(userId: a), isEmpty);
      final s = (await db.getCustomSets(userId: a)).first;
      expect(s.remoteId, 'srv-1');
      expect(s.needsSync, isFalse);
    });

    test(
      'upsert depuis le serveur : insertion puis mise à jour, sans doublon',
      () async {
        final a = await _user('c7');
        final remote = CustomSet(
          remoteId: 'srv-9',
          name: 'Serveur',
          tenses: const ['futur simple'],
          verbs: const ['finir'],
          createdAt: DateTime.utc(2026, 1, 1),
          updatedAt: DateTime.utc(2026, 1, 1),
        );
        final id1 = await db.upsertCustomSetFromRemote(remote, userId: a);
        final id2 = await db.upsertCustomSetFromRemote(
          remote.copyWith(name: 'Serveur v2'),
          userId: a,
        );
        expect(id2, id1);
        final sets = await db.getCustomSets(userId: a);
        expect(sets, hasLength(1));
        expect(sets.first.name, 'Serveur v2');
        expect(sets.first.needsSync, isFalse);
      },
    );

    test('upsert sans remoteId refusé', () async {
      final a = await _user('c8');
      expect(
        () => db.upsertCustomSetFromRemote(_set('X'), userId: a),
        throwsArgumentError,
      );
    });
  });

  group('Verbes (LEFFF importé)', () {
    test('la table des verbes est remplie', () async {
      expect(await db.getDistinctVerbs(), isNotEmpty);
      expect(await db.getDistinctTenses(), contains('présent'));
      expect(await db.getRandomExerciseRaw(), isNotNull);
    });

    test(
      'exercice tiré d\'un ensemble : respecte les verbes et les temps',
      () async {
        final raw = (await db.getRandomExerciseRaw())!;
        final set = CustomSet.newLocal(
          name: 'Précis',
          tenses: [raw['tense'] as String],
          verbs: [raw['verb'] as String],
        );
        for (var i = 0; i < 5; i++) {
          final ex = await db.getRandomExerciseForCustomSet(set);
          expect(ex, isNotNull);
          expect(ex!['verb'], raw['verb']);
          expect(ex['tense'], raw['tense']);
        }
      },
    );

    test('ensemble sans verbe ou sans temps : aucun exercice', () async {
      expect(
        await db.getRandomExerciseForCustomSet(
          CustomSet.newLocal(name: 'v', tenses: ['présent'], verbs: []),
        ),
        isNull,
      );
      expect(
        await db.getRandomExerciseForCustomSet(
          CustomSet.newLocal(name: 't', tenses: [], verbs: ['aimer']),
        ),
        isNull,
      );
    });
  });
}
