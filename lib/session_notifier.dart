import 'package:flutter/foundation.dart';

// Notificateurs globaux : les pages gardées en vie par IndexedStack (Accueil,
// Historique, Verbes, Tableau de bord, Paramètres) s'y abonnent pour se
// recharger quand le compte change ou quand de nouvelles données sont
// enregistrées (partie terminée, badge débloqué...).

/// Incrémenté à chaque connexion, inscription, déconnexion, suppression de
/// compte ou changement de profil.
final ValueNotifier<int> authVersion = ValueNotifier<int>(0);

/// Incrémenté quand des données de jeu changent (partie enregistrée, badge...).
final ValueNotifier<int> dataVersion = ValueNotifier<int>(0);

/// Écoute les deux en même temps.
final Listenable appStateChanged = Listenable.merge([authVersion, dataVersion]);

void notifyAuthChanged() => authVersion.value++;
void notifyDataChanged() => dataVersion.value++;
