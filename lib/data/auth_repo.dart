// lib/data/auth_repo.dart
import 'package:shared_preferences/shared_preferences.dart';

import '../session_notifier.dart';
import 'app_db.dart';
import 'password_hasher.dart';

/// Erreur d'authentification avec un message prêt à afficher.
class AuthException implements Exception {
  final String message;
  const AuthException(this.message);

  @override
  String toString() => message;
}

/// Seule implémentation d'authentification de l'application (inscription,
/// connexion, déconnexion, changement de mot de passe, suppression de compte).
///
/// Les mots de passe ne sont JAMAIS modifiés (pas de trim) : ce que l'élève
/// tape à l'inscription est exactement ce qu'il doit retaper à la connexion.
class AuthRepo {
  AuthRepo._();
  static final AuthRepo instance = AuthRepo._();

  // Clés de session (SharedPreferences)
  static const String kUserId = 'current_user_id';
  static const String kDisplayName = 'user_display_name';
  static const String kCurrentDisplayName = 'current_display_name';
  static const String kEmail = 'user_email';

  // Même clé que SyncService, pour qu'il n'y ait qu'un seul réglage.
  static const String _prefOnlineSync = 'sync_enabled';

  // Blocage simple après trop d'échecs (en mémoire, par email).
  static const int _maxFailures = 5;
  static const Duration _lockDuration = Duration(minutes: 1);
  final Map<String, int> _failures = {};
  final Map<String, DateTime> _lockedUntil = {};

  // ---------------------------------------------------------------------
  // Validation
  // ---------------------------------------------------------------------

  /// Retourne un message d'erreur, ou null si l'email est valide.
  static String? validateEmail(String email) {
    final e = email.trim();
    if (e.isEmpty) return 'Entre ton adresse courriel.';
    final ok = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$').hasMatch(e);
    return ok ? null : 'Adresse courriel invalide.';
  }

  /// Retourne un message d'erreur, ou null si le mot de passe est assez fort.
  static String? validatePassword(String password) {
    if (password.length < 8) {
      return 'Le mot de passe doit contenir au moins 8 caractères.';
    }
    if (!RegExp(r'[A-Za-zÀ-ÿ]').hasMatch(password) ||
        !RegExp(r'\d').hasMatch(password)) {
      return 'Le mot de passe doit contenir au moins une lettre et un chiffre.';
    }
    return null;
  }

  // ---------------------------------------------------------------------
  // Inscription / connexion
  // ---------------------------------------------------------------------

  /// Crée un compte, ouvre la session et rattache les parties jouées en invité.
  Future<void> signUp(
    String email,
    String password, {
    String? displayName,
  }) async {
    final emailErr = validateEmail(email);
    if (emailErr != null) throw AuthException(emailErr);
    final pwdErr = validatePassword(password);
    if (pwdErr != null) throw AuthException(pwdErr);

    final db = AppDb.instance;
    final emailLower = email.trim().toLowerCase();

    if (await db.getUserByEmail(emailLower) != null) {
      throw const AuthException('Un compte existe déjà avec ce courriel.');
    }

    final salt = PasswordHasher.newSalt();
    final hash = await PasswordHasher.hash(password, salt);
    final name = (displayName ?? '').trim().isNotEmpty
        ? displayName!.trim()
        : emailLower.split('@').first;

    final int id;
    try {
      id = await db.insertUser(
        email: emailLower,
        passwordHash: hash,
        salt: salt,
        displayName: name,
      );
    } catch (_) {
      // Contrainte unique (deux inscriptions en même temps)
      throw const AuthException('Un compte existe déjà avec ce courriel.');
    }

    await _openSession(id, name, emailLower);
    await db.attachGuestRunsToUser(id);
    notifyAuthChanged();
  }

  /// Connecte un utilisateur. Lance une [AuthException] en cas d'échec.
  /// Le message est volontairement le même pour « compte inconnu » et
  /// « mauvais mot de passe » (on ne révèle pas quels courriels existent).
  Future<Map<String, dynamic>> signIn(String email, String password) async {
    final emailLower = email.trim().toLowerCase();
    if (emailLower.isEmpty || password.isEmpty) {
      throw const AuthException('Entre ton courriel et ton mot de passe.');
    }

    final lockedUntil = _lockedUntil[emailLower];
    if (lockedUntil != null) {
      if (DateTime.now().isBefore(lockedUntil)) {
        throw const AuthException(
          'Trop de tentatives. Réessaie dans une minute.',
        );
      }
      _lockedUntil.remove(emailLower);
      _failures.remove(emailLower);
    }

    final db = AppDb.instance;
    final user = await db.getUserByEmail(emailLower);

    var ok = false;
    if (user != null) {
      final salt = (user['salt'] as String?) ?? '';
      final stored = (user['password_hash'] as String?) ?? '';
      ok = await PasswordHasher.verify(password, salt, stored);
    }

    if (!ok || user == null) {
      final n = (_failures[emailLower] ?? 0) + 1;
      _failures[emailLower] = n;
      if (n >= _maxFailures) {
        _lockedUntil[emailLower] = DateTime.now().add(_lockDuration);
      }
      throw const AuthException('Courriel ou mot de passe incorrect.');
    }

    _failures.remove(emailLower);

    final userId = user['id'] as int;

    // Migration silencieuse des anciens hash SHA-256 vers PBKDF2.
    final stored = (user['password_hash'] as String?) ?? '';
    if (PasswordHasher.needsUpgrade(stored)) {
      final newSalt = PasswordHasher.newSalt();
      final newHash = await PasswordHasher.hash(password, newSalt);
      await db.updateUserPassword(
        userId: userId,
        passwordHash: newHash,
        salt: newSalt,
      );
    }

    final displayName =
        (user['display_name'] as String?)?.trim().isNotEmpty == true
        ? user['display_name'] as String
        : emailLower.split('@').first;

    await _openSession(userId, displayName, emailLower);
    await db.attachGuestRunsToUser(userId);
    notifyAuthChanged();
    return user;
  }

  Future<Map<String, dynamic>?> login(String email, String password) async {
    try {
      return await signIn(email, password);
    } on AuthException {
      return null;
    }
  }

  /// Déconnexion : la session est entièrement effacée.
  Future<void> signOut() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(kUserId);
    await prefs.remove(kDisplayName);
    await prefs.remove(kCurrentDisplayName);
    await prefs.remove(kEmail);
    await AppDb.instance.clearGuestData();
    notifyAuthChanged();
  }

  // ---------------------------------------------------------------------
  // Compte
  // ---------------------------------------------------------------------

  /// Change le mot de passe après vérification de l'ancien.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final user = await getCurrentUser();
    if (user == null) throw const AuthException('Tu n\'es pas connecté.');

    final salt = (user['salt'] as String?) ?? '';
    final stored = (user['password_hash'] as String?) ?? '';
    if (!await PasswordHasher.verify(currentPassword, salt, stored)) {
      throw const AuthException('Mot de passe actuel incorrect.');
    }

    final err = validatePassword(newPassword);
    if (err != null) throw AuthException(err);

    final newSalt = PasswordHasher.newSalt();
    final newHash = await PasswordHasher.hash(newPassword, newSalt);
    await AppDb.instance.updateUserPassword(
      userId: user['id'] as int,
      passwordHash: newHash,
      salt: newSalt,
    );
  }

  /// Supprime le compte et toutes ses données, après confirmation par mot de
  /// passe, puis ferme la session.
  Future<void> deleteAccount(String password) async {
    final user = await getCurrentUser();
    if (user == null) throw const AuthException('Tu n\'es pas connecté.');

    final salt = (user['salt'] as String?) ?? '';
    final stored = (user['password_hash'] as String?) ?? '';
    if (!await PasswordHasher.verify(password, salt, stored)) {
      throw const AuthException('Mot de passe incorrect.');
    }

    await AppDb.instance.deleteUser(user['id'] as int);
    await signOut();
    notifyDataChanged();
  }

  // ---------------------------------------------------------------------
  // Session
  // ---------------------------------------------------------------------

  /// Retourne l'utilisateur connecté (ou null). Si l'id mémorisé ne
  /// correspond plus à aucun compte, la session est nettoyée.
  Future<Map<String, dynamic>?> getCurrentUser() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getInt(kUserId);
    if (id == null) return null;

    final user = await AppDb.instance.getUserById(id);
    if (user == null) {
      await prefs.remove(kUserId);
      await prefs.remove(kDisplayName);
      await prefs.remove(kCurrentDisplayName);
      await prefs.remove(kEmail);
      return null;
    }
    return user;
  }

  /// Id de l'utilisateur connecté, ou null (invité).
  Future<int?> getCurrentUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(kUserId);
  }

  Future<void> _openSession(int id, String displayName, String email) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(kUserId, id);
    await prefs.setString(kDisplayName, displayName);
    await prefs.setString(kCurrentDisplayName, displayName);
    await prefs.setString(kEmail, email);
  }

  // ---------------------------------------------------------------------
  // Réglage de synchro (la synchro réelle est dans SyncService)
  // ---------------------------------------------------------------------

  Future<void> setOnlineSyncEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefOnlineSync, enabled);
  }

  Future<bool> isOnlineSyncEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefOnlineSync) ?? false;
  }
}
