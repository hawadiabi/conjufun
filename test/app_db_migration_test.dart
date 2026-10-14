// Vérifie qu'une ancienne base est migrée vers la version 12 sans perte.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:conjufun/data/app_db.dart';

void main() {
  late Directory tmp;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    tmp = Directory.systemTemp.createTempSync('conjufun_migration_');
    await databaseFactoryFfi.setDatabasesPath(tmp.path);

    // Base telle qu'elle existait en version 11.
    final old = await databaseFactoryFfi.openDatabase(
      p.join(tmp.path, 'conjufun.db'),
      options: OpenDatabaseOptions(
        version: 11,
        onCreate: (db, v) async {
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
          )''');
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
            deleted_at INTEGER
          )''');
          await db.insert('custom_sets', {
            'name': 'Ancien ensemble',
            'school_level': 'level_cycle1',
            'tenses_json': 'présent,futur simple',
            'verbs_json': 'aimer,finir',
            'created_at': 1700000000000,
            'updated_at': 1700000000000,
            'max_questions': 8,
          });
        },
      ),
    );
    await old.close();
  });

  tearDownAll(() async {
    try {
      await (await AppDb.instance.database).close();
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  test(
    '11 vers 12 : colonne user_id ajoutée, anciens ensembles côté invité',
    () async {
      final db = await AppDb.instance.database;
      expect(await db.getVersion(), 12);

      final cols = await db.rawQuery('PRAGMA table_info(custom_sets)');
      expect(cols.map((c) => c['name']), contains('user_id'));

      final guestSets = await AppDb.instance.getCustomSets(userId: null);
      expect(guestSets, hasLength(1));
      expect(guestSets.first.name, 'Ancien ensemble');
      expect(guestSets.first.tenses, ['présent', 'futur simple']);
      expect(guestSets.first.maxQuestions, 8);
    },
  );
}
