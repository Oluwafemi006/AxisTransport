import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/session.dart';

/// Ce qui est supprimé et ce qui est conservé : même règle que le serveur (account_deletion.py).
const deletedItems = [
  'Votre prénom, votre nom, votre téléphone, votre e-mail et votre identifiant',
  'Votre mot de passe : vous ne pourrez plus vous connecter',
  'Les noms et téléphones inscrits sur vos billets, réservations et colis',
];
const keptItems = [
  'Vos billets, colis, locations et paiements passés, sans nom ni coordonnées, pour la comptabilité de l’agence',
];

/// « Supprimer mon compte » (client) : confirmation par le mot de passe, refus si un voyage payé n'est pas encore parti.
class DeleteAccountScreen extends ConsumerStatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  ConsumerState<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends ConsumerState<DeleteAccountScreen> {
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    if (_busy) return;
    if (_password.text.isEmpty) {
      setState(() => _error = 'Saisissez votre mot de passe pour confirmer.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(sessionProvider.notifier).deleteAccount(_password.text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Votre compte a été supprimé.')));
      context.go('/');
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString().replaceFirst('Exception: ', '');
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget list(List<String> items) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [for (final item in items) Padding(padding: const EdgeInsets.only(top: 6), child: Text('• $item'))],
        );
    return Scaffold(
      appBar: AppBar(title: const Text('Supprimer mon compte')),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Text('Ce qui est supprimé', style: theme.textTheme.titleMedium),
          list(deletedItems),
          const SizedBox(height: 16),
          Text('Ce qui est conservé', style: theme.textTheme.titleMedium),
          list(keptItems),
          const SizedBox(height: 16),
          const Text('Si vous avez un billet payé pour un voyage qui n’est pas encore parti, la suppression sera possible après ce voyage. Cette action est définitive.'),
          const SizedBox(height: 20),
          TextField(
            key: const Key('delete-password'),
            controller: _password,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Mot de passe actuel'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, key: const Key('delete-error'), style: TextStyle(color: theme.colorScheme.error)),
          ],
          const SizedBox(height: 20),
          FilledButton(
            key: const Key('delete-confirm'),
            style: FilledButton.styleFrom(backgroundColor: theme.colorScheme.error, foregroundColor: theme.colorScheme.onError),
            onPressed: _busy ? null : _delete,
            child: Text(_busy ? 'Suppression…' : 'Supprimer définitivement mon compte'),
          ),
        ],
      ),
    );
  }
}
