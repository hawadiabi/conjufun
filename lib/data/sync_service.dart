// lib/data/sync_service.dart
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'app_db.dart';
import '../models/custom_set.dart';
import 'auth_repo.dart';

class SyncService {
  SyncService._();
  static final SyncService instance = SyncService._();

  /// Pour les tests en local (backend Node sur la même machine) :
  final String baseUrl = 'http://localhost:3000';

  /// Méthode à appeler depuis l'UI (bouton "Synchroniser maintenant", etc.)
  /// - Vérifie si la synchro est activée
  /// - Vérifie s'il y a un utilisateur connecté
  /// - Lance la synchro des CustomSets
  Future<void> syncCustomSetsIfEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool('sync_enabled') ?? false;
    if (!enabled) return;

    final user = await AuthRepo.instance.getCurrentUser();
    final userId = user?['id'] as int?;
    if (userId == null) {
      // invité : on peut décider de ne pas synchroniser pour l’instant
      return;
    }

    await syncCustomSetsForUser(userId);
  }

  Future<void> syncCustomSetsForUser(int userId) async {
    final prefs = await SharedPreferences.getInstance();
    final lastSyncIso = prefs.getString('custom_sets_last_sync_at');

    final db = await AppDb.instance.database;

    // ------------------------------------------------------------------
    // 1) Récupérer les ensembles à synchroniser (needs_sync = 1)
    // ------------------------------------------------------------------
    final localRows = await db.query(
      'custom_sets',
      where: 'needs_sync = 1 AND user_id = ?',
      whereArgs: [userId],
    );
    final localSets = localRows.map((m) => CustomSet.fromMap(m)).toList();

    // Conversion en JSON API
    final pushPayload = localSets
        .map<Map<String, dynamic>>(
          (s) => {
            'remote_id': s.remoteId,
            'name': s.name,
            'school_level': s.schoolLevel,
            'tenses': s.tenses,
            'verbs': s.verbs,
            'created_at': s.createdAt.toUtc().toIso8601String(),
            'updated_at': s.updatedAt.toUtc().toIso8601String(),
            'max_questions': s.maxQuestions,
            'is_deleted': s.isDeleted,
            'deleted_at': s.deletedAt?.toUtc().toIso8601String(),
          },
        )
        .toList();

    final body = <String, dynamic>{
      'user_id': userId,
      'push': pushPayload,
      if (lastSyncIso != null) 'since': lastSyncIso,
    };

    final uri = Uri.parse('$baseUrl/sync/custom_sets');

    // ------------------------------------------------------------------
    // 2) Appel HTTP à l’API de synchro
    // ------------------------------------------------------------------
    final resp = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );

    if (resp.statusCode != 200) {
      return;
    }

    final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
    final serverTime = decoded['server_time'] as String?;
    final updatedList = (decoded['updated'] as List?) ?? [];

    // ------------------------------------------------------------------
    // 3) Appliquer la réponse "updated" dans SQLite
    // ------------------------------------------------------------------
    await db.transaction((txn) async {
      for (final item in updatedList) {
        final m = Map<String, dynamic>.from(item as Map);

        final remoteId = m['remote_id'] as String?;
        if (remoteId == null) continue;

        final name = m['name'] as String? ?? 'Sans nom';
        final schoolLevel = m['school_level'] as String?;
        final tensesList = (m['tenses'] as List? ?? [])
            .map((e) => e.toString())
            .toList();
        final verbsList = (m['verbs'] as List? ?? [])
            .map((e) => e.toString())
            .toList();

        final createdAtStr = m['created_at'] as String?;
        final updatedAtStr = m['updated_at'] as String?;

        final createdAt = createdAtStr != null
            ? DateTime.tryParse(createdAtStr) ?? DateTime.now().toUtc()
            : DateTime.now().toUtc();
        final updatedAt = updatedAtStr != null
            ? DateTime.tryParse(updatedAtStr) ?? createdAt
            : createdAt;

        final isDeleted = m['is_deleted'] == true;
        final deletedAtStr = m['deleted_at'] as String?;
        final deletedAt = deletedAtStr != null
            ? DateTime.tryParse(deletedAtStr)?.toUtc()
            : null;

        final maxQuestions = m['max_questions'] as int?;

        // Chercher si on a déjà un set avec ce remote_id
        final existing = await txn.query(
          'custom_sets',
          where: 'remote_id = ? AND user_id = ?',
          whereArgs: [remoteId, userId],
          limit: 1,
        );

        if (existing.isEmpty) {
          // Nouveau set côté client (créé sur le serveur, ou importé du serveur)
          await txn.insert('custom_sets', {
            'name': name,
            'school_level': schoolLevel,
            'tenses_json': tensesList.join(','),
            'verbs_json': verbsList.join(','),
            'created_at': createdAt.millisecondsSinceEpoch,
            'updated_at': updatedAt.millisecondsSinceEpoch,
            'max_questions': maxQuestions,
            'remote_id': remoteId,
            'user_id': userId,
            'needs_sync': 0, // déjà à jour avec le serveur
            'is_deleted': isDeleted ? 1 : 0,
            'deleted_at': deletedAt?.millisecondsSinceEpoch,
          });
        } else {
          // Conflit éventuel → last write wins
          final localRow = existing.first;
          final localUpdatedMs =
              (localRow['updated_at'] as int?) ??
              (localRow['created_at'] as int);
          final localUpdatedAt = DateTime.fromMillisecondsSinceEpoch(
            localUpdatedMs,
          );

          // Si la version serveur est plus récente, on écrase la locale
          if (updatedAt.isAfter(localUpdatedAt)) {
            await txn.update(
              'custom_sets',
              {
                'name': name,
                'school_level': schoolLevel,
                'tenses_json': tensesList.join(','),
                'verbs_json': verbsList.join(','),
                'created_at': createdAt.millisecondsSinceEpoch,
                'updated_at': updatedAt.millisecondsSinceEpoch,
                'max_questions': maxQuestions,
                'remote_id': remoteId,
                'needs_sync': 0,
                'is_deleted': isDeleted ? 1 : 0,
                'deleted_at': deletedAt?.millisecondsSinceEpoch,
              },
              where: 'id = ?',
              whereArgs: [localRow['id']],
            );
          }
        }
      }

      // ----------------------------------------------------------------
      // 4) Marquer comme synchronisés les sets poussés avec succès
      // ----------------------------------------------------------------
      if (localSets.isNotEmpty) {
        final ids = localSets
            .where((s) => s.id != null)
            .map((s) => s.id!)
            .toList();
        if (ids.isNotEmpty) {
          final placeholders = List.filled(ids.length, '?').join(',');
          await txn.rawUpdate(
            'UPDATE custom_sets SET needs_sync = 0 WHERE id IN ($placeholders)',
            ids,
          );
        }
      }
    });

    // ------------------------------------------------------------------
    // 5) Mémoriser la dernière synchro
    // ------------------------------------------------------------------
    final newLastSync = serverTime ?? DateTime.now().toUtc().toIso8601String();
    await prefs.setString('custom_sets_last_sync_at', newLastSync);
  }
}
