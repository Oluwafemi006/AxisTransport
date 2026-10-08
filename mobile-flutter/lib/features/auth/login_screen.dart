import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/session.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _firstName = TextEditingController();
  final _phone = TextEditingController();
  bool _creating = false;
  bool _busy = false;
  String? _message;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _firstName.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_username.text.trim().isEmpty || _password.text.isEmpty) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final session = ref.read(sessionProvider.notifier);
      if (_creating) {
        await session.register(
          username: _username.text.trim(),
          password: _password.text,
          firstName: _firstName.text.trim(),
          phone: _phone.text.trim(),
        );
      } else {
        await session.login(_username.text.trim(), _password.text);
      }
      if (mounted) context.pop();
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
          Text(
            _creating ? 'Créer mon compte' : 'Bienvenue',
            style: const TextStyle(
              color: AxisColors.text,
              fontSize: 30,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Retrouvez vos billets, colis et locations dans votre compte Axis Transport.',
            style: TextStyle(color: AxisColors.muted, height: 1.45),
          ),
          if (_creating) ...[
            const SizedBox(height: 14),
            TextField(
              controller: _firstName,
              decoration: const InputDecoration(labelText: 'Prénom'),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Téléphone'),
            ),
          ],
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
            child: Text(
              _busy
                  ? 'Patientez…'
                  : _creating
                  ? 'Créer et continuer'
                  : 'Se connecter',
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: () => setState(() {
              _creating = !_creating;
              _message = null;
            }),
            child: Text(
              _creating ? 'J’ai déjà un compte' : 'Créer un compte client',
            ),
          ),
        ],
      ),
    );
  }
}
