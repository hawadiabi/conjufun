import 'package:flutter_test/flutter_test.dart';
import 'package:conjufun/models/custom_set.dart';

void main() {
  group('Code de partage CFSET1', () {
    test('export puis import redonne le même contenu', () {
      final original = CustomSet.newLocal(
        name: 'Mon ensemble',
        schoolLevel: 'level_cycle2',
        tenses: ['Présent', 'Imparfait'],
        verbs: ['manger', 'finir', 'aller'],
        maxQuestions: 15,
      );
      final copy = CustomSet.fromShareCode(original.exportCode());

      expect(copy, isNotNull);
      expect(copy!.name, 'Mon ensemble');
      expect(copy.schoolLevel, 'level_cycle2');
      expect(copy.tenses, ['Présent', 'Imparfait']);
      expect(copy.verbs, ['manger', 'finir', 'aller']);
      expect(copy.maxQuestions, 15);
    });

    test('l\'ensemble importé est neuf : pas de remoteId, à synchroniser', () {
      final copy = CustomSet.fromShareCode(
        CustomSet.newLocal(
          name: 'A',
          tenses: ['Présent'],
          verbs: ['aimer'],
        ).exportCode(),
      );
      expect(copy!.remoteId, isNull);
      expect(copy.needsSync, isTrue);
    });

    test('sans nombre de questions ni niveau', () {
      final copy = CustomSet.fromShareCode(
        CustomSet.newLocal(
          name: 'B',
          tenses: ['Futur'],
          verbs: ['aimer'],
        ).exportCode(),
      );
      expect(copy!.maxQuestions, isNull);
      expect(copy.schoolLevel, isNull);
    });

    test('le caractère | dans le nom est remplacé à l\'export', () {
      final code = CustomSet.newLocal(
        name: 'a|b',
        tenses: ['Présent'],
        verbs: ['aimer'],
      ).exportCode();
      final copy = CustomSet.fromShareCode(code);
      expect(copy, isNotNull);
      expect(copy!.name, 'a b');
    });

    test('codes invalides', () {
      expect(CustomSet.fromShareCode(''), isNull);
      expect(CustomSet.fromShareCode('abc'), isNull);
      expect(CustomSet.fromShareCode('CFSET2|a|b|c|d|1|'), isNull);
      expect(CustomSet.fromShareCode('CFSET1|trop|court'), isNull);
    });
  });

  group('Persistance locale', () {
    test('toMap puis fromMap', () {
      final s = CustomSet.newLocal(
        name: 'C',
        schoolLevel: 'expert',
        tenses: ['Présent', 'Futur'],
        verbs: ['aimer', 'finir'],
        maxQuestions: 10,
      );
      final back = CustomSet.fromMap(s.toMap());
      expect(back.name, 'C');
      expect(back.tenses, ['Présent', 'Futur']);
      expect(back.verbs, ['aimer', 'finir']);
      expect(back.maxQuestions, 10);
      expect(back.needsSync, isTrue);
      expect(back.isDeleted, isFalse);
    });
  });
}
