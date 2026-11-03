import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/session.dart';
import '../../core/theme/axis_spacing.dart';
import '../../core/theme/axis_tokens.dart';
import '../../core/widgets/axis_button.dart';
import '../../core/widgets/axis_text_field.dart';

/// Mon compte : e-mail (clients, pour le mot de passe oublié) et changement de mot de passe.
class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  late final TextEditingController _email;
  final _current = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  bool _savingEmail = false;
  bool _savingPassword = false;
  String? _emailMessage;
  String? _emailError;
  String? _passwordMessage;
  String? _passwordError;

  @override
  void initState() {
    super.initState();
    _email = TextEditingController(text: ref.read(sessionProvider).user?.email ?? '');
  }

  @override
  void dispose() {
    _email.dispose();
    _current.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  String _clean(Object error) => error.toString().replaceFirst('Exception: ', '');

  Future<void> _saveEmail() async {
    final email = _email.text.trim();
    if (email.isNotEmpty && !email.contains('@')) {
      setState(() => _emailError = 'Veuillez saisir une adresse e-mail valide.');
      return;
    }
    setState(() {
      _savingEmail = true;
      _emailError = null;
      _emailMessage = null;
    });
    try {
      await ref.read(apiClientProvider).updateEmail(email);
      await ref.read(sessionProvider.notifier).restore();
      if (mounted) setState(() => _emailMessage = 'E-mail enregistré.');
    } catch (error) {
      if (mounted) setState(() => _emailError = _clean(error));
    } finally {
      if (mounted) setState(() => _savingEmail = false);
    }
  }

  Future<void> _savePassword() async {
    if (_current.text.isEmpty || _password.text.isEmpty) {
      setState(() => _passwordError = 'Renseignez le mot de passe actuel et le nouveau.');
      return;
    }
    if (_password.text != _confirm.text) {
      setState(() => _passwordError = 'Les deux mots de passe ne correspondent pas.');
      return;
    }
    setState(() {
      _savingPassword = true;
      _passwordError = null;
      _passwordMessage = null;
    });
    try {
      await ref.read(apiClientProvider).changePassword(
            currentPassword: _current.text,
            newPassword: _password.text,
          );
      _current.clear();
      _password.clear();
      _confirm.clear();
      if (mounted) {
        setState(() => _passwordMessage =
            'Mot de passe modifié. Vos autres appareils sont déconnectés.');
      }
    } catch (error) {
      if (mounted) setState(() => _passwordError = _clean(error));
    } finally {
      if (mounted) setState(() => _savingPassword = false);
    }
  }

  Widget _feedback(String? message, String? error) {
    final text = error ?? message;
    if (text == null) return const SizedBox.shrink();
    final tokens = context.axis;
    return Padding(
      padding: const EdgeInsets.only(top: AxisSpacing.sm),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: error != null ? tokens.danger : tokens.success,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.axis;
    final isClient = ref.watch(sessionProvider).user?.isClient ?? false;
    final title = theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: tokens.ink);

    return Scaffold(
      appBar: AppBar(title: Text(isClient ? 'Mon compte' : 'Mot de passe')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AxisSpacing.screen),
          children: [
            if (isClient) ...[
              Text('E-mail', style: title),
              const SizedBox(height: 4),
              Text(
                'Il sert à recevoir un code si vous oubliez votre mot de passe.',
                style: theme.textTheme.bodySmall?.copyWith(color: tokens.textSecondary),
              ),
              const SizedBox(height: AxisSpacing.sm),
              AxisTextField(
                label: 'Adresse e-mail',
                controller: _email,
                keyboardType: TextInputType.emailAddress,
              ),
              _feedback(_emailMessage, _emailError),
              const SizedBox(height: AxisSpacing.sm),
              AxisButton(
                label: 'Enregistrer l’e-mail',
                variant: AxisButtonVariant.outline,
                onPressed: _savingEmail ? null : _saveEmail,
                loading: _savingEmail,
              ),
              const SizedBox(height: AxisSpacing.lg),
            ],
            Text('Changer le mot de passe', style: title),
            const SizedBox(height: AxisSpacing.sm),
            AxisTextField(label: 'Mot de passe actuel', controller: _current, isPassword: true),
            const SizedBox(height: AxisSpacing.sm),
            AxisTextField(
              label: 'Nouveau mot de passe',
              controller: _password,
              isPassword: true,
              helperText: '8 caractères minimum',
            ),
            const SizedBox(height: AxisSpacing.sm),
            AxisTextField(label: 'Confirmer le mot de passe', controller: _confirm, isPassword: true),
            _feedback(_passwordMessage, _passwordError),
            const SizedBox(height: AxisSpacing.sm),
            AxisButton(
              label: 'Changer le mot de passe',
              onPressed: _savingPassword ? null : _savePassword,
              loading: _savingPassword,
            ),
          ],
        ),
      ),
    );
  }
}
