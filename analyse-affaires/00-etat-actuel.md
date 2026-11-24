# État actuel du produit

**Date :** 24 novembre 2026
**Version analysée :** dépôt `github.com/hawadiabi/conjufun`, commit `30a120e` (« ConjuFun: version finale »)
**Document de comparaison :** rapport du sprint 3, INM5151, 12 décembre 2025 (tag `v3.0-sprint3`)

Ce document compare ce que décrit le rapport du sprint 3 avec ce que contient réellement l'application aujourd'hui. Le rapport n'a pas été modifié : il reste le livrable d'équipe tel qu'il a été remis.

## 1. Cas d'utilisation du sprint 3

| CU | Description | Rapport du sprint 3 | État actuel |
|---|---|---|---|
| CU1 | Jouer le test de niveau | Implanté | Implanté |
| CU2 | Consulter le tableau de bord enrichi | Implanté | Implanté, avec mode sombre et carte de série animée |
| CU3 | Consulter ses statistiques par mode et par temps | Implanté | Implanté, avec graphiques, meilleur et plus faible niveau, meilleur et plus faible temps |
| CU4 | Créer un exercice (mode créateur) | Implanté | Implanté |
| CU5 | Importer un exercice | Implanté, mais aussi listé au plan du sprint suivant | Implanté hors ligne par code de partage, couvert par des tests |
| CU6 | Exporter un exercice | Implanté, mais aussi listé au plan du sprint suivant | Implanté hors ligne par code de partage, couvert par des tests |
| CU7 | Exporter ses statistiques | Implanté (« CSV ou PDF » en section 2.1) | Export PDF seulement |
| CU8 | Synchroniser ses données | Déclaré complété | Partiel : voir section 3 |

## 2. Fonctions décrites dans le rapport mais non livrées

| Fonction | Ce que dit le rapport | État actuel |
|---|---|---|
| Groupes d'élèves (enseignant) | Section 2.1 et plan du sprint suivant | Non développé |
| Statistiques par groupe ou par élève (enseignant) | Section 2.1 et plan du sprint suivant | Non développé |
| Défis entre amis | Section 2.1 et plan du sprint suivant | Non développé |
| Erreurs fréquentes et révision ciblée | Décrites comme existantes en 2.1, mais aussi au plan du sprint suivant | Partiel : les bonnes et mauvaises réponses sont comptées **par temps**, pas par verbe. Il n'existe ni liste des verbes ratés ni exercice de révision ciblée. |
| Export CSV | Section 2.1 | Non développé |

Ces fonctions sont traitées dans l'analyse comme des **besoins à valider** en entrevue.

## 3. Synchronisation

- Un serveur Node.js/Express (`conjufun-sync-api/server.js`) existe dans le dépôt.
- Il ne synchronise que les ensembles d'exercices personnalisés, pas les scores, badges ou statistiques.
- Les données sont gardées en mémoire : elles sont perdues à chaque redémarrage du serveur.
- L'application pointe vers `http://localhost:3000`. Rien n'est déployé en ligne.
- Le contrat client est couvert par `sync_service_test.dart` (serveur simulé).

**Conclusion :** la synchronisation fonctionne en développement local seulement. Pour un utilisateur réel, l'application est **100 % hors ligne**.

## 4. Ajouts réalisés après le rapport

- Correction de 10 bogues, dont la migration de la table des statistiques (version 11 à 12), la logique des séries de jours, l'affichage de la série toujours à 0 et le faux remplissage des temps composés.
- Unification des badges et des rangs.
- Mode sombre, carte de série animée et interface adaptative.
- Suite de plus de 130 tests automatiques (`flutter test`) : tolérance des réponses, hachage PBKDF2, authentification, base de données et migration, logique de partie, synchronisation, codes de partage.
- README complet, projet publié sur GitHub.

## 5. Points connus à valider avec les utilisateurs

| Point | Constat | Lien avec la fiche de cadrage |
|---|---|---|
| Verbes du cycle 3 | Contient des verbes rares pour des élèves de 8 à 10 ans (vaincre, résoudre, nuire) | Hypothèse H8 |
| Secondaire 1 et 2 | 18 verbes en commun (admettre, atteindre, boire, craindre, résoudre, etc.) : révision voulue ou doublon ? | Hypothèse H8 |
| Plateforme | Le rapport indique que la version PC a été priorisée et que l'optimisation mobile n'était pas terminée. Le README documente Windows et Android. | À confirmer avant l'étape 4 (tests sur téléphone) |
