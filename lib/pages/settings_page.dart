import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/auth_repo.dart';
import '../data/sync_service.dart';
import '../ui/app_colors.dart';
import '../main.dart' show brandBlue, brandYellow;
import '../session_notifier.dart';
import '../theme_notifier.dart';
import '../widgets/auth_sheet.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _syncEnabled = true;
  bool _darkModeEnabled = false;
  String? _displayName;
  String? _email;
  bool _isLoggedIn = false;

  bool _loading = true;
  bool _syncInProgress = false;

  @override
  void initState() {
    super.initState();
    // La page est gardée en vie par l'IndexedStack : on se recharge quand le
    // compte change (connexion, déconnexion, suppression).
    authVersion.addListener(_loadPrefsAndUser);
    _loadPrefsAndUser();
  }

  @override
  void dispose() {
    authVersion.removeListener(_loadPrefsAndUser);
    super.dispose();
  }

  Future<void> _loadPrefsAndUser() async {
    final prefs = await SharedPreferences.getInstance();
    // getCurrentUser() nettoie la session si le compte n'existe plus.
    final user = await AuthRepo.instance.getCurrentUser();

    if (!mounted) return;
    setState(() {
      _syncEnabled = prefs.getBool('sync_enabled') ?? false;
      _darkModeEnabled = prefs.getBool('dark_mode_enabled') ?? false;
      _isLoggedIn = user != null;
      _displayName = user == null ? null : user['display_name'] as String?;
      _email = user == null ? null : user['email'] as String?;
      _loading = false;
    });
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _onSyncChanged(bool value) async {
    setState(() => _syncEnabled = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('sync_enabled', value);
  }

  Future<void> _onDarkModeChanged(bool value) async {
    setState(() => _darkModeEnabled = value);
    themeModeNotifier.value = value ? ThemeMode.dark : ThemeMode.light;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('dark_mode_enabled', value);
  }

  Future<void> _onManualSync() async {
    if (!_isLoggedIn) {
      _snack('Connecte-toi pour synchroniser tes données.');
      return;
    }
    if (!_syncEnabled) {
      _snack('Active d’abord la synchronisation en ligne.');
      return;
    }

    setState(() => _syncInProgress = true);
    try {
      await SyncService.instance.syncCustomSetsIfEnabled();
      _snack('Synchronisation terminée (si le serveur est joignable).');
    } catch (_) {
      _snack('La synchronisation a échoué. Réessaie plus tard.');
    } finally {
      if (mounted) setState(() => _syncInProgress = false);
    }
  }

  // ---------------------------------------------------------------------
  // Compte
  // ---------------------------------------------------------------------

  Future<void> _onLogin() async {
    await showAuthSheet(context);
    // authVersion se charge de recharger la page.
  }

  Future<void> _onLogout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Se déconnecter ?'),
        content: const Text(
          'Tes données restent sauvegardées sur ton compte. '
          'Tu pourras les retrouver en te reconnectant.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Se déconnecter'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await AuthRepo.instance.signOut();
  }

  Future<void> _onChangePassword() async {
    final currentCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    String? error;
    bool busy = false;

    final done = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Changer le mot de passe'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: currentCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Mot de passe actuel',
                    ),
                    validator: (v) =>
                        (v == null || v.isEmpty) ? 'Requis' : null,
                  ),
                  TextFormField(
                    controller: newCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Nouveau mot de passe',
                      helperText:
                          '8 caractères minimum, une lettre et un chiffre',
                      helperMaxLines: 2,
                    ),
                    validator: (v) => AuthRepo.validatePassword(v ?? ''),
                  ),
                  TextFormField(
                    controller: confirmCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Confirmer le nouveau mot de passe',
                    ),
                    validator: (v) => v != newCtrl.text
                        ? 'Les mots de passe sont différents'
                        : null,
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 10),
                    Text(error!, style: const TextStyle(color: Colors.red)),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(ctx, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) return;
                      setLocal(() {
                        busy = true;
                        error = null;
                      });
                      try {
                        await AuthRepo.instance.changePassword(
                          currentPassword: currentCtrl.text,
                          newPassword: newCtrl.text,
                        );
                        if (ctx.mounted) Navigator.pop(ctx, true);
                      } on AuthException catch (e) {
                        setLocal(() {
                          busy = false;
                          error = e.message;
                        });
                      } catch (_) {
                        setLocal(() {
                          busy = false;
                          error = 'Une erreur est survenue. Réessaie.';
                        });
                      }
                    },
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );

    currentCtrl.dispose();
    newCtrl.dispose();
    confirmCtrl.dispose();

    if (done == true) _snack('Mot de passe modifié.');
  }

  Future<void> _onDeleteAccount() async {
    final passCtrl = TextEditingController();
    String? error;
    bool busy = false;

    final deleted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Supprimer mon compte'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Cette action est définitive. Ton compte, tes parties, '
                  'tes statistiques et tes badges seront supprimés de cet appareil.',
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: passCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Mot de passe pour confirmer',
                  ),
                ),
                if (error != null) ...[
                  const SizedBox(height: 10),
                  Text(error!, style: const TextStyle(color: Colors.red)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(ctx, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: busy
                  ? null
                  : () async {
                      if (passCtrl.text.isEmpty) {
                        setLocal(() => error = 'Entre ton mot de passe.');
                        return;
                      }
                      setLocal(() {
                        busy = true;
                        error = null;
                      });
                      try {
                        await AuthRepo.instance.deleteAccount(passCtrl.text);
                        if (ctx.mounted) Navigator.pop(ctx, true);
                      } on AuthException catch (e) {
                        setLocal(() {
                          busy = false;
                          error = e.message;
                        });
                      } catch (_) {
                        setLocal(() {
                          busy = false;
                          error = 'Une erreur est survenue. Réessaie.';
                        });
                      }
                    },
              child: const Text('Supprimer'),
            ),
          ],
        ),
      ),
    );

    passCtrl.dispose();

    if (deleted == true) _snack('Compte supprimé.');
  }

  // ---------------------------------------------------------------------
  // Interface
  // ---------------------------------------------------------------------

  Widget _buildAccountCard() {
    final name = _isLoggedIn
        ? ((_displayName?.isNotEmpty ?? false) ? _displayName! : 'Utilisateur')
        : 'Invité';

    return Card(
      elevation: 0,
      color: brandBlue.withValues(alpha: 0.05),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: brandYellow.withValues(alpha: 0.8),
                  child: Text(
                    name.substring(0, 1).toUpperCase(),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                      color: Colors.black,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        _isLoggedIn
                            ? (_email ?? '')
                            : 'Tes parties sont gardées sur cet appareil.',
                        style: TextStyle(
                          fontSize: 14,
                          color: context.mutedText,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (!_isLoggedIn)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _onLogin,
                  icon: const Icon(Icons.login),
                  label: const Text('Se connecter ou créer un compte'),
                ),
              )
            else
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _onChangePassword,
                    icon: const Icon(Icons.lock_reset),
                    label: const Text('Mot de passe'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _onLogout,
                    icon: const Icon(Icons.logout),
                    label: const Text('Déconnexion'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Paramètres'),
        backgroundColor: brandBlue,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildAccountCard(),
          const SizedBox(height: 24),

          if (_isLoggedIn) ...[
            SwitchListTile(
              value: _syncEnabled,
              onChanged: _onSyncChanged,
              title: const Text(
                'Synchronisation en ligne',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: const Text(
                'Autoriser la sauvegarde / récupération de tes ensembles personnalisés.',
              ),
              activeThumbColor: brandYellow,
            ),
            const Divider(height: 32),
          ],

          SwitchListTile(
            value: _darkModeEnabled,
            onChanged: _onDarkModeChanged,
            title: const Text(
              'Mode sombre',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: const Text(
              'Bascule le thème sombre sur toute l’application.',
            ),
            activeThumbColor: brandYellow,
          ),

          if (_isLoggedIn) ...[
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _syncInProgress ? null : _onManualSync,
              icon: _syncInProgress
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync),
              label: const Text(
                'Synchroniser maintenant',
                style: TextStyle(fontSize: 16),
              ),
            ),
            const SizedBox(height: 32),
            const Divider(),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _onDeleteAccount,
              icon: const Icon(Icons.delete_forever),
              label: const Text('Supprimer mon compte'),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
            ),
          ],

          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
