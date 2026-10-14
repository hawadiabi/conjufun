import 'package:flutter_test/flutter_test.dart';
import 'package:conjufun/viewmodels/answer_utils.dart';

void main() {
  group('normalisation', () {
    test('apostrophes typographiques remplacées par l\'apostrophe droite', () {
      expect(normalizeApostrophes('j’aime'), "j'aime");
      expect(normalizeApostrophes('l‘eau'), "l'eau");
    });

    test('minuscules, espaces réduits', () {
      expect(normalizeAnswerText('  Il   MANGE '), 'il mange');
    });
  });

  group('contractPronoun', () {
    test('« je » devient « j\' » devant une voyelle', () {
      expect(contractPronoun('je', 'aime'), "j'");
      expect(contractPronoun('je', 'été'), "j'");
      expect(contractPronoun('je', 'Aime'), "j'");
    });

    test('« je » reste « je » devant une consonne', () {
      expect(contractPronoun('je', 'mange'), 'je');
    });

    test('h muet : élision', () {
      expect(contractPronoun('je', 'habite'), "j'");
    });

    test('h aspiré : pas d\'élision', () {
      expect(contractPronoun('je', 'hais'), 'je');
      expect(contractPronoun('je', 'hache'), 'je');
    });

    test('forme vide ou autre pronom', () {
      expect(contractPronoun('je', ''), 'je');
      expect(contractPronoun('tu', 'aimes'), 'tu');
    });
  });

  group('splitPronounAndVerb', () {
    test('élision', () {
      expect(splitPronounAndVerb("j'aime"), ("j'", 'aime'));
      expect(splitPronounAndVerb('J’aime'), ("J'", 'aime'));
    });

    test('pronom et verbe séparés par des espaces', () {
      expect(splitPronounAndVerb('il mange'), ('il', 'mange'));
      expect(splitPronounAndVerb('nous  mangeons'), ('nous', 'mangeons'));
    });

    test('un seul mot : pas de pronom', () {
      expect(splitPronounAndVerb('manger'), ('', 'manger'));
    });

    test('texte vide', () {
      expect(splitPronounAndVerb(''), ('', ''));
    });
  });

  group('samePronoun', () {
    test('identique, sans tenir compte de la casse', () {
      expect(samePronoun('tu', 'Tu'), isTrue);
      expect(samePronoun("j'", 'j’'), isTrue);
    });

    test('« je » et « j\' » sont différents par défaut', () {
      expect(samePronoun('je', "j'"), isFalse);
    });

    test('lenientJe accepte les deux', () {
      expect(samePronoun('je', "j'", lenientJe: true), isTrue);
    });

    test('il et elle sont différents par défaut', () {
      expect(samePronoun('il', 'elle'), isFalse);
      expect(samePronoun('ils', 'elles'), isFalse);
    });

    test('ignoreGender accepte il/elle et ils/elles', () {
      expect(samePronoun('il', 'elle', ignoreGender: true), isTrue);
      expect(samePronoun('ils', 'elles', ignoreGender: true), isTrue);
      expect(samePronoun('il', 'ils', ignoreGender: true), isFalse);
    });

    test('pronom vide = forme sans pronom', () {
      expect(samePronoun('', kNoPronoun), isTrue);
      expect(samePronoun('tu', ''), isFalse);
    });
  });

  group('personLabel', () {
    test('personnes simples', () {
      expect(personLabel('je'), '1re personne du singulier');
      expect(personLabel("j'"), '1re personne du singulier');
      expect(personLabel('tu'), '2e personne du singulier');
      expect(personLabel('nous'), '1re personne du pluriel');
      expect(personLabel('vous'), '2e personne du pluriel');
    });

    test('genre précisé ou non', () {
      expect(personLabel('il'), '3e personne du singulier (masculin)');
      expect(personLabel('elle'), '3e personne du singulier (féminin)');
      expect(personLabel('ils', genderless: true), '3e personne du pluriel');
    });

    test('cas particuliers', () {
      expect(personLabel(kNoPronoun), 'forme sans pronom');
      expect(personLabel('xyz'), 'personne non spécifiée');
    });
  });
}
