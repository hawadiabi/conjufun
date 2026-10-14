class CustomSet {
  final int? id;
  final String name;
  final String? schoolLevel;
  final List<String> tenses;
  final List<String> verbs;

  /// Date de création locale
  final DateTime createdAt;

  /// Dernière modification (locale ou serveur, utilisée pour la résolution de conflits)
  final DateTime updatedAt;

  /// Nombre max de questions (optionnel)
  final int? maxQuestions;

  /// Identifiant sur le serveur (null si jamais synchronisé)
  final String? remoteId;

  /// true = doit être synchronisé avec le serveur
  final bool needsSync;

  /// Marqueur de suppression logique
  final bool isDeleted;

  /// Date de suppression (pour résoudre les conflits)
  final DateTime? deletedAt;

  const CustomSet({
    this.id,
    required this.name,
    this.schoolLevel,
    required this.tenses,
    required this.verbs,
    required this.createdAt,
    required this.updatedAt,
    this.maxQuestions,
    this.remoteId,
    this.needsSync = false,
    this.isDeleted = false,
    this.deletedAt,
  });

  factory CustomSet.newLocal({
    int? id,
    required String name,
    String? schoolLevel,
    required List<String> tenses,
    required List<String> verbs,
    int? maxQuestions,
  }) {
    final now = DateTime.now();
    return CustomSet(
      id: id,
      name: name,
      schoolLevel: schoolLevel,
      tenses: tenses,
      verbs: verbs,
      createdAt: now,
      updatedAt: now,
      maxQuestions: maxQuestions,
      remoteId: null,
      needsSync: true,
    );
  }

  CustomSet copyWith({
    int? id,
    String? name,
    String? schoolLevel,
    List<String>? tenses,
    List<String>? verbs,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? maxQuestions,
    String? remoteId,
    bool? needsSync,
    bool? isDeleted,
    DateTime? deletedAt,
  }) {
    return CustomSet(
      id: id ?? this.id,
      name: name ?? this.name,
      schoolLevel: schoolLevel ?? this.schoolLevel,
      tenses: tenses ?? this.tenses,
      verbs: verbs ?? this.verbs,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      maxQuestions: maxQuestions ?? this.maxQuestions,
      remoteId: remoteId ?? this.remoteId,
      needsSync: needsSync ?? this.needsSync,
      isDeleted: isDeleted ?? this.isDeleted,
      deletedAt: deletedAt ?? this.deletedAt,
    );
  }

  // ---------- PERSISTENCE LOCALE (SQLite) ----------
  // Le propriétaire (user_id) est géré par AppDb, pas par ce modèle.

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'school_level': schoolLevel,
      'tenses_json': tenses.join(','),
      'verbs_json': verbs.join(','),
      'created_at': createdAt.millisecondsSinceEpoch,
      'updated_at': updatedAt.millisecondsSinceEpoch,
      'max_questions': maxQuestions,
      'remote_id': remoteId,
      'needs_sync': needsSync ? 1 : 0,
      'is_deleted': isDeleted ? 1 : 0,
      'deleted_at': deletedAt?.millisecondsSinceEpoch,
    };
  }

  factory CustomSet.fromMap(Map<String, dynamic> map) {
    final createdMs = map['created_at'] as int;
    final updatedRaw = map['updated_at'];
    final updatedMs = updatedRaw is int ? updatedRaw : createdMs;

    final tensesStr = map['tenses_json'] as String? ?? '';
    final verbsStr = map['verbs_json'] as String? ?? '';

    final deletedMs = map['deleted_at'] as int?;
    final deletedAt = deletedMs != null
        ? DateTime.fromMillisecondsSinceEpoch(deletedMs)
        : null;

    return CustomSet(
      id: map['id'] as int?,
      name: map['name'] as String,
      schoolLevel: map['school_level'] as String?,
      tenses: tensesStr.split(',').where((e) => e.isNotEmpty).toList(),
      verbs: verbsStr.split(',').where((e) => e.isNotEmpty).toList(),
      createdAt: DateTime.fromMillisecondsSinceEpoch(createdMs),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(updatedMs),
      maxQuestions: map['max_questions'] as int?,
      remoteId: map['remote_id'] as String?,
      needsSync: (map['needs_sync'] as int? ?? 0) == 1,
      isDeleted: (map['is_deleted'] as int? ?? 0) == 1,
      deletedAt: deletedAt,
    );
  }

  // ---------- SYNCHRO SERVEUR ----------

  /// JSON envoyé au serveur
  Map<String, dynamic> toRemoteJson() {
    return {
      'id': remoteId,
      'name': name,
      'school_level': schoolLevel,
      'tenses': tenses,
      'verbs': verbs,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'max_questions': maxQuestions,
    };
  }

  /// Construction depuis la réponse JSON du serveur
  factory CustomSet.fromRemoteJson(Map<String, dynamic> json) {
    final createdStr = json['created_at'] as String?;
    final updatedStr = json['updated_at'] as String?;

    final nowIso = DateTime.now().toIso8601String();
    final createdAt = DateTime.parse(createdStr ?? updatedStr ?? nowIso);
    final updatedAt = DateTime.parse(updatedStr ?? createdStr ?? nowIso);

    return CustomSet(
      id: null,
      remoteId: json['id'] as String?,
      name: json['name'] as String,
      schoolLevel: json['school_level'] as String?,
      tenses: List<String>.from(json['tenses'] as List),
      verbs: List<String>.from(json['verbs'] as List),
      createdAt: createdAt,
      updatedAt: updatedAt,
      maxQuestions: json['max_questions'] as int?,
      needsSync: false,
    );
  }

  // ---------- PARTAGE (export / import offline) ----------

  String exportCode() {
    final buffer = StringBuffer();
    buffer.write('CFSET1|');
    buffer.write(name.replaceAll('|', ' '));
    buffer.write('|');
    buffer.write((schoolLevel ?? '').replaceAll('|', ' '));
    buffer.write('|');
    buffer.write(tenses.join(','));
    buffer.write('|');
    buffer.write(verbs.join(','));
    buffer.write('|');
    buffer.write(createdAt.millisecondsSinceEpoch.toString());
    buffer.write('|');
    buffer.write(maxQuestions?.toString() ?? '');
    return buffer.toString();
  }

  /// Lit un code de partage. Retourne null si le code est invalide.
  /// La date de création du code est ignorée : l'ensemble importé reçoit la
  /// date du jour (voir [CustomSet.newLocal]).
  static CustomSet? fromShareCode(String code) {
    try {
      if (!code.startsWith('CFSET1|')) {
        return null;
      }
      final parts = code.split('|');
      if (parts.length < 6) {
        return null;
      }

      final name = parts[1].trim();
      final schoolLevel = parts[2].trim().isEmpty ? null : parts[2].trim();
      final tenses = parts[3].split(',').where((e) => e.isNotEmpty).toList();
      final verbs = parts[4].split(',').where((e) => e.isNotEmpty).toList();

      int? maxQuestions;
      if (parts.length >= 7 && parts[6].trim().isNotEmpty) {
        maxQuestions = int.tryParse(parts[6].trim());
      }

      return CustomSet.newLocal(
        name: name,
        schoolLevel: schoolLevel,
        tenses: tenses,
        verbs: verbs,
        maxQuestions: maxQuestions,
      );
    } catch (_) {
      // Code corrompu
      return null;
    }
  }
}
