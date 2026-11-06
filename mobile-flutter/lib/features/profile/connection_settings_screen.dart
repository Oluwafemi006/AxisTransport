import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_lock.dart';
import '../../shared/contact_actions.dart';

/// Paramètres de connexion : déverrouillage par biométrie, désactivé par défaut.
class ConnectionSettingsScreen extends ConsumerStatefulWidget {
  const ConnectionSettingsScreen({super.key});

  @override
  ConsumerState<ConnectionSettingsScreen> createState() => _ConnectionSettingsScreenState();
}

class _ConnectionSettingsScreenState extends ConsumerState<ConnectionSettingsScreen> {
  String? _message;
  bool _busy = false;

  Future<void> _toggle(bool on) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    final lock = ref.read(appLockProvider.notifier);
    String? error;
    if (on) {
      error = await lock.enable();
    } else {
      await lock.disable();
    }
    if (mounted) {
      setState(() {
        _busy = false;
        _message = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = ref.watch(appLockProvider).enabled;
    return Scaffold(
      appBar: AppBar(title: const Text('Paramètres de connexion')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SwitchListTile(
            key: const Key('biometric-switch'),
            title: const Text('Déverrouiller l’application avec l’empreinte ou la biométrie'),
            subtitle: Text(
              'Après ${appLockDelay.inMinutes} minutes en arrière-plan, l’application demande votre empreinte. '
              'Le mot de passe reste nécessaire pour se connecter ; il n’est jamais enregistré sur le téléphone.',
            ),
            value: enabled,
            onChanged: _busy ? null : _toggle,
          ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                _message!,
                key: const Key('biometric-message'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
    );
  }
}

/// Aide et suggestions : les coordonnées saisies dans /admin (aucun numéro écrit dans le code).
class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Aide et suggestions')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          Text('Une question ou une suggestion ? Contactez l’agence :'),
          SizedBox(height: 12),
          ContactActions(),
        ],
      ),
    );
  }
}
