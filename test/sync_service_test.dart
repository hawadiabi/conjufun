// Teste le client de synchronisation contre un faux serveur (MockClient).
// Ces tests décrivent aussi le contrat que le futur serveur Flask doit respecter.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:conjufun/data/app_db.dart';
import 'package:conjufun/data/sync_service.dart';
import 'package:conjufun/models/custom_set.dart';

import 'helpers/test_db.dart';

const _jsonHeaders = {'content-type': 'application/json; charset=utf-8'};

http.Response _ok(Map<String, dynamic> body) =>
    http.Response(jsonEncode(body), 200, headers: _jsonHeaders);

/// Exécute [body] avec [client] comme client HTTP.
Future<T> _with<T>(MockClient client, Future<T> Function() body) =>
    http.runWithClient(body, () => client);

Future<int> _user() => AppDb.instance.insertUser(
  email: uniqueEmail('sync'),
  passwordHash: 'h',
  salt: 's',
);

CustomSet _set(String name) =>
    CustomSet.newLocal(name: name, tenses: ['présent'], verbs: ['aimer']);

Map<String, dynamic> _remoteItem({
  required String remoteId,
  String name = 'Du serveur',
  String updatedAt = '2026-06-01T12:00:00Z',
  bool isDeleted = false,
}) => {
  'remote_id': remoteId,
  'name': name,
  'school_level': 'level_cycle2',
  'tenses': ['futur simple'],
  'verbs': ['finir', 'aller'],
  'created_at': '2026-01-01T00:00:00Z',
  'updated_at': updatedAt,
  'max_questions': 12,
  'is_deleted': isDeleted,
  'deleted_at': null,
};

void main() {
  final sync = SyncService.instance;
  final db = AppDb.instance;

  setUpAll(initTestDb);
  setUp(resetTestData);
  tearDownAll(disposeTestDb);

  test('envoie les ensembles à synchroniser au bon format', () async {
    final uid = await _user();
    await db.insertCustomSet(_set('À envoyer'), userId: uid);

    late http.Request seen;
    final client = MockClient((req) async {
      seen = req;
      return _ok({'server_time': '2026-06-01T12:00:00Z', 'updated': []});
    });
    await _with(client, () => sync.syncCustomSetsForUser(uid));

    expect(seen.method, 'POST');
    expect(seen.url.path, '/sync/custom_sets');
    expect(seen.headers['Content-Type'], contains('application/json'));

    final body = jsonDecode(seen.body) as Map<String, dynamic>;
    expect(body['user_id'], uid);
    expect(body.containsKey('since'), isFalse); // première synchro
    final push = body['push'] as List;
    expect(push, hasLength(1));
    final item = push.first as Map<String, dynamic>;
    expect(item['name'], 'À envoyer');
    expect(item['tenses'], ['présent']);
    expect(item['verbs'], ['aimer']);
    expect(item['is_deleted'], false);
    expect(item['remote_id'], isNull);
    for (final k in [
      'school_level',
      'created_at',
      'updated_at',
      'max_questions',
      'deleted_at',
    ]) {
      expect(item.containsKey(k), isTrue, reason: 'champ manquant : $k');
    }
  });

  test(
    'après succès : plus rien à envoyer, date de synchro mémorisée, "since" au tour suivant',
    () async {
      final uid = await _user();
      await db.insertCustomSet(_set('Un'), userId: uid);

      final bodies = <Map<String, dynamic>>[];
      final client = MockClient((req) async {
        bodies.add(jsonDecode(req.body) as Map<String, dynamic>);
        return _ok({'server_time': '2026-06-01T12:00:00Z', 'updated': []});
      });

      await _with(client, () => sync.syncCustomSetsForUser(uid));
      expect(await db.getCustomSetsToSync(userId: uid), isEmpty);
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('custom_sets_last_sync_at'),
        '2026-06-01T12:00:00Z',
      );

      await _with(client, () => sync.syncCustomSetsForUser(uid));
      expect(bodies.last['since'], '2026-06-01T12:00:00Z');
      expect(bodies.last['push'], isEmpty);
    },
  );

  test('un ensemble reçu du serveur est inséré, déjà synchronisé', () async {
    final uid = await _user();
    final client = MockClient(
      (_) async => _ok({
        'server_time': '2026-06-02T00:00:00Z',
        'updated': [_remoteItem(remoteId: 'srv-1')],
      }),
    );
    await _with(client, () => sync.syncCustomSetsForUser(uid));

    final sets = await db.getCustomSets(userId: uid);
    expect(sets, hasLength(1));
    final s = sets.first;
    expect(s.remoteId, 'srv-1');
    expect(s.name, 'Du serveur');
    expect(s.tenses, ['futur simple']);
    expect(s.verbs, ['finir', 'aller']);
    expect(s.maxQuestions, 12);
    expect(s.needsSync, isFalse);
  });

  test('conflit : la version la plus récente gagne', () async {
    final uid = await _user();
    final id = await db.insertCustomSet(_set('Local'), userId: uid);
    await db.markCustomSetSynced(
      localId: id,
      remoteId: 'srv-2',
      remoteUpdatedAt: DateTime.utc(2026, 3, 1),
    );

    // Serveur plus ancien : la version locale est gardée.
    await _with(
      MockClient(
        (_) async => _ok({
          'server_time': 't',
          'updated': [
            _remoteItem(
              remoteId: 'srv-2',
              name: 'Vieux',
              updatedAt: '2026-01-01T00:00:00Z',
            ),
          ],
        }),
      ),
      () => sync.syncCustomSetsForUser(uid),
    );
    expect((await db.getCustomSets(userId: uid)).first.name, 'Local');

    // Serveur plus récent : il écrase la version locale.
    await _with(
      MockClient(
        (_) async => _ok({
          'server_time': 't',
          'updated': [
            _remoteItem(
              remoteId: 'srv-2',
              name: 'Récent',
              updatedAt: '2026-09-01T00:00:00Z',
            ),
          ],
        }),
      ),
      () => sync.syncCustomSetsForUser(uid),
    );
    final after = await db.getCustomSets(userId: uid);
    expect(after, hasLength(1));
    expect(after.first.name, 'Récent');
  });

  test('suppression venue du serveur', () async {
    final uid = await _user();
    final id = await db.insertCustomSet(_set('À effacer'), userId: uid);
    await db.markCustomSetSynced(
      localId: id,
      remoteId: 'srv-3',
      remoteUpdatedAt: DateTime.utc(2026, 3, 1),
    );
    await _with(
      MockClient(
        (_) async => _ok({
          'server_time': 't',
          'updated': [
            _remoteItem(
              remoteId: 'srv-3',
              updatedAt: '2026-09-01T00:00:00Z',
              isDeleted: true,
            ),
          ],
        }),
      ),
      () => sync.syncCustomSetsForUser(uid),
    );
    expect(await db.getCustomSets(userId: uid), isEmpty);
  });

  test('erreur serveur : rien n\'est marqué comme synchronisé', () async {
    final uid = await _user();
    await db.insertCustomSet(_set('Reste'), userId: uid);

    await _with(
      MockClient((_) async => http.Response('boom', 500)),
      () => sync.syncCustomSetsForUser(uid),
    );

    expect(await db.getCustomSetsToSync(userId: uid), hasLength(1));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('custom_sets_last_sync_at'), isNull);
  });

  test('n\'envoie jamais les ensembles d\'un autre compte', () async {
    final a = await _user();
    final b = await _user();
    await db.insertCustomSet(_set('De A'), userId: a);
    await db.insertCustomSet(_set('De B'), userId: b);

    late Map<String, dynamic> body;
    await _with(
      MockClient((req) async {
        body = jsonDecode(req.body) as Map<String, dynamic>;
        return _ok({'server_time': 't', 'updated': []});
      }),
      () => sync.syncCustomSetsForUser(a),
    );

    final names = (body['push'] as List)
        .map((e) => (e as Map)['name'])
        .toList();
    expect(names, ['De A']);
    expect(await db.getCustomSetsToSync(userId: b), hasLength(1));
  });

  group('syncCustomSetsIfEnabled', () {
    test('ne fait aucune requête si la synchro est désactivée', () async {
      var calls = 0;
      final uid = await _user();
      SharedPreferences.setMockInitialValues({'current_user_id': uid});
      await _with(
        MockClient((_) async {
          calls++;
          return _ok({'server_time': 't', 'updated': []});
        }),
        () => sync.syncCustomSetsIfEnabled(),
      );
      expect(calls, 0);
    });

    test('ne fait aucune requête pour un invité', () async {
      var calls = 0;
      SharedPreferences.setMockInitialValues({'sync_enabled': true});
      await _with(
        MockClient((_) async {
          calls++;
          return _ok({'server_time': 't', 'updated': []});
        }),
        () => sync.syncCustomSetsIfEnabled(),
      );
      expect(calls, 0);
    });

    test(
      'synchronise quand elle est activée et qu\'un compte est connecté',
      () async {
        var calls = 0;
        final uid = await _user();
        SharedPreferences.setMockInitialValues({
          'sync_enabled': true,
          'current_user_id': uid,
        });
        await _with(
          MockClient((_) async {
            calls++;
            return _ok({'server_time': 't', 'updated': []});
          }),
          () => sync.syncCustomSetsIfEnabled(),
        );
        expect(calls, 1);
      },
    );
  });
}
