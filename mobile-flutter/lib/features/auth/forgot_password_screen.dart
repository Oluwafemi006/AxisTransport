import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/session.dart';
import '../../core/theme/axis_spacing.dart';
import '../../core/theme/axis_tokens.dart';
import '../../core/widgets/axis_button.dart';
import '../../core/widgets/axis_text_field.dart';

/// Mot de passe oublié (clients) : e-mail, puis code à 6 chiffres et nouveau mot de passe.
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _email = TextEditingController();
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  bool _busy = false;
  bool _codeSent = false;
  String? _notice;
  String? _error;
  String? _done;

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Veuillez saisir une adresse e-mail valide.');
      return;
    }
    if (_codeSent && _code.text.trim().length != 6) {
      setState(() => _error = 'Saisissez le code à 6 chiffres reçu par e-mail.');
      return;
    }
    if (_codeSent && _password.text != _confirm.text) {
      setState(() => _error = 'Les deux mots de passe ne correspondent pas.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final api = ref.read(apiClientProvider);
      if (_codeSent) {
        final detail = await api.confirmPasswordReset(
          email: email,
          code: _code.text.trim(),
          password: _password.text,
        );
        if (mounted) setState(() => _done = detail);
      } else {
        final detail = await api.requestPasswordReset(email);
        if (mounted) {
          setState(() {
            _notice = detail;
            _codeSent = true;
          });
        }
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _backToLogin() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/connexion');
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.axis;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Mot de passe oublié')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AxisSpacing.screen),
          children: [
            Text(
              _done ??
                  _notice ??
                  'Saisissez l’e-mail de votre compte client. Personnel ou compte sans e-mail : contactez un administrateur.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: tokens.textSecondary,
              ),
            ),
            const SizedBox(height: AxisSpacing.sm),
            if (_done == null) ...[
              AxisTextField(
                label: 'E-mail',
                controller: _email,
                readOnly: _codeSent,
                keyboardType: TextInputType.emailAddress,
              ),
              if (_codeSent) ...[
                const SizedBox(height: AxisSpacing.sm),
                AxisTextField(
                  label: 'Code à 6 chiffres',
                  controller: _code,
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: AxisSpacing.sm),
                AxisTextField(
                  label: 'Nouveau mot de passe',
                  controller: _password,
                  isPassword: true,
                  helperText: '8 caractères minimum',
                ),
                const SizedBox(height: AxisSpacing.sm),
                AxisTextField(
                  label: 'Confirmer le mot de passe',
                  controller: _confirm,
                  isPassword: true,
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: AxisSpacing.sm),
                Text(
                  _error!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: tokens.danger,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: AxisSpacing.sm),
              AxisButton(
                label: _codeSent ? 'Changer le mot de passe' : 'Recevoir un code',
                onPressed: _busy ? null : _submit,
                loading: _busy,
              ),
            ] else
              AxisButton(label: 'Se connecter', onPressed: _backToLogin),
          ],
        ),
      ),
    );
  }
}
