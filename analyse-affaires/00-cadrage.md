# Fiche de cadrage : analyse d'affaires de ConjuFun

**Analyste :** Hawa Diabi
**Date :** 24 novembre 2026
**Version :** 1.0

## 1. Contexte

ConjuFun est une application mobile Flutter de pratique de la conjugaison française, conçue en équipe (Hawa Diabi et Adeoumi Faicoth Adekambi) dans le cadre du cours INM5151 à l'UQAM, selon la méthode Scrum (3 sprints, livraison `v3.0-sprint3`). L'application a ensuite été poursuivie et terminée par Hawa Diabi.

Le développement s'est appuyé sur des besoins définis par l'équipe elle-même. Aucun utilisateur réel n'a été consulté, et l'application n'a jamais été testée par des personnes extérieures au projet.

## 2. Objectif de l'analyse

Valider, après coup, que ConjuFun répond à de vrais besoins, et produire les livrables d'un analyste d'affaires :

1. recueillir les besoins auprès d'utilisateurs réels ;
2. modéliser le processus actuel et le processus cible (BPMN) ;
3. repérer les gaspillages du processus actuel (lean) ;
4. piloter des tests d'acceptation avec des testeurs externes et formuler une recommandation de mise en production.

## 3. Portée

**Inclus :**
- les fonctions apprenant livrées : exercices (mode fixe et illimité), rétroaction immédiate, test de niveau, tableau de bord, statistiques par niveau et par temps, badges, série de jours, historique des parties, mode créateur avec import et export par code de partage, export PDF des statistiques ;
- les cas d'utilisation CU1 à CU7 du rapport du sprint 3 (CU8, la synchronisation, n'est pas déployé : voir [l'état actuel du produit](00-etat-actuel.md)) ;
- le point de vue de l'enseignant et du parent sur le suivi des progrès.

**Exclus :**
- les fonctions non livrées (groupes d'élèves, statistiques par élève pour l'enseignant, défis entre amis, liste des erreurs fréquentes par verbe, synchronisation en ligne) : elles seront traitées comme des **besoins à valider**, pas comme des fonctions à tester ;
- toute modification du code pendant l'analyse ;
- la participation directe de mineurs (voir section 6).

## 4. Parties prenantes et profils d'utilisateurs

| Profil | Rôle dans l'analyse | Objectif |
|---|---|---|
| Enseignant(e) du primaire ou du secondaire | Entrevue + test | 2 personnes idéalement, au moins 1 |
| Parent d'un enfant d'âge scolaire | Entrevue + test | 1 personne |
| Adulte qui apprend le français (francisation) | Entrevue + test | 1 personne |
| Hawa Diabi | Analyste, animatrice des entrevues et des tests | |

## 5. Hypothèses à valider en entrevue

Ces hypothèses viennent du rapport du sprint 3. Elles n'ont jamais été vérifiées auprès d'utilisateurs.

| # | Hypothèse |
|---|---|
| H1 | La pratique de la conjugaison est répétitive et peu motivante pour les élèves. |
| H2 | La correction des exercices de conjugaison prend un temps important à l'enseignant. |
| H3 | Une rétroaction immédiate aide davantage qu'une correction reçue plus tard. |
| H4 | Les éléments de jeu (points, badges, séries de jours) motivent à pratiquer régulièrement. |
| H5 | Le fonctionnement hors ligne est important (pas de wifi, téléphone de l'enfant sans forfait). |
| H6 | Les enseignants et les parents veulent suivre les progrès et voir les erreurs fréquentes. |
| H7 | Un rapport exportable (PDF) est utile pour le suivi pédagogique. |
| H8 | Le découpage par niveaux scolaires (cycle 1 à secondaire 2) correspond à ce qui est enseigné. |

## 6. Contraintes et considérations éthiques

- Temps disponible : environ 12 à 15 heures par semaine.
- Aucun budget : outils gratuits seulement (draw.io ou Camunda Modeler, Excel, GitHub).
- Les participants sont des adultes. Aucun enfant n'est interviewé ni enregistré ; le point de vue de l'élève est recueilli à travers l'enseignant et le parent.
- Consentement verbal au début de chaque entrevue. Les notes sont anonymisées (P1, P2, P3...) avant d'être publiées sur GitHub.
- Pas d'enregistrement audio sans accord explicite.

## 7. Livrables et échéancier

| Étape | Livrable | Dossier | Échéance |
|---|---|---|---|
| 0 | Fiche de cadrage, recrutement | `/` | 25 nov. |
| 1 | Guide d'entrevue, notes, synthèse des besoins | `01-besoins/` | 28 nov. |
| 2 | BPMN actuel et cible | `02-processus/` | 30 nov. |
| 3 | Tableau des gaspillages | `03-lean/` | 1er déc. |
| 4 | Plan de tests, grille de résultats, bilan de pilotage | `04-tests/` | 6 déc. |
| 5 | Dossier final (PDF) | `/` | 7 déc. |

## 8. Critères de réussite

- Au moins 3 entrevues réalisées, avec au moins un enseignant.
- Chaque hypothèse H1 à H8 est confirmée, nuancée ou infirmée, avec des citations anonymes à l'appui.
- Au moins 3 testeurs externes ont exécuté le plan de tests.
- Le bilan se termine par une recommandation claire et justifiée : prêt à déployer, prêt avec réserves, ou non prêt.
