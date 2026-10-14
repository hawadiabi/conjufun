import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:conjufun/data/password_hasher.dart';

void main() {
  group('PasswordHasher', () {
    test(
      'vecteur de test PBKDF2-HMAC-SHA256 connu (RFC 7914, 1 itération)',
      () async {
        // P = "passwd", S = "salt", c = 1, les 32 premiers octets.
        const stored =
            r'pbkdf2-sha256$1$'
            '55ac046e56e3089fec1691c22544b605f94185216dde0465e68b9d57c20dacbc';
        expect(await PasswordHasher.verify('passwd', 'salt', stored), isTrue);
        expect(await PasswordHasher.verify('autre', 'salt', stored), isFalse);
      },
    );

    test(
      'hash puis verify : bon mot de passe accepté, mauvais refusé',
      () async {
        const salt = 'selDeTest12345';
        final stored = await PasswordHasher.hash('Motdepasse1', salt);
        expect(stored.startsWith(r'pbkdf2-sha256$60000$'), isTrue);
        expect(
          await PasswordHasher.verify('Motdepasse1', salt, stored),
          isTrue,
        );
        expect(
          await PasswordHasher.verify('motdepasse1', salt, stored),
          isFalse,
        );
      },
    );

    test('un autre sel donne un autre hash', () async {
      final a = await PasswordHasher.hash('Motdepasse1', 'sel-A');
      final b = await PasswordHasher.hash('Motdepasse1', 'sel-B');
      expect(a, isNot(b));
    });

    test('ancien format SHA-256 toujours accepté et à migrer', () async {
      const salt = 'ancienSel';
      const password = 'Ancien1234';
      final legacy = sha256.convert(utf8.encode('$salt$password')).toString();

      expect(await PasswordHasher.verify(password, salt, legacy), isTrue);
      expect(await PasswordHasher.verify('mauvais', salt, legacy), isFalse);
      expect(PasswordHasher.needsUpgrade(legacy), isTrue);
    });

    test('needsUpgrade', () {
      expect(PasswordHasher.needsUpgrade(r'pbkdf2-sha256$60000$abcd'), isFalse);
      expect(PasswordHasher.needsUpgrade(r'pbkdf2-sha256$1000$abcd'), isTrue);
      expect(PasswordHasher.needsUpgrade(r'pbkdf2-sha256$abc'), isTrue);
    });

    test('hash stocké mal formé refusé', () async {
      expect(
        await PasswordHasher.verify('x', 's', r'pbkdf2-sha256$abc$def'),
        isFalse,
      );
      expect(
        await PasswordHasher.verify('x', 's', r'pbkdf2-sha256$0$def'),
        isFalse,
      );
    });

    test('newSalt : longueur et variété', () {
      expect(PasswordHasher.newSalt().length, 16);
      expect(PasswordHasher.newSalt(24).length, 24);
      expect(PasswordHasher.newSalt(), isNot(PasswordHasher.newSalt()));
    });
  });
}
