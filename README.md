# ConjuFun

Application Flutter qui aide à pratiquer la conjugaison française sous forme de jeu. Elle fonctionne hors ligne grâce à une base de données locale SQLite. Une synchronisation avec un serveur est en cours de développement (voir la section « Serveur et synchronisation »).

Projet démarré en équipe dans le cadre du cours INM5151 (Projet d'analyse et de modélisation) à l'UQAM, puis repris et amélioré par Hawa Diabi : correction de bugs, unification des badges et des rangs, mode créateur, mode sombre, interface adaptative et suite de tests automatiques.

## Fonctionnalités

### Jeu
- Exercices générés au hasard à partir du lexique LEFFF, pour 20 temps et modes (présent, imparfait, futur, conditionnel, subjonctif, passé simple, temps composés, impératif, participes, gérondif, infinitifs).
- Six niveaux : Cycle 1, Cycle 2, Cycle 3, Secondaire 1, Secondaire 2 et Expert. Chaque niveau a sa liste de verbes, ses temps et ses points par bonne réponse.
- Deux modes de jeu : illimité (la partie se termine à la première erreur) et fixe (10, 15 ou 25 questions).
- Réponses tolérantes : accents, apostrophes typographiques, « je » et « j' », « il » et « elle », « ils » et « elles », double auxiliaire des verbes comme « rentrer » ou « monter ».
- Explication de la règle après chaque réponse.
- Test de niveau initial qui recommande un niveau de départ.
- Les verbes pronominaux ne sont pas inclus.

### Progression
- Badges (réponses correctes, sessions jouées, séries de jours consécutifs) et six rangs selon le score cumulé, de « Début du parcours » à « Grand Sage de la Langue Française ». Tous les seuils sont définis à un seul endroit : `lib/data/badge_catalog.dart`.
- Les badges et les rangs sont réservés aux comptes. En mode invité, la page des badges invite à ouvrir un compte.
- Historique des parties, records par niveau et par mode (le premier score d'un niveau n'est pas considéré comme un record).
- Tableau de bord et statistiques par niveau et par temps, avec export PDF.
- Retour visuel et sonore (confettis lors d'un record).

### Mode créateur
- Création d'ensembles personnalisés : choix des verbes, des temps, du niveau scolaire et du nombre de questions.
- Modification, suppression, export et import par code de partage (`CFSET1|...`).
- Les ensembles appartiennent au compte connecté (ou à l'invité).

### Comptes
- Jeu sans compte (invité) ou avec compte : inscription, connexion, changement de mot de passe, suppression du compte.
- Les parties jouées en invité sont rattachées au compte à l'inscription ou à la première connexion.
- Les données de chaque compte sont isolées. À la déconnexion, l'historique, les statistiques et les badges affichés sont vidés, et les données d'invité restantes sont supprimées.
- Mots de passe hachés avec PBKDF2-HMAC-SHA256 (60 000 itérations, sel aléatoire). Les anciens hachages sont migrés à la prochaine connexion.
- Après 5 échecs de connexion, la tentative suivante est bloquée pendant une minute.

### Interface
- Mode clair et mode sombre, conservé entre les sessions.
- Mise en page adaptative : barre de navigation en bas sous 800 px de large, rail latéral à partir de 800 px, contenu limité à 1100 px.

## Technologies

| Rôle | Technologie |
|---|---|
| Interface | Flutter 3.35 ou plus récent, Dart 3.9 ou plus récent |
| Base de données locale | SQLite (`sqflite`, `sqflite_common_ffi` pour Windows, Linux et macOS) |
| Préférences et session | `shared_preferences` |
| Hachage des mots de passe | `crypto` (PBKDF2 écrit dans `lib/data/password_hasher.dart`) |
| Graphiques | `fl_chart` |
| Export PDF | `pdf`, `path_provider`, `open_filex` |
| Son et animations | `audioplayers`, `confetti` |
| Réseau (synchronisation) | `http` |

La gestion d'état repose sur `ChangeNotifier` (ViewModel de l'exercice) et sur des `ValueNotifier` (`lib/session_notifier.dart` pour les changements de compte et de données, `lib/theme_notifier.dart` pour le thème).

## Prérequis

- Flutter SDK (vérifier avec `flutter --version`) et un éditeur : VS Code ou Android Studio.
- **Windows** : Visual Studio 2022 avec la charge de travail « Développement Desktop en C++ ».
- **Android** : Android Studio, SDK Android, et un émulateur ou un appareil connecté en USB.
- **Web** : non supporté. La base SQLite locale n'est pas disponible dans le navigateur.

## Installation et exécution

```bash
git clone https://github.com/<ton-compte>/conjufun.git
cd conjufun
flutter pub get
flutter run -d windows   # ou : flutter run -d android
```

## Tests

```bash
flutter analyze
flutter test
```

Plus de 130 tests automatiques couvrent la logique de l'application :

| Fichier | Contenu |
|---|---|
| `answer_utils_test.dart` | Tolérance des réponses (accents, apostrophes, pronoms) |
| `password_hasher_test.dart` | PBKDF2, y compris un vecteur de test officiel (RFC 7914) |
| `auth_repo_test.dart` | Inscription, connexion, blocage, rattachement des parties d'invité, déconnexion |
| `app_db_test.dart` | Isolation invité et compte, records, statistiques, ensembles |
| `app_db_migration_test.dart` | Migration de la base de la version 11 à 12 |
| `exercise_vm_test.dart` | Logique de partie avec les vraies données LEFFF |
| `sync_service_test.dart` | Contrat de synchronisation avec un serveur simulé |
| `share_code_test.dart` | Export et import des codes de partage |
| `levels_config_test.dart` | Configuration des niveaux |
| `widget_test.dart` | Badges et rangs |

Les tests de base de données utilisent un fichier temporaire et ne touchent jamais à la vraie base `conjufun.db`. L'affichage (mode sombre, tailles de fenêtre) a été vérifié à la main, sans test automatique.

## Structure du projet

```text
conjufun/
├─ lib/
│  ├─ main.dart                 Thème, couleurs de la marque, point d'entrée
│  ├─ session_notifier.dart     Notifications de changement de compte ou de données
│  ├─ theme_notifier.dart       Mode clair ou sombre
│  ├─ config/                   Niveaux : nom, points, verbes et temps autorisés
│  ├─ data/                     Base SQLite, authentification, hachage, badges,
│  │                            synchronisation, listes de verbes par niveau
│  ├─ models/                   Modèles (ensemble personnalisé, exercice)
│  ├─ viewmodels/               Logique du jeu et validation des réponses
│  ├─ pages/                    Écrans de l'application
│  ├─ widgets/                  Fenêtre de connexion et d'inscription
│  └─ ui/                       Composants et couleurs partagés
├─ assets/
│  ├─ data/                     Conjugaisons (LEFFF) et règles de grammaire
│  ├─ fonts/                    Polices (export PDF)
│  └─ sounds/                   Effets sonores
├─ test/                        Tests automatiques
├─ android/  ios/  windows/  macos/  linux/
└─ pubspec.yaml
```

## Données locales

- La base `conjufun.db` (SQLite, version 12) contient les utilisateurs, les parties, les statistiques par temps, les badges et les ensembles personnalisés.
- Les parties, statistiques et ensembles ont une colonne `user_id`. Une valeur vide désigne l'invité.
- Les conjugaisons proviennent du LEFFF (Lexique des formes fléchies du français). Vérifier sa licence avant toute redistribution.

## Serveur et synchronisation (en développement)

Le client contient déjà la synchronisation des ensembles du mode créateur (`lib/data/sync_service.dart`). Le serveur correspondant (Flask) n'est pas encore écrit : par défaut, la synchronisation est désactivée (réglage dans les Paramètres, visible seulement connecté) et l'application fonctionne entièrement en local. L'adresse du serveur est actuellement `http://localhost:3000`.

Contrat prévu pour le futur serveur :

```text
POST /sync/custom_sets
Requête  : { "user_id": 1,
             "push": [ { "remote_id", "name", "school_level", "tenses", "verbs",
                         "created_at", "updated_at", "max_questions",
                         "is_deleted", "deleted_at" } ],
             "since": "2026-10-12T20:00:00Z" }        (since est facultatif)
Réponse  : { "server_time": "...", "updated": [ { ...mêmes champs... } ] }
```

En cas de conflit, la version la plus récente (`updated_at`) l'emporte.

Travaux prévus pour le serveur : session sécurisée par jeton, réinitialisation du mot de passe par courriel, identifiants de compte uniques, synchronisation des parties, des statistiques et des badges.

## Limites connues

- Sur Windows, le terminal peut afficher un avertissement du plugin `audioplayers` (message envoyé depuis un thread non plateforme). Il n'affecte pas le fonctionnement de l'application.
- Pas de version web.
- Pas de verbes pronominaux.
- La synchronisation est inactive tant que le serveur n'existe pas.

## Équipe

- Adeoumi Faicoth Adekambi
- Hawa Diabi

## Références

- Documentation Flutter : https://docs.flutter.dev/
- Codelab « Write your first Flutter app » : https://docs.flutter.dev/get-started/codelab
- Cookbook Flutter : https://docs.flutter.dev/cookbook