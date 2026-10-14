// Outils communs aux tests qui utilisent la vraie base SQLite (AppDb).
//
// Utilise une base temporaire, jamais la vraie base de l'app.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:conjufun/data/app_db.dart';

Directory? _tmp;

/// À appeler dans setUpAll. Crée la base (schéma + import du LEFFF).
Future<void> initTestDb() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  _tmp = Directory.systemTemp.createTempSync('conjufun_test_');
  await databaseFactoryFfi.setDatabasesPath(_tmp!.path);
  await AppDb.instance.database;
}

/// À appeler dans setUp : vide les tables de joueurs et la session.
/// (La table des verbes est conservée : l'import du LEFFF est long.)
Future<void> resetTestData() async {
  final db = await AppDb.instance.database;
  for (final t in ['runs', 'stats', 'badges', 'custom_sets', 'users']) {
    await db.delete(t);
  }
  SharedPreferences.setMockInitialValues({});
}

/// À appeler dans tearDownAll.
Future<void> disposeTestDb() async {
  try {
    final db = await AppDb.instance.database;
    await db.close();
    _tmp?.deleteSync(recursive: true);
  } catch (_) {
    // Sous Windows, le fichier peut rester verrouillé : sans importance.
  }
}

int _counter = 0;

/// Courriel unique par appel (le blocage après échecs est mémorisé par courriel).
String uniqueEmail([String prefix = 'user']) =>
    '$prefix${_counter++}@example.com';
