import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/session.dart';

/// Mot de passe provisoire saisi par un administrateur : il faut en choisir un nouveau avant d'accéder au reste
/// (le serveur refuse aussi toute autre demande tant que ce n'est pas fait).
class ForcedPasswordScreen extends ConsumerStatefulWidget {
  const ForcedPasswordScreen({super.key});

  @override
  ConsumerState<ForcedPasswordScreen> createState() => _ForcedPasswordScreenState();
}

class _ForcedPasswordScreenState extends ConsumerState<ForcedPasswordScreen> {
  final _current = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    if (_current.text.isEmpty || _password.text.isEmpty) {
      setState(() => _error = 'Renseignez le mot de passe provisoire et le nouveau.');
      return;
    }
    if (_password.text != _confirm.text) {
      setState(() => _error = 'Les deux mots de passe ne correspondent pas.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(apiClientProvider).changePassword(currentPassword: _current.text, newPassword: _password.text);
      // Compte relu : l'obligation est levée et le routeur ouvre les écrans habituels.
      await ref.read(sessionProvider.notifier).restore();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Choisissez votre mot de passe'), automaticallyImplyLeading: false),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const Text('Votre mot de passe actuel est provisoire : remplacez-le pour continuer.'),
          const SizedBox(height: 16),
          TextField(key: const Key('forced-current'), controller: _current, obscureText: true, decoration: const InputDecoration(labelText: 'Mot de passe provisoire')),
          const SizedBox(height: 12),
          TextField(key: const Key('forced-new'), controller: _password, obscureText: true, decoration: const InputDecoration(labelText: 'Nouveau mot de passe')),
          const SizedBox(height: 12),
          TextField(key: const Key('forced-confirm'), controller: _confirm, obscureText: true, decoration: const InputDecoration(labelText: 'Confirmer le mot de passe')),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, key: const Key('forced-error'), style: TextStyle(color: theme.colorScheme.error)),
          ],
          const SizedBox(height: 20),
          FilledButton(
            key: const Key('forced-save'),
            onPressed: _busy ? null : _save,
            child: Text(_busy ? 'Enregistrement…' : 'Enregistrer et continuer'),
          ),
          TextButton(
            onPressed: () => ref.read(sessionProvider.notifier).logout(),
            child: const Text('Déconnexion'),
          ),
        ],
      ),
    );
  }
}
