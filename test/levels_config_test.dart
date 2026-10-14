import 'package:flutter_test/flutter_test.dart';
import 'package:conjufun/config/levels_config.dart';
import 'package:conjufun/viewmodels/exercise_vm.dart' show GameLevel;

void main() {
  group('Niveaux', () {
    test('points par bonne réponse', () {
      expect(GameLevel.level_cycle1.pointsPerAnswer, 5);
      expect(GameLevel.level_cycle2.pointsPerAnswer, 8);
      expect(GameLevel.level_cycle3.pointsPerAnswer, 11);
      expect(GameLevel.level_sec1.pointsPerAnswer, 14);
      expect(GameLevel.level_sec2.pointsPerAnswer, 17);
      expect(GameLevel.expert.pointsPerAnswer, 20);
    });

    test('la clé enregistrée en base est le nom de l\'énumération', () {
      for (final l in GameLevel.values) {
        expect(l.key, l.name);
        expect(gameLevelFromKey(l.key), l);
      }
    });

    test('anciennes clés reconnues', () {
      expect(gameLevelFromKey('level1'), GameLevel.level_cycle1);
      expect(gameLevelFromKey('level2'), GameLevel.level_cycle2);
      expect(gameLevelFromKey('level3'), GameLevel.level_cycle3);
      expect(gameLevelFromKey('level4'), GameLevel.level_sec1);
      expect(gameLevelFromKey('level5'), GameLevel.level_sec2);
      expect(gameLevelFromKey('level_expert'), GameLevel.expert);
    });

    test('clé inconnue ou vide', () {
      expect(gameLevelFromKey('zzz'), isNull);
      expect(gameLevelFromKey(null), isNull);
      expect(levelLabelFromKey('zzz'), 'zzz');
    });

    test('libellés', () {
      expect(GameLevel.level_cycle1.label, 'Niveau 1 (Cycle 1)');
      expect(GameLevel.expert.label, 'Niveau Expert');
      expect(levelLabelFromKey('level4'), 'Niveau 4 (Sec 1)');
    });

    test('chaque niveau a ses verbes et la liste ne rétrécit pas', () {
      var previous = 0;
      for (final l in [
        GameLevel.level_cycle1,
        GameLevel.level_cycle2,
        GameLevel.level_cycle3,
        GameLevel.level_sec1,
        GameLevel.level_sec2,
      ]) {
        final n = kLevelVerbs[l]!.length;
        expect(n, greaterThan(0));
        expect(n, greaterThanOrEqualTo(previous));
        previous = n;
      }
    });
  });
}
