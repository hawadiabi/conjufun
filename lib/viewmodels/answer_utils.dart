// Outils partagés pour lire et vérifier les réponses des élèves.

const String kNoPronoun = '(aucun pronom)';

/// Apostrophes typographiques (iOS, claviers français) -> apostrophe droite.
String normalizeApostrophes(String s) =>
    s.replaceAll('’', "'").replaceAll('‘', "'").replaceAll('`', "'");

/// Minuscules, apostrophe droite, espaces multiples réduits.
String normalizeAnswerText(String s) => normalizeApostrophes(
  s,
).trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

// Débuts de formes à h aspiré : pas d'élision (« je hais », « je hache »).
// Liste volontairement limitée aux verbes courants.
const List<String> _aspiratedHStarts = [
  'haï',
  'hais',
  'hach',
  'hale',
  'hant',
  'harc',
  'harp',
  'hara',
  'hasa',
  'haus',
  'happ',
  'hât',
  'hâl',
  'heur',
  'henn',
  'héri',
  'hiss',
  'hoch',
  'hurl',
  'hue',
  'huch',
];

const String _vowels = 'aàâäeéèêëiîïoôöuùûüyœæ';

/// « je » devient « j' » devant une voyelle (accentuée ou non) ou un h muet.
/// Les autres pronoms sont renvoyés tels quels.
String contractPronoun(String pronoun, String verbForm) {
  final p = pronoun.trim().toLowerCase();
  if (p != 'je' && p != "j'") return pronoun;

  final t = normalizeApostrophes(verbForm).trim().toLowerCase();
  if (t.isEmpty) return 'je';

  final first = t[0];
  if (_vowels.contains(first)) return "j'";
  if (first == 'h') {
    final aspirated = _aspiratedHStarts.any((s) => t.startsWith(s));
    return aspirated ? 'je' : "j'";
  }
  return 'je';
}

/// Sépare « j'aime » en (« j' », « aime ») et « il mange » en (« il », « mange »).
/// Si la réponse ne contient qu'un mot (sans élision), le pronom est vide.
(String pronoun, String verb) splitPronounAndVerb(String raw) {
  final t = normalizeApostrophes(raw.trim());
  if (t.isEmpty) return ('', '');

  if (t.toLowerCase().startsWith("j'")) {
    return (t.substring(0, 2), t.substring(2).trim());
  }

  final i = t.indexOf(RegExp(r'\s'));
  if (i < 0) return ('', t);
  return (t.substring(0, i), t.substring(i).trim());
}

/// Compare le pronom attendu et celui de l'élève.
/// - [lenientJe] : accepte « je » et « j' » indifféremment (utile quand
///   plusieurs auxiliaires sont possibles et que l'élision change).
/// - [ignoreGender] : il = elle, ils = elles (test de niveau).
bool samePronoun(
  String expected,
  String given, {
  bool lenientJe = false,
  bool ignoreGender = false,
}) {
  String norm(String s) {
    var v = normalizeApostrophes(s).trim().toLowerCase();
    if (v.isEmpty) return kNoPronoun;
    if (lenientJe && (v == "j'" || v == 'je')) return 'je';
    if (ignoreGender) {
      if (v == 'il' || v == 'elle' || v == 'il/elle') return 'il/elle';
      if (v == 'ils' || v == 'elles' || v == 'ils/elles') return 'ils/elles';
    }
    return v;
  }

  return norm(expected) == norm(given);
}

/// Libellé de la personne pour l'en-tête de la question.
String personLabel(String pronoun, {bool genderless = false}) {
  final p = normalizeApostrophes(pronoun).trim().toLowerCase();

  switch (p) {
    case 'je':
    case "j'":
      return '1re personne du singulier';
    case 'tu':
      return '2e personne du singulier';
    case 'il':
      return genderless
          ? '3e personne du singulier'
          : '3e personne du singulier (masculin)';
    case 'elle':
      return genderless
          ? '3e personne du singulier'
          : '3e personne du singulier (féminin)';
    case 'il/elle':
      return '3e personne du singulier';
    case 'nous':
      return '1re personne du pluriel';
    case 'vous':
      return '2e personne du pluriel';
    case 'ils':
      return genderless
          ? '3e personne du pluriel'
          : '3e personne du pluriel (masculin)';
    case 'elles':
      return genderless
          ? '3e personne du pluriel'
          : '3e personne du pluriel (féminin)';
    case 'ils/elles':
      return '3e personne du pluriel';
    case kNoPronoun:
      return 'forme sans pronom';
    default:
      return 'personne non spécifiée';
  }
}
