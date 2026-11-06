import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/session.dart';

/// Contrôle local avant envoi ; le serveur revérifie tout (prénom et téléphone obligatoires, 8 à 15 chiffres).
String? profileFormError({required String firstName, required String phone, required String email}) {
  if (firstName.trim().isEmpty) return 'Le prénom est obligatoire.';
  if (phone.trim().isEmpty) return 'Le numéro de téléphone est obligatoire.';
  final digits = phone.replaceAll(RegExp(r'\D'), '');
  if (!RegExp(r'^\+?[0-9 ().-]+$').hasMatch(phone.trim()) || digits.length < 8 || digits.length > 15) {
    return 'Numéro de téléphone invalide.';
  }
  if (email.trim().isNotEmpty && !email.contains('@')) return 'Veuillez saisir une adresse e-mail valide.';
  return null;
}

/// « Mes informations » : le client corrige son prénom, son nom, son téléphone et son e-mail.
class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  late final TextEditingController _firstName;
  late final TextEditingController _lastName;
  late final TextEditingController _phone;
  late final TextEditingController _email;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final user = ref.read(sessionProvider).user;
    _firstName = TextEditingController(text: user?.firstName ?? '');
    _lastName = TextEditingController(text: user?.lastName ?? '');
    _phone = TextEditingController(text: user?.phone ?? '');
    _email = TextEditingController(text: user?.email ?? '');
  }

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _phone.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final error = profileFormError(firstName: _firstName.text, phone: _phone.text, email: _email.text);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(apiClientProvider).updateProfile({
        'first_name': _firstName.text.trim(),
        'last_name': _lastName.text.trim(),
        'phone': _phone.text.trim(),
        'email': _email.text.trim(),
      });
      await ref.read(sessionProvider.notifier).restore();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Informations enregistrées.')));
      Navigator.of(context).maybePop();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mes informations')),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          TextField(key: const Key('profile-first-name'), controller: _firstName, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Prénom')),
          const SizedBox(height: 12),
          TextField(key: const Key('profile-last-name'), controller: _lastName, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Nom')),
          const SizedBox(height: 12),
          TextField(key: const Key('profile-phone'), controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Téléphone')),
          const SizedBox(height: 12),
          TextField(key: const Key('profile-email'), controller: _email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'E-mail (pour retrouver votre mot de passe)')),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, key: const Key('profile-error'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 20),
          FilledButton(
            key: const Key('profile-save'),
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'Enregistrement…' : 'Enregistrer'),
          ),
        ],
      ),
    );
  }
}
