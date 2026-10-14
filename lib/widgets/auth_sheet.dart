import 'package:flutter/material.dart';

import '../data/auth_repo.dart';
import '../main.dart' show brandBlue;

enum AuthSheetMode { login, signup }

// --- Ouvre la fenêtre de connexion ---
Future<bool?> showLoginSheet(BuildContext context) {
  return showAuthSheet(context);
}

// --- Ouvre la fenêtre d'inscription ---
Future<bool?> showSignupSheet(BuildContext context) {
  return showAuthSheet(context, mode: AuthSheetMode.signup);
}

// --- Fenêtre centrale ---
Future<bool?> showAuthSheet(
  BuildContext context, {
  AuthSheetMode mode = AuthSheetMode.login,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: SingleChildScrollView(child: _AuthSheetBody(initialMode: mode)),
      ),
    ),
  );
}

class _AuthSheetBody extends StatefulWidget {
  const _AuthSheetBody({required this.initialMode});
  final AuthSheetMode initialMode;

  @override
  State<_AuthSheetBody> createState() => _AuthSheetBodyState();
}

class _AuthSheetBodyState extends State<_AuthSheetBody> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  final _formKey = GlobalKey<FormState>();
  bool _loading = false;
  bool _showPassword = false;
  String? _error;
  late AuthSheetMode _mode;

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_loading) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // Le mot de passe n'est jamais modifié (pas de trim).
      if (_mode == AuthSheetMode.login) {
        await AuthRepo.instance.signIn(_emailCtrl.text, _passCtrl.text);
      } else {
        await AuthRepo.instance.signUp(
          _emailCtrl.text,
          _passCtrl.text,
          displayName: _nameCtrl.text,
        );
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Une erreur est survenue. Réessaie.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLogin = _mode == AuthSheetMode.login;

    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            isLogin ? 'Se connecter' : 'Créer un compte',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
          ),
          const SizedBox(height: 20),

          if (!isLogin) ...[
            TextFormField(
              controller: _nameCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(hintText: 'Nom ou pseudo'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Requis' : null,
            ),
            const SizedBox(height: 10),
          ],
          TextFormField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            decoration: const InputDecoration(hintText: 'Courriel'),
            validator: (v) => AuthRepo.validateEmail(v ?? ''),
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: _passCtrl,
            obscureText: !_showPassword,
            decoration: InputDecoration(
              hintText: 'Mot de passe',
              helperMaxLines: 3,
              errorMaxLines: 3,
              helperText: isLogin
                  ? null
                  : '8 caractères minimum, avec une lettre et un chiffre',
              suffixIcon: IconButton(
                icon: Icon(
                  _showPassword ? Icons.visibility_off : Icons.visibility,
                ),
                onPressed: () => setState(() => _showPassword = !_showPassword),
              ),
            ),
            validator: (v) {
              if (v == null || v.isEmpty) return 'Requis';
              return isLogin ? null : AuthRepo.validatePassword(v);
            },
          ),
          if (!isLogin) ...[
            const SizedBox(height: 10),
            TextFormField(
              controller: _confirmCtrl,
              obscureText: !_showPassword,
              decoration: const InputDecoration(
                hintText: 'Confirmer le mot de passe',
              ),
              validator: (v) => v != _passCtrl.text
                  ? 'Les mots de passe sont différents'
                  : null,
            ),
          ],

          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],

          const SizedBox(height: 20),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _loading ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: brandBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                textStyle: const TextStyle(fontWeight: FontWeight.w700),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Text(
                _loading ? 'Patiente...' : (isLogin ? 'Se connecter' : 'Créer'),
              ),
            ),
          ),

          const SizedBox(height: 18),

          Wrap(
            alignment: WrapAlignment.center,
            spacing: 6,
            children: [
              Text(
                isLogin ? 'Tu n’as pas de compte ?' : 'Tu as déjà un compte ?',
              ),
              GestureDetector(
                onTap: _loading
                    ? null
                    : () => setState(() {
                        _mode = isLogin
                            ? AuthSheetMode.signup
                            : AuthSheetMode.login;
                        _error = null;
                      }),
                child: Text(
                  isLogin ? 'Inscris-toi' : 'Connecte-toi',
                  style: const TextStyle(
                    color: brandBlue,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          TextButton(
            onPressed: _loading ? null : () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
        ],
      ),
    );
  }
}
