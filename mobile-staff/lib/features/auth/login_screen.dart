import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/session.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';

/// Connexion du personnel. Les comptes sont créés par l'administrateur : pas d'inscription ici.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _message;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_username.text.trim().isEmpty || _password.text.isEmpty) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      // Une fois le personnel connecté, l'application remplace cet écran par l'accueil.
      await ref
          .read(sessionProvider.notifier)
          .login(_username.text.trim(), _password.text);
    } catch (error) {
      if (mounted) setState(() => _message = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Connexion')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(22, 12, 22, 40),
        children: [
          const Align(alignment: Alignment.centerLeft, child: Brand()),
          const SizedBox(height: 26),
          const Text(
            'Espace équipe',
            style: TextStyle(
              color: AxisColors.text,
              fontSize: 30,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Saisissez vos identifiants Axis.',
            style: TextStyle(color: AxisColors.muted, height: 1.45),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _username,
            autocorrect: false,
            textCapitalization: TextCapitalization.none,
            decoration: const InputDecoration(labelText: 'Identifiant'),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _password,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Mot de passe'),
          ),
          if (_message != null) Notice(_message!, error: true),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: Text(_busy ? 'Patientez…' : 'Se connecter'),
          ),
        ],
      ),
    );
  }
}
