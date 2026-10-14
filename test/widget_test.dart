import 'package:flutter_test/flutter_test.dart';
import 'package:conjufun/data/badge_catalog.dart';

void main() {
  group('Catalogue de badges', () {
    test('les codes sont uniques', () {
      final codes = kBadgeCatalog.map((b) => b.code).toList();
      expect(codes.toSet().length, codes.length);
    });

    test('les rangs sont dans l\'ordre croissant', () {
      for (var i = 1; i < kRankSteps.length; i++) {
        expect(kRankSteps[i].minScore, greaterThan(kRankSteps[i - 1].minScore));
      }
    });

    test('formatNumber sépare les milliers', () {
      expect(formatNumber(999), '999');
      expect(formatNumber(15000), '15 000');
    });
  });

  group('rankForScore', () {
    test('au départ', () {
      final r = rankForScore(0);
      expect(r.current.name, 'Début du parcours');
      expect(r.remaining, 1000);
      expect(r.fraction, 0.0);
      expect(r.isMax, isFalse);
    });

    test('à mi-chemin du premier rang', () {
      final r = rankForScore(500);
      expect(r.remaining, 500);
      expect(r.fraction, 0.5);
    });

    test('un seuil atteint donne le rang correspondant', () {
      final r = rankForScore(1000);
      expect(r.current.name, 'Apprenti·e des verbes');
      expect(r.remaining, 4000);
    });

    test('le rang maximum', () {
      final r = rankForScore(60000);
      expect(r.isMax, isTrue);
      expect(r.remaining, 0);
      expect(r.fraction, 1.0);
    });
  });
}
