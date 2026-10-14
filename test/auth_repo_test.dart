import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:conjufun/data/app_db.dart';
import 'package:conjufun/data/auth_repo.dart';
import 'package:conjufun/models/custom_set.dart';
import 'package:conjufun/session_notifier.dart';

import 'helpers/test_db.dart';

const _pwd = 'Motdepasse1';

Future<void> _expectAuthError(
  Future<void> Function() action,
  String fragment,
) async {
  try {
    await action();
    fail('Une AuthException était attendue');
  } on AuthException catch (e) {
    expect(e.message, contains(fragment));
  }
}

void main() {
  final auth = AuthRepo.instance;

  setUpAll(initTestDb);
  setUp(resetTestData);
  tearDownAll(disposeTestDb);

  group('Validation', () {
    test('courriel', () {
      expect(AuthRepo.validateEmail(''), isNotNull);
      expect(AuthRepo.validateEmail('abc'), isNotNull);
      expect(AuthRepo.validateEmail('a@b'), isNotNull);
      expect(AuthRepo.validateEmail('a b@c.com'), isNotNull);
      expect(AuthRepo.validateEmail('  hawa@example.com '), isNull);
    });

    test('mot de passe', () {
      expect(AuthRepo.validatePassword('Abc123'), isNotNull); // trop court
      expect(
        AuthRepo.validatePassword('1234567890'),
        isNotNull,
      ); // pas de lettre
      expect(
        AuthRepo.validatePassword('abcdefghij'),
        isNotNull,
      ); // pas de chiffre
      expect(AuthRepo.validatePassword('abcdefg1'), isNull); // 8 caractères
      expect(
        AuthRepo.validatePassword('Écoute123'),
        isNull,
      ); // lettre accentuée
    });
  });

  group('Inscription', () {
    test('crée le compte et ouvre la session', () async {
      final email = uniqueEmail();
      await auth.signUp(email, _pwd, displayName: 'Hawa');

      final user = await AppDb.instance.getUserByEmail(email);
      expect(user, isNotNull);
      expect(user!['display_name'], 'Hawa');
      expect(user['password_hash'], isNot(_pwd));
      expect(
        (user['password_hash'] as String).startsWith('pbkdf2-sha256'),
        isTrue,
      );

      expect(await auth.getCurrentUserId(), user['id']);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(AuthRepo.kEmail), email);
    });

    test('nom affiché par défaut = début du courriel', () async {
      await auth.signUp('claire.dupont@example.com', _pwd);
      final user = await AppDb.instance.getUserByEmail(
        'claire.dupont@example.com',
      );
      expect(user!['display_name'], 'claire.dupont');
    });

    test('courriel normalisé (casse et espaces)', () async {
      final email = uniqueEmail('maj');
      await auth.signUp('  ${email.toUpperCase()} ', _pwd);
      await auth.signOut();
      final user = await auth.signIn(email, _pwd);
      expect(user['email'], email);
    });

    test('courriel déjà utilisé', () async {
      final email = uniqueEmail();
      await auth.signUp(email, _pwd);
      await auth.signOut();
      await _expectAuthError(() => auth.signUp(email, _pwd), 'existe déjà');
    });

    test(
      'courriel ou mot de passe invalide refusé, aucun compte créé',
      () async {
        await _expectAuthError(
          () => auth.signUp('pas-un-courriel', _pwd),
          'invalide',
        );
        final email = uniqueEmail();
        await _expectAuthError(
          () => auth.signUp(email, 'court1'),
          '8 caractères',
        );
        expect(await AppDb.instance.getUserByEmail(email), isNull);
      },
    );

    test('l\'inscription notifie le changement de compte', () async {
      final before = authVersion.value;
      await auth.signUp(uniqueEmail(), _pwd);
      expect(authVersion.value, greaterThan(before));
    });
  });

  group('Connexion', () {
    test('bon mot de passe', () async {
      final email = uniqueEmail();
      await auth.signUp(email, _pwd);
      await auth.signOut();
      expect(await auth.getCurrentUserId(), isNull);

      final user = await auth.signIn(email, _pwd);
      expect(await auth.getCurrentUserId(), user['id']);
    });

    test('même message pour compte inconnu et mauvais mot de passe', () async {
      final email = uniqueEmail();
      await auth.signUp(email, _pwd);
      await auth.signOut();

      String? msgWrong, msgUnknown;
      try {
        await auth.signIn(email, 'Autre12345');
      } on AuthException catch (e) {
        msgWrong = e.message;
      }
      try {
        await auth.signIn(uniqueEmail('inconnu'), _pwd);
      } on AuthException catch (e) {
        msgUnknown = e.message;
      }
      expect(msgWrong, isNotNull);
      expect(msgWrong, msgUnknown);
    });

    test('champs vides', () async {
      await _expectAuthError(() => auth.signIn('', ''), 'Entre ton courriel');
    });

    test('login() retourne null au lieu de lancer une exception', () async {
      expect(await auth.login(uniqueEmail('x'), _pwd), isNull);
    });

    test('blocage après 5 échecs, même avec le bon mot de passe', () async {
      final email = uniqueEmail('lock');
      await auth.signUp(email, _pwd);
      await auth.signOut();

      for (var i = 0; i < 5; i++) {
        await _expectAuthError(
          () => auth.signIn(email, 'Mauvais1234'),
          'incorrect',
        );
      }
      await _expectAuthError(
        () => auth.signIn(email, _pwd),
        'Trop de tentatives',
      );
    });

    test('un succès remet le compteur d\'échecs à zéro', () async {
      final email = uniqueEmail('reset');
      await auth.signUp(email, _pwd);
      await auth.signOut();

      for (var i = 0; i < 4; i++) {
        await _expectAuthError(
          () => auth.signIn(email, 'Mauvais1234'),
          'incorrect',
        );
      }
      await auth.signIn(email, _pwd); // succès
      await auth.signOut();
      for (var i = 0; i < 4; i++) {
        await _expectAuthError(
          () => auth.signIn(email, 'Mauvais1234'),
          'incorrect',
        );
      }
      await auth.signIn(email, _pwd); // toujours possible : pas de blocage
    });

    test('ancien hachage SHA-256 accepté puis migré vers PBKDF2', () async {
      const salt = 'vieuxSel';
      final legacy = await _legacyHash(salt, _pwd);
      final email = uniqueEmail('legacy');
      await AppDb.instance.insertUser(
        email: email,
        passwordHash: legacy,
        salt: salt,
        displayName: 'Ancien',
      );

      await auth.signIn(email, _pwd);
      final after = await AppDb.instance.getUserByEmail(email);
      expect(
        (after!['password_hash'] as String).startsWith('pbkdf2-sha256'),
        isTrue,
      );
      expect(after['salt'], isNot(salt));

      // Le mot de passe fonctionne toujours après la migration.
      await auth.signOut();
      await auth.signIn(email, _pwd);
    });
  });

  group('Déconnexion et session', () {
    test('signOut efface la session', () async {
      await auth.signUp(uniqueEmail(), _pwd);
      await auth.signOut();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(AuthRepo.kUserId), isNull);
      expect(prefs.getString(AuthRepo.kEmail), isNull);
      expect(await auth.getCurrentUser(), isNull);
    });

    test(
      'signOut efface les restes d\'invité mais pas les données du compte',
      () async {
        final db = AppDb.instance;
        await auth.signUp(uniqueEmail(), _pwd);
        final id = (await auth.getCurrentUserId())!;
        await db.insertRun(
          startedAt: DateTime(2026, 6, 6),
          mode: 'fixed',
          level: 'level_cycle1',
          totalTarget: 10,
          correctCount: 6,
          score: 30,
          userId: id,
        );
        // Reste d'invité (jamais rattaché).
        await db.insertRun(
          startedAt: DateTime(2026, 6, 7),
          mode: 'fixed',
          level: 'level_cycle1',
          totalTarget: 10,
          correctCount: 4,
          score: 20,
        );
        await db.incrementStat('présent', correct: true);
        await db.insertCustomSet(
          CustomSet.newLocal(
            name: 'Reste',
            tenses: ['présent'],
            verbs: ['aimer'],
          ),
          userId: null,
        );

        await auth.signOut();

        expect(await db.getRuns(mode: 'fixed', userId: null), isEmpty);
        expect((await db.getGlobalStats(userId: null))['correct'], 0);
        expect(await db.getCustomSets(userId: null), isEmpty);
        // Le compte garde ses parties.
        expect(await db.getTotalScore(userId: id), 30);
      },
    );

    test('session orpheline nettoyée si le compte n\'existe plus', () async {
      SharedPreferences.setMockInitialValues({AuthRepo.kUserId: 999999});
      expect(await auth.getCurrentUser(), isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(AuthRepo.kUserId), isNull);
    });
  });

  group('Isolation invité / compte', () {
    test('les données de l\'invité sont rattachées à l\'inscription', () async {
      final db = AppDb.instance;
      await db.insertRun(
        startedAt: DateTime(2026, 1, 1),
        mode: 'fixed',
        level: 'level_cycle1',
        totalTarget: 10,
        correctCount: 7,
        score: 35,
      );
      await db.incrementStat('présent', correct: true);
      await db.insertCustomSet(
        CustomSet.newLocal(
          name: 'Invité',
          tenses: ['présent'],
          verbs: ['aimer'],
        ),
        userId: null,
      );

      await auth.signUp(uniqueEmail(), _pwd);
      final id = (await auth.getCurrentUserId())!;

      expect(await db.getRuns(mode: 'fixed', userId: id), hasLength(1));
      expect(await db.getRuns(mode: 'fixed', userId: null), isEmpty);
      expect((await db.getGlobalStats(userId: id))['correct'], 1);
      expect((await db.getGlobalStats(userId: null))['correct'], 0);
      expect(await db.getCustomSets(userId: id), hasLength(1));
      expect(await db.getCustomSets(userId: null), isEmpty);
    });

    test(
      'après déconnexion, un invité ne voit pas les données du compte',
      () async {
        final db = AppDb.instance;
        await auth.signUp(uniqueEmail(), _pwd);
        final id = (await auth.getCurrentUserId())!;
        await db.insertRun(
          startedAt: DateTime(2026, 2, 2),
          mode: 'unlimited',
          level: 'level_cycle1',
          totalTarget: 3,
          correctCount: 3,
          score: 15,
          userId: id,
        );
        await auth.signOut();

        expect(await db.getRuns(mode: 'unlimited', userId: null), isEmpty);
        expect(await db.getTotalScore(userId: null), 0);
        expect(await db.getTotalScore(userId: id), 15);
      },
    );

    test(
      'les données d\'un compte ne sont pas absorbées par un autre compte',
      () async {
        final db = AppDb.instance;
        await auth.signUp(uniqueEmail('a'), _pwd);
        final a = (await auth.getCurrentUserId())!;
        await db.insertRun(
          startedAt: DateTime(2026, 3, 3),
          mode: 'fixed',
          level: 'expert',
          totalTarget: 10,
          correctCount: 10,
          score: 200,
          userId: a,
        );
        await auth.signOut();

        await auth.signUp(uniqueEmail('b'), _pwd);
        final b = (await auth.getCurrentUserId())!;
        expect(await db.getTotalScore(userId: b), 0);
        expect(await db.getTotalScore(userId: a), 200);
      },
    );
  });

  group('Compte', () {
    test('changement de mot de passe', () async {
      final email = uniqueEmail();
      await auth.signUp(email, _pwd);

      await _expectAuthError(
        () => auth.changePassword(
          currentPassword: 'Faux123456',
          newPassword: 'Nouveau1234',
        ),
        'actuel incorrect',
      );
      await _expectAuthError(
        () => auth.changePassword(currentPassword: _pwd, newPassword: 'court'),
        '8 caractères',
      );

      await auth.changePassword(
        currentPassword: _pwd,
        newPassword: 'Nouveau1234',
      );
      await auth.signOut();
      await _expectAuthError(() => auth.signIn(email, _pwd), 'incorrect');
      await auth.signIn(email, 'Nouveau1234');
    });

    test('changement de mot de passe sans être connecté', () async {
      await _expectAuthError(
        () => auth.changePassword(
          currentPassword: _pwd,
          newPassword: 'Nouveau1234',
        ),
        'pas connecté',
      );
    });

    test('suppression du compte : mauvais mot de passe refusé', () async {
      final email = uniqueEmail();
      await auth.signUp(email, _pwd);
      await _expectAuthError(
        () => auth.deleteAccount('Faux123456'),
        'incorrect',
      );
      expect(await AppDb.instance.getUserByEmail(email), isNotNull);
    });

    test(
      'suppression du compte : efface le compte et ses données, pas celles des autres',
      () async {
        final db = AppDb.instance;
        await auth.signUp(uniqueEmail('autre'), _pwd);
        final other = (await auth.getCurrentUserId())!;
        await db.insertRun(
          startedAt: DateTime(2026, 4, 4),
          mode: 'fixed',
          level: 'level_sec1',
          totalTarget: 10,
          correctCount: 5,
          score: 70,
          userId: other,
        );
        await auth.signOut();

        final email = uniqueEmail('supprime');
        await auth.signUp(email, _pwd);
        final id = (await auth.getCurrentUserId())!;
        await db.insertRun(
          startedAt: DateTime(2026, 5, 5),
          mode: 'fixed',
          level: 'level_sec1',
          totalTarget: 10,
          correctCount: 9,
          score: 126,
          userId: id,
        );
        await db.incrementStat('futur simple', correct: true, userId: id);
        await db.insertBadge(userId: id, code: 'correct_10', title: 't');
        await db.insertCustomSet(
          CustomSet.newLocal(name: 'S', tenses: ['présent'], verbs: ['aimer']),
          userId: id,
        );

        await auth.deleteAccount(_pwd);

        expect(await db.getUserByEmail(email), isNull);
        expect(await auth.getCurrentUserId(), isNull);
        expect(await db.getRuns(mode: 'fixed', userId: id), isEmpty);
        expect(await db.getBadgesForUser(id), isEmpty);
        expect(await db.getCustomSets(userId: id), isEmpty);
        expect((await db.getGlobalStats(userId: id))['correct'], 0);
        // L'autre compte est intact.
        expect(await db.getTotalScore(userId: other), 70);
      },
    );
  });

  test('réglage de synchro : désactivé par défaut', () async {
    expect(await auth.isOnlineSyncEnabled(), isFalse);
    await auth.setOnlineSyncEnabled(true);
    expect(await auth.isOnlineSyncEnabled(), isTrue);
  });
}

// Même calcul que l'ancien format de l'application : SHA-256(sel + mot de passe).
Future<String> _legacyHash(String salt, String password) async =>
    sha256.convert(utf8.encode('$salt$password')).toString();
