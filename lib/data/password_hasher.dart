import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show compute;

/// Hachage des mots de passe : PBKDF2-HMAC-SHA256 (sans dépendance en plus de
/// `crypto`, déjà utilisée par le projet).
///
/// Format stocké dans `users.password_hash` :
///   `pbkdf2-sha256$<itérations>$<hash hexadécimal>`
/// Les anciens comptes ont un simple SHA-256(sel + mot de passe) en
/// hexadécimal. Ils sont toujours acceptés puis migrés automatiquement vers
/// PBKDF2 à la prochaine connexion réussie (voir AuthRepo.signIn).
class PasswordHasher {
  PasswordHasher._();

  static const String _prefix = 'pbkdf2-sha256';
  static const int currentIterations = 60000;

  static String newSalt([int length = 16]) {
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final r = Random.secure();
    return List.generate(length, (_) => chars[r.nextInt(chars.length)]).join();
  }

  /// Calcule le hash PBKDF2 (dans un isolate pour ne pas bloquer l'interface).
  static Future<String> hash(String password, String salt) async {
    final hex = await compute(_pbkdf2Hex, <Object>[
      password,
      salt,
      currentIterations,
    ]);
    return '$_prefix\$$currentIterations\$$hex';
  }

  static Future<bool> verify(
    String password,
    String salt,
    String stored,
  ) async {
    if (stored.startsWith('$_prefix\$')) {
      final parts = stored.split('\$');
      if (parts.length != 3) return false;
      final iterations = int.tryParse(parts[1]);
      if (iterations == null || iterations <= 0) return false;
      final hex = await compute(_pbkdf2Hex, <Object>[
        password,
        salt,
        iterations,
      ]);
      return _constantTimeEquals(hex, parts[2]);
    }

    // Ancien format : SHA-256(sel + mot de passe)
    final legacy = sha256.convert(utf8.encode('$salt$password')).toString();
    return _constantTimeEquals(legacy, stored);
  }

  /// true si le hash stocké n'est pas au format / à la force actuels.
  static bool needsUpgrade(String stored) {
    if (!stored.startsWith('$_prefix\$')) return true;
    final parts = stored.split('\$');
    if (parts.length != 3) return true;
    final iterations = int.tryParse(parts[1]) ?? 0;
    return iterations < currentIterations;
  }

  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}

/// Fonction de premier niveau (exigée par `compute`).
String _pbkdf2Hex(List<Object> args) {
  final password = args[0] as String;
  final salt = args[1] as String;
  final iterations = args[2] as int;

  final hmac = Hmac(sha256, utf8.encode(password));
  final saltBytes = utf8.encode(salt);

  // Un seul bloc suffit : 32 octets demandés = taille de sortie de SHA-256.
  final first = Uint8List(saltBytes.length + 4)
    ..setRange(0, saltBytes.length, saltBytes);
  first[saltBytes.length + 3] = 1; // INT(1) sur 4 octets, big-endian

  var u = Uint8List.fromList(hmac.convert(first).bytes);
  final t = Uint8List.fromList(u);

  for (var i = 1; i < iterations; i++) {
    u = Uint8List.fromList(hmac.convert(u).bytes);
    for (var j = 0; j < t.length; j++) {
      t[j] ^= u[j];
    }
  }

  final sb = StringBuffer();
  for (final b in t) {
    sb.write(b.toRadixString(16).padLeft(2, '0'));
  }
  return sb.toString();
}
