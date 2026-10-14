import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;
import '../models/custom_set.dart';

class AppDb {
  AppDb._();
  static final AppDb instance = AppDb._();
  static sqflite.Database? _db;
  // Future d'ouverture en cours (évite d'ouvrir la base deux fois).
  static Future<sqflite.Database>? _openFuture;

  Future<sqflite.Database> get database async {
    if (_db != null) return _db!;

    // Si une ouverture est déjà en cours, on attend le même Future
    _openFuture ??= _open();
    _db = await _openFuture!;
    return _db!;
  }

  /// Compare deux DateTime en ignorant l'heure, pour calculer un nombre de
  /// jours calendaires écoulés plutôt qu'une durée brute en heures/ms.
  /// Ex: lundi 23h59 → mardi 00h01 donne 1 jour, même si la différence
  /// réelle n'est que de 2 minutes.
  int _calendarDayDiff(DateTime from, DateTime to) {
    final fromDate = DateTime(from.year, from.month, from.day);
    final toDate = DateTime(to.year, to.month, to.day);
    return toDate.difference(fromDate).inDays;
  }

  /// Clause SQL + arguments pour filtrer sur un utilisateur.
  /// userId == null signifie « invité » : uniquement les lignes sans
  /// utilisateur (user_id IS NULL), JAMAIS celles de tous les comptes.
  (String clause, List<Object?> args) _userFilter(int? userId) {
    if (userId == null) return ('user_id IS NULL', <Object?>[]);
    return ('user_id = ?', <Object?>[userId]);
  }

  Future<sqflite.Database> _open() async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      ffi.sqfliteFfiInit();
      sqflite.databaseFactory = ffi.databaseFactoryFfi;
    }

    final path = p.join(await sqflite.getDatabasesPath(), 'conjufun.db');
    return sqflite.openDatabase(
      path,
      version: 12,
      onCreate: (db, v) async {
        // --- USERS ---------------------------------------------------------
        await db.execute('''
          CREATE TABLE users(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          email TEXT NOT NULL UNIQUE,
          password_hash TEXT NOT NULL,
          salt TEXT NOT NULL,
          display_name TEXT,
          has_done_level_test INTEGER NOT NULL DEFAULT 0,
          last_recommended_level TEXT,
          current_streak INTEGER NOT NULL DEFAULT 0,
          best_streak INTEGER NOT NULL DEFAULT 0,
          last_streak_ms INTEGER
        );
        ''');

        // --- VERBS ---------------------------------------------------------
        await db.execute('''
          CREATE TABLE verbs(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            verb TEXT NOT NULL,
            pronoun TEXT NOT NULL,
            tense TEXT NOT NULL,
            correct_answer TEXT NOT NULL
          );
        ''');

        // --- STATS ---------------------------------------------------------
        await db.execute('''
          CREATE TABLE stats(
            tense TEXT,
            correct_count INTEGER DEFAULT 0,
            wrong_count INTEGER DEFAULT 0,
            user_id INTEGER,
            PRIMARY KEY (tense, user_id),
            FOREIGN KEY (user_id) REFERENCES users(id)
          );
        ''');

        // --- RUNS ------------------------------------------
        await db.execute('''
          CREATE TABLE runs(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            started_at INTEGER NOT NULL,
            mode TEXT NOT NULL,
            level TEXT NOT NULL,
            total_target INTEGER NOT NULL,
            correct_count INTEGER NOT NULL,
            score INTEGER NOT NULL,
            user_id INTEGER,
            FOREIGN KEY (user_id) REFERENCES users(id)
          );
        ''');

        // --- BADGES --------------------------------------------------------
        await db.execute('''
          CREATE TABLE badges(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER,
            code TEXT NOT NULL,
            title TEXT NOT NULL,
            description TEXT,
            earned_at INTEGER NOT NULL,
            UNIQUE(user_id, code),
            FOREIGN KEY (user_id) REFERENCES users(id)
          );
        ''');

        // --- CUSTOM SETS (mode créateur) ----------------------------------
        await db.execute('''
          CREATE TABLE custom_sets (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            school_level TEXT,
            tenses_json TEXT NOT NULL,
            verbs_json TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            max_questions INTEGER,
            remote_id TEXT,
            needs_sync INTEGER NOT NULL DEFAULT 0,
            is_deleted INTEGER NOT NULL DEFAULT 0,
            deleted_at INTEGER,
            user_id INTEGER
          );
        ''');

        // Index pour le dashboard ---------------
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_runs_user_mode ON runs(user_id, mode);',
        );
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_runs_level ON runs(level);',
        );
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_runs_started ON runs(started_at DESC);',
        );

        await _importLefffConjugationsJson(db);
      },
      onUpgrade: (db, oldV, newV) async {
        if (oldV < 2) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS stats(
              tense TEXT,
              correct_count INTEGER DEFAULT 0,
              wrong_count INTEGER DEFAULT 0,
              user_id INTEGER,
              PRIMARY KEY (tense, user_id),
              FOREIGN KEY (user_id) REFERENCES users(id)
            );
          ''');
        }

        if (oldV < 3) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS runs(
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              started_at INTEGER NOT NULL,
              mode TEXT NOT NULL,
              level TEXT NOT NULL,
              total_target INTEGER NOT NULL,
              correct_count INTEGER NOT NULL,
              score INTEGER NOT NULL
            );
          ''');
        }
        if (oldV < 4) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS users(
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              email TEXT NOT NULL UNIQUE,
              password_hash TEXT NOT NULL,
              salt TEXT NOT NULL,
              display_name TEXT
            );
          ''');
        }
        if (oldV < 5) {
          // Ajouter user_id à runs + index
          await db.execute('ALTER TABLE runs ADD COLUMN user_id INTEGER;');
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_runs_user_mode ON runs(user_id, mode);',
          );
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_runs_level ON runs(level);',
          );
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_runs_started ON runs(started_at DESC);',
          );
        }
        if (oldV < 6) {
          // Table badges
          await db.execute('''
          CREATE TABLE IF NOT EXISTS badges(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER,
            code TEXT NOT NULL,
            title TEXT NOT NULL,
            description TEXT,
            earned_at INTEGER NOT NULL,
            UNIQUE(user_id, code),
            FOREIGN KEY (user_id) REFERENCES users(id)
          );
        ''');
        }
        if (oldV < 7) {
          await db.execute(
            'ALTER TABLE users ADD COLUMN has_done_level_test INTEGER NOT NULL DEFAULT 0;',
          );
          await db.execute(
            'ALTER TABLE users ADD COLUMN last_recommended_level TEXT;',
          );
        }
        if (oldV < 8) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS custom_sets (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              school_level TEXT,
              tenses_json TEXT NOT NULL,
              verbs_json TEXT NOT NULL,
              created_at INTEGER NOT NULL
            );
          ''');
        }
        if (oldV < 9) {
          // Colonne manquante possible sur des anciennes installations
          await db.execute(
            'ALTER TABLE custom_sets ADD COLUMN max_questions INTEGER',
          );

          await db.execute(
            'ALTER TABLE custom_sets ADD COLUMN updated_at INTEGER',
          );
          await db.execute('ALTER TABLE custom_sets ADD COLUMN remote_id TEXT');
          await db.execute(
            'ALTER TABLE custom_sets ADD COLUMN needs_sync INTEGER NOT NULL DEFAULT 0',
          );

          // Initialiser updated_at = created_at pour les anciennes lignes
          await db.execute(
            'UPDATE custom_sets SET updated_at = created_at WHERE updated_at IS NULL',
          );
        }

        if (oldV < 10) {
          await db.execute(
            'ALTER TABLE custom_sets ADD COLUMN is_deleted INTEGER NOT NULL DEFAULT 0',
          );
          await db.execute(
            'ALTER TABLE custom_sets ADD COLUMN deleted_at INTEGER',
          );
        }
        if (oldV < 11) {
          await db.execute(
            'ALTER TABLE users ADD COLUMN current_streak INTEGER NOT NULL DEFAULT 0;',
          );
          await db.execute(
            'ALTER TABLE users ADD COLUMN best_streak INTEGER NOT NULL DEFAULT 0;',
          );
          await db.execute(
            'ALTER TABLE users ADD COLUMN last_streak_ms INTEGER;',
          );
        }
        if (oldV < 12) {
          // Les ensembles du mode créateur appartiennent maintenant à un
          // compte (NULL = invité). Les ensembles existants passent en invité
          // et sont rattachés au compte à la prochaine connexion.
          await db.execute(
            'ALTER TABLE custom_sets ADD COLUMN user_id INTEGER',
          );
        }
      },
    );
  }

  Future<void> _importLefffConjugationsJson(sqflite.Database db) async {
    final raw = await rootBundle.loadString(
      'assets/data/lefff_conjugations.json',
    );
    final Map<String, dynamic> data = json.decode(raw);
    const persons = ['je', 'tu', 'il', 'nous', 'vous', 'ils'];

    final tenseNames = <String, String>{
      'P': 'présent',
      'I': 'imparfait',
      'F': 'futur simple',
      'C': 'conditionnel présent',
      'S': 'subjonctif présent',
      'T': 'subjonctif imparfait',
      'J': 'passé simple',
      'Y': 'impératif',
      'G': 'gérondif',
      'K': 'participe passé',
      'W': 'infinitif',
      'PC': 'passé composé',
      'FP': 'futur proche',
    };

    final batch = db.batch();
    data.forEach((infinitif, tensesAny) {
      final tenses = (tensesAny as Map).cast<String, dynamic>();
      tenses.forEach((tenseCode, formsAny) {
        final tense = tenseNames[tenseCode];
        if (tense == null) return;
        if (formsAny is List) {
          for (var i = 0; i < formsAny.length && i < 6; i++) {
            final form = formsAny[i]?.toString().trim();
            if (form == null || form.isEmpty || form == 'NA') continue;
            batch.insert('verbs', {
              'verb': infinitif,
              'tense': tense,
              'pronoun': persons[i],
              'correct_answer': form,
            });
          }
        }
      });
    });
    await batch.commit(noResult: true);
  }

  // -----------------------------------------------------------------------
  // USERS API
  // -----------------------------------------------------------------------

  Future<int> insertUser({
    required String email,
    required String passwordHash,
    required String salt,
    String? displayName,
  }) async {
    final db = await database;
    return db.insert('users', {
      'email': email.trim().toLowerCase(),
      'password_hash': passwordHash,
      'salt': salt,
      'display_name': displayName,
    }, conflictAlgorithm: sqflite.ConflictAlgorithm.abort);
  }

  Future<Map<String, dynamic>?> getUserByEmail(String email) async {
    final db = await database;
    final rows = await db.query(
      'users',
      where: 'email = ?',
      whereArgs: [email.trim().toLowerCase()],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<Map<String, dynamic>?> getUserById(int id) async {
    final db = await database;
    final rows = await db.query(
      'users',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  /// Met à jour le mot de passe (nouveau hash + nouveau sel).
  Future<void> updateUserPassword({
    required int userId,
    required String passwordHash,
    required String salt,
  }) async {
    final db = await database;
    await db.update(
      'users',
      {'password_hash': passwordHash, 'salt': salt},
      where: 'id = ?',
      whereArgs: [userId],
    );
  }

  /// Supprime un compte et toutes ses données (parties, stats, badges).
  /// Exigé par l'App Store et Google Play dès que l'app crée des comptes.
  Future<void> deleteUser(int userId) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('runs', where: 'user_id = ?', whereArgs: [userId]);
      await txn.delete('stats', where: 'user_id = ?', whereArgs: [userId]);
      await txn.delete('badges', where: 'user_id = ?', whereArgs: [userId]);
      await txn.delete(
        'custom_sets',
        where: 'user_id = ?',
        whereArgs: [userId],
      );
      await txn.delete('users', where: 'id = ?', whereArgs: [userId]);
    });
  }

  Future<void> setUserLevelTestResult({
    required int userId,
    required String levelString,
  }) async {
    final db = await database;
    await db.update(
      'users',
      {'has_done_level_test': 1, 'last_recommended_level': levelString},
      where: 'id = ?',
      whereArgs: [userId],
    );
  }

  Future<Map<String, dynamic>?> getUserLevelTestResult(int userId) async {
    final db = await database;
    final rows = await db.query(
      'users',
      columns: ['has_done_level_test', 'last_recommended_level'],
      where: 'id = ?',
      whereArgs: [userId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first;
  }

  // -----------------------------------------------------------------------
  // VERBS / EXERCISES
  // -----------------------------------------------------------------------

  Future<Map<String, dynamic>?> getRandomExerciseRaw() async {
    final db = await database;
    final r = await db.rawQuery('''
      SELECT * FROM verbs
      WHERE tense NOT IN ('infinitif', 'participe passé', 'gérondif')
      ORDER BY RANDOM()
      LIMIT 1
    ''');
    return r.isEmpty ? null : r.first;
  }

  // -----------------------------------------------------------------------
  // STATS (par temps)
  // -----------------------------------------------------------------------

  /// Incrémente la stat d'un temps. userId == null : stats de l'invité.
  Future<void> incrementStat(
    String tense, {
    required bool correct,
    int? userId,
  }) async {
    final db = await database;
    final (userClause, userArgs) = _userFilter(userId);

    await db.transaction((txn) async {
      final existing = await txn.query(
        'stats',
        where: 'tense = ? AND $userClause',
        whereArgs: [tense, ...userArgs],
        limit: 1,
      );

      if (existing.isEmpty) {
        await txn.insert('stats', {
          'tense': tense,
          'user_id': userId,
          'correct_count': correct ? 1 : 0,
          'wrong_count': correct ? 0 : 1,
        });
      } else {
        final row = existing.first;
        final correctCount =
            ((row['correct_count'] as int?) ?? 0) + (correct ? 1 : 0);
        final wrongCount =
            ((row['wrong_count'] as int?) ?? 0) + (correct ? 0 : 1);
        await txn.update(
          'stats',
          {'correct_count': correctCount, 'wrong_count': wrongCount},
          where: 'tense = ? AND $userClause',
          whereArgs: [tense, ...userArgs],
        );
      }
    });
  }

  Future<List<Map<String, dynamic>>> getAllStats() async {
    final db = await database;
    return db.query('stats');
  }

  Future<List<Map<String, dynamic>>> getStatsByTense({int? userId}) async {
    final db = await database;
    final (userClause, userArgs) = _userFilter(userId);

    final rows = await db.rawQuery('''
      SELECT
        tense,
        SUM(correct_count) AS correct,
        SUM(wrong_count)   AS wrong
      FROM stats
      WHERE $userClause
      GROUP BY tense
      ORDER BY tense
    ''', userArgs);
    return rows.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  /// Si userId est fourni, retourne les stats globales pour cet utilisateur
  /// uniquement. Si userId est omis, retourne les stats invité (user_id
  /// NULL) — jamais celles de tous les utilisateurs confondus.
  Future<Map<String, num>> getGlobalStats({int? userId}) async {
    final db = await database;
    final (userClause, userArgs) = _userFilter(userId);
    final result = await db.rawQuery(
      'SELECT SUM(correct_count) AS correct, SUM(wrong_count) AS wrong FROM stats WHERE $userClause',
      userArgs,
    );
    if (result.isEmpty) return {'correct': 0, 'wrong': 0};
    final row = result.first;
    return {
      'correct': (row['correct'] as int?) ?? 0,
      'wrong': (row['wrong'] as int?) ?? 0,
    };
  }

  // -----------------------------------------------------------------------
  // RUNS
  // -----------------------------------------------------------------------

  Future<void> insertRun({
    required DateTime startedAt,
    required String mode,
    required String level,
    required int totalTarget,
    required int correctCount,
    required int score,
    int? userId,
  }) async {
    final db = await database;

    await db.insert('runs', {
      'started_at': startedAt.millisecondsSinceEpoch,
      'mode': mode,
      'level': level,
      'total_target': totalTarget,
      'correct_count': correctCount,
      'score': score,
      'user_id': userId,
    });
  }

  // Tous les records / totaux ci-dessous sont filtrés par utilisateur :
  // userId == null = invité uniquement.

  Future<int> getUnlimitedRecord({int? userId}) async {
    final db = await database;
    final (userClause, userArgs) = _userFilter(userId);
    final r = await db.rawQuery(
      "SELECT MAX(score) AS best FROM runs WHERE mode = 'unlimited' AND $userClause",
      userArgs,
    );
    final row = r.isNotEmpty ? r.first : null;
    return (row?['best'] as int?) ?? 0;
  }

  Future<int> getRecordByLevel(String level, {int? userId}) async {
    final db = await database;
    final (userClause, userArgs) = _userFilter(userId);
    final r = await db.rawQuery(
      "SELECT MAX(score) AS best FROM runs WHERE mode = 'unlimited' AND level = ? AND $userClause",
      [level, ...userArgs],
    );
    final row = r.isNotEmpty ? r.first : null;
    return (row?['best'] as int?) ?? 0;
  }

  Future<int> getRecordByLevelAndMode({
    required String level,
    required String mode,
    int? userId,
  }) async {
    final db = await database;
    final (userClause, userArgs) = _userFilter(userId);
    final r = await db.rawQuery(
      'SELECT MAX(score) AS best FROM runs WHERE mode = ? AND level = ? AND $userClause',
      [mode, level, ...userArgs],
    );
    final row = r.isNotEmpty ? r.first : null;
    return (row?['best'] as int?) ?? 0;
  }

  Future<List<Map<String, dynamic>>> getRuns({
    required String mode,
    int? userId,
  }) async {
    final db = await database;
    final (userClause, userArgs) = _userFilter(userId);

    final rows = await db.rawQuery(
      '''
    SELECT
      MIN(id)            AS id,
      started_at,
      mode,
      level,
      MAX(total_target)  AS total_target,
      MAX(correct_count) AS correct_count,
      MAX(score)         AS score,
      user_id
    FROM runs
    WHERE mode = ? AND $userClause
    GROUP BY started_at, mode, level, user_id
    ORDER BY started_at DESC
  ''',
      [mode, ...userArgs],
    );

    return rows.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<int> getTotalScoreByLevelAndMode({
    required String level,
    required String mode,
    required int? userId,
  }) async {
    final db = await database;
    final (userClause, userArgs) = _userFilter(userId);
    final result = await db.rawQuery(
      '''
      SELECT SUM(score) AS total
      FROM runs
      WHERE level = ? AND mode = ? AND $userClause
      ''',
      [level, mode, ...userArgs],
    );
    if (result.isEmpty) return 0;
    final total = result.first['total'] as int?;
    return total ?? 0;
  }

  Future<int> getTotalScoreForUser(int? userId) async {
    if (userId == null) return 0;
    final db = await database;
    final result = await db.rawQuery(
      '''
      SELECT SUM(score) AS total
      FROM runs
      WHERE user_id = ?
      ''',
      [userId],
    );
    if (result.isEmpty) return 0;
    final row = result.first;
    final total = row['total'] as int?;
    return total ?? 0;
  }

  /// Score total : celui du compte, ou celui de l'invité (user_id NULL) si
  /// userId est null.
  Future<int> getTotalScore({required int? userId}) async {
    final db = await database;
    final (userClause, userArgs) = _userFilter(userId);
    final result = await db.rawQuery(
      'SELECT SUM(score) AS total FROM runs WHERE $userClause',
      userArgs,
    );
    if (result.isEmpty) return 0;
    return (result.first['total'] as int?) ?? 0;
  }

  Future<Map<String, num>> getRunsSuccess(String mode, {int? userId}) async {
    final db = await database;
    final (userClause, userArgs) = _userFilter(userId);

    final r = await db.rawQuery(
      'SELECT COUNT(*) AS runs, SUM(correct_count) AS correct, SUM(total_target) AS total FROM runs WHERE mode = ? AND $userClause',
      [mode, ...userArgs],
    );
    if (r.isEmpty) return {'runs': 0, 'correct': 0, 'total': 0};
    final row = r.first;

    return {
      'runs': (row['runs'] as int?) ?? 0,
      'correct': (row['correct'] as int?) ?? 0,
      'total': (row['total'] as int?) ?? 0,
    };
  }

  // ========================= REWARDS / PROGRESS =========================

  Future<int> getTotalCorrectAnswers(int userId) async {
    final db = await database;
    final rows = await db.rawQuery(
      '''
        SELECT SUM(correct_count) AS total_correct
        FROM runs
        WHERE user_id = ?
      ''',
      [userId],
    );
    final val = rows.first['total_correct'] as num?;
    return (val ?? 0).toInt();
  }

  Future<int> getTotalSessions(int userId) async {
    final db = await database;
    final rows = await db.rawQuery(
      '''
        SELECT COUNT(*) AS cnt
        FROM runs
        WHERE user_id = ?
      ''',
      [userId],
    );
    final val = rows.first['cnt'] as num?;
    return (val ?? 0).toInt();
  }

  Future<List<DateTime>> getSessionStartTimesForUser(int userId) async {
    final db = await database;
    final rows = await db.rawQuery(
      '''
    SELECT started_at
    FROM runs
    WHERE user_id = ?
    ORDER BY started_at DESC
    ''',
      [userId],
    );

    return rows
        .map((r) => DateTime.fromMillisecondsSinceEpoch(r['started_at'] as int))
        .toList();
  }

  Future<Map<String, int>> updateStreakAfterSession({
    required int userId,
    required DateTime sessionTime,
  }) async {
    final db = await database;
    final nowMs = sessionTime.millisecondsSinceEpoch;

    return await db.transaction((txn) async {
      final rows = await txn.query(
        'users',
        columns: ['current_streak', 'best_streak', 'last_streak_ms'],
        where: 'id = ?',
        whereArgs: [userId],
        limit: 1,
      );

      if (rows.isEmpty) return {'current': 0, 'best': 0};

      final row = rows.first;
      int current = (row['current_streak'] as int?) ?? 0;
      int best = (row['best_streak'] as int?) ?? 0;
      final int? lastMs = row['last_streak_ms'] as int?;

      if (lastMs == null) {
        // 1ère session qui initialise le streak
        current = 1;
        if (current > best) best = current;

        await txn.update(
          'users',
          {
            'current_streak': current,
            'best_streak': best,
            'last_streak_ms': nowMs,
          },
          where: 'id = ?',
          whereArgs: [userId],
        );
        return {'current': current, 'best': best};
      }

      // On compare des jours calendaires (année/mois/jour) et non des
      // fenêtres fixes de 24h/48h, qui se décalaient avec l'heure de jeu.
      final lastDate = DateTime.fromMillisecondsSinceEpoch(lastMs);
      final dayDiff = _calendarDayDiff(lastDate, sessionTime);

      if (dayDiff <= 0) {
        // Même jour calendaire (ou horloge en arrière) : max 1x par jour.
        return {'current': current, 'best': best};
      }

      if (dayDiff == 1) {
        // Jour calendaire suivant : streak +1
        current = current <= 0 ? 1 : (current + 1);
      } else {
        // Au moins un jour complet sauté : reset, nouvelle série à 1.
        current = 1;
      }

      if (current > best) best = current;

      await txn.update(
        'users',
        {
          'current_streak': current,
          'best_streak': best,
          'last_streak_ms': nowMs,
        },
        where: 'id = ?',
        whereArgs: [userId],
      );

      return {'current': current, 'best': best};
    });
  }

  Future<Map<String, int>> getStreakForUser(int userId) async {
    final db = await database;
    final rows = await db.query(
      'users',
      columns: ['current_streak', 'best_streak', 'last_streak_ms'],
      where: 'id = ?',
      whereArgs: [userId],
      limit: 1,
    );
    if (rows.isEmpty) return {'current': 0, 'best': 0};

    int current = (rows.first['current_streak'] as int?) ?? 0;
    final int best = (rows.first['best_streak'] as int?) ?? 0;
    final int? lastMs = rows.first['last_streak_ms'] as int?;

    if (lastMs == null) return {'current': current, 'best': best};

    final lastDate = DateTime.fromMillisecondsSinceEpoch(lastMs);
    final dayDiff = _calendarDayDiff(lastDate, DateTime.now());

    if (dayDiff >= 2) {
      // Au moins un jour complet sauté : le streak est expiré.
      await db.update(
        'users',
        {'current_streak': 0},
        where: 'id = ?',
        whereArgs: [userId],
      );
      current = 0;
    }

    return {'current': current, 'best': best};
  }

  Future<List<DateTime>> getActivityDatesForUser(int? userId) async {
    if (userId == null) return [];
    final db = await database;
    final rows = await db.rawQuery(
      '''
        SELECT DISTINCT started_at
        FROM runs
        WHERE user_id = ?
      ''',
      [userId],
    );
    return rows
        .map(
          (r) => DateTime.fromMillisecondsSinceEpoch((r['started_at'] as int)),
        )
        .toList();
  }

  /// Rattache les données de l'invité (parties ET statistiques par temps,
  /// toutes avec user_id NULL) au compte, puis les retire du mode invité.
  /// Comme les lectures sont maintenant isolées par utilisateur, les lignes
  /// sans utilisateur sont exclusivement celles de l'invité.
  Future<void> attachGuestRunsToUser(int userId) async {
    final db = await database;

    await db.transaction((txn) async {
      await txn.update('runs', {'user_id': userId}, where: 'user_id IS NULL');

      // Fusion des stats : on additionne avec les stats déjà présentes.
      final guestStats = await txn.query('stats', where: 'user_id IS NULL');
      for (final g in guestStats) {
        final tense = g['tense'] as String?;
        if (tense == null) continue;
        final gc = (g['correct_count'] as int?) ?? 0;
        final gw = (g['wrong_count'] as int?) ?? 0;

        final existing = await txn.query(
          'stats',
          where: 'tense = ? AND user_id = ?',
          whereArgs: [tense, userId],
          limit: 1,
        );

        if (existing.isEmpty) {
          await txn.insert('stats', {
            'tense': tense,
            'user_id': userId,
            'correct_count': gc,
            'wrong_count': gw,
          });
        } else {
          final row = existing.first;
          await txn.update(
            'stats',
            {
              'correct_count': ((row['correct_count'] as int?) ?? 0) + gc,
              'wrong_count': ((row['wrong_count'] as int?) ?? 0) + gw,
            },
            where: 'tense = ? AND user_id = ?',
            whereArgs: [tense, userId],
          );
        }
      }
      await txn.delete('stats', where: 'user_id IS NULL');

      // Ensembles du mode créateur créés en invité : ils passent au compte
      // et seront envoyés à la prochaine synchro.
      await txn.update('custom_sets', {
        'user_id': userId,
        'needs_sync': 1,
      }, where: 'user_id IS NULL AND is_deleted = 0');
    });
  }

  /// Efface les données de l'invité (parties, statistiques, ensembles du mode
  /// créateur sans compte). Appelé à la déconnexion : les données d'invité
  /// sont rattachées au compte à chaque connexion, donc ce qui reste ici n'a
  /// plus de propriétaire. Les données des comptes ne sont jamais touchées.
  Future<void> clearGuestData() async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('runs', where: 'user_id IS NULL');
      await txn.delete('stats', where: 'user_id IS NULL');
      await txn.delete('custom_sets', where: 'user_id IS NULL');
    });
  }

  Future<bool> userHasBadge(int userId, String code) async {
    final db = await database;
    final rows = await db.query(
      'badges',
      where: 'user_id = ? AND code = ?',
      whereArgs: [userId, code],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<void> insertBadge({
    required int userId,
    required String code,
    required String title,
    String? description,
  }) async {
    final db = await database;
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    await db.insert('badges', {
      'user_id': userId,
      'code': code,
      'title': title,
      'description': description,
      'earned_at': nowMs,
    }, conflictAlgorithm: sqflite.ConflictAlgorithm.ignore);
  }

  // Pour les badges liés à l'Expert
  Future<bool> userHasPlayedExpert(int userId) async {
    final db = await database;
    final rows = await db.query(
      'runs',
      where: 'user_id = ? AND level = ?',
      whereArgs: [userId, 'expert'],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<List<Map<String, dynamic>>> getBadgesForUser(int userId) async {
    final db = await database;
    final rows = await db.query(
      'badges',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'earned_at DESC',
    );
    return rows;
  }

  Future<List<String>> getDistinctTenses() async {
    final db = await database;
    final rows = await db.rawQuery(
      "SELECT DISTINCT tense FROM verbs ORDER BY tense",
    );
    return rows
        .map((r) => (r['tense'] as String?) ?? '')
        .where((s) => s.isNotEmpty)
        .toList();
  }

  Future<List<String>> getDistinctVerbs() async {
    final db = await database;
    final rows = await db.rawQuery(
      "SELECT DISTINCT verb FROM verbs ORDER BY verb",
    );
    return rows
        .map((r) => (r['verb'] as String?) ?? '')
        .where((s) => s.isNotEmpty)
        .toList();
  }

  Future<Map<String, dynamic>?> getRandomExerciseForCustomSet(
    CustomSet set,
  ) async {
    final db = await database;

    if (set.verbs.isEmpty || set.tenses.isEmpty) {
      return null;
    }

    final verbPlaceholders = List.filled(set.verbs.length, '?').join(',');
    final tensePlaceholders = List.filled(set.tenses.length, '?').join(',');

    final args = <Object?>[...set.verbs, ...set.tenses];

    final rows = await db.rawQuery('''
    SELECT *
    FROM verbs
    WHERE verb IN ($verbPlaceholders)
      AND tense IN ($tensePlaceholders)
    ORDER BY RANDOM()
    LIMIT 1
    ''', args);

    return rows.isEmpty ? null : rows.first;
  }

  // -----------------------------------------------------------------------
  // CUSTOM SETS (mode créateur)
  // -----------------------------------------------------------------------

  /// [userId] null = invité.
  Future<int> insertCustomSet(CustomSet set, {required int? userId}) async {
    final db = await database;
    final now = DateTime.now();

    final toInsert = set.copyWith(
      createdAt: set.createdAt,
      updatedAt: now,
      needsSync: true, // nouvel ensemble -> à synchroniser
    );

    return db.insert('custom_sets', {...toInsert.toMap(), 'user_id': userId});
  }

  /// Ensembles du compte [userId] (ou de l'invité si null).
  Future<List<CustomSet>> getCustomSets({required int? userId}) async {
    final db = await database;
    final (userClause, userArgs) = _userFilter(userId);
    final maps = await db.query(
      'custom_sets',
      where: 'is_deleted = 0 AND $userClause',
      whereArgs: userArgs,
      orderBy: 'updated_at DESC, created_at DESC',
    );

    return maps.map((m) => CustomSet.fromMap(m)).toList();
  }

  Future<int> deleteCustomSet(int id) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;

    return db.update(
      'custom_sets',
      {
        'is_deleted': 1,
        'deleted_at': now,
        'updated_at': now,
        'needs_sync': 1, // à pousser au serveur
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> updateCustomSet(CustomSet set) async {
    final db = await database;
    if (set.id == null) return 0;

    final updated = set.copyWith(
      updatedAt: DateTime.now(),
      needsSync: true, // modification locale -> à resynchroniser
    );

    return db.update(
      'custom_sets',
      updated.toMap(),
      where: 'id = ?',
      whereArgs: [set.id],
    );
  }
  // -----------------------------------------------------------------------
  // SYNCHRO CUSTOM SETS AVEC LE SERVEUR
  // -----------------------------------------------------------------------

  /// Marque un ensemble comme correctement synchronisé avec le serveur.
  ///
  /// - met à jour remote_id (envoyé par le backend)
  /// - met updated_at = horodatage reçu du backend (pour résolution de conflits)
  /// - passe needs_sync = 0
  Future<void> markCustomSetSynced({
    required int localId,
    required String remoteId,
    required DateTime remoteUpdatedAt,
  }) async {
    final db = await database;
    await db.update(
      'custom_sets',
      {
        'remote_id': remoteId,
        'updated_at': remoteUpdatedAt.millisecondsSinceEpoch,
        'needs_sync': 0,
      },
      where: 'id = ?',
      whereArgs: [localId],
    );
  }

  /// Insère ou met à jour un ensemble reçu du serveur.
  ///
  /// Si un custom_set avec le même remote_id existe déjà en local,
  /// on le met à jour. Sinon, on l’insère.
  ///
  /// Retourne l'id local (SQLite).
  Future<int> upsertCustomSetFromRemote(
    CustomSet remoteSet, {
    required int? userId,
  }) async {
    final db = await database;

    if (remoteSet.remoteId == null) {
      throw ArgumentError(
        'remoteSet.remoteId ne doit pas être null dans upsertCustomSetFromRemote',
      );
    }

    // On cherche s’il existe déjà un set avec ce remote_id
    final existing = await db.query(
      'custom_sets',
      where: 'remote_id = ? AND ${_userFilter(userId).$1}',
      whereArgs: [remoteSet.remoteId, ..._userFilter(userId).$2],
      limit: 1,
    );

    // Tout ce qui vient du serveur est considéré comme synchro
    final localModel = remoteSet.copyWith(
      id: null, // id local sera fixé par SQLite
      needsSync: false, // déjà synchronisé
    );

    if (existing.isEmpty) {
      // INSERT
      return db.insert('custom_sets', {
        ...localModel.toMap(),
        'user_id': userId,
      });
    } else {
      // UPDATE
      final localId = existing.first['id'] as int;
      await db.update(
        'custom_sets',
        localModel.copyWith(id: localId).toMap(),
        where: 'id = ?',
        whereArgs: [localId],
      );
      return localId;
    }
  }

  Future<List<CustomSet>> getCustomSetsToSync({required int userId}) async {
    final db = await database;

    final rows = await db.query(
      'custom_sets',
      where: 'needs_sync = 1 AND user_id = ?',
      whereArgs: [userId],
      orderBy: 'updated_at ASC, created_at ASC',
    );

    return rows.map((m) => CustomSet.fromMap(m)).toList();
  }
}
