import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/session.dart';
import '../../core/theme/axis_spacing.dart';
import '../../core/theme/axis_tokens.dart';
import '../../core/widgets/axis_button.dart';
import '../../core/widgets/axis_text_field.dart';

/// Mot de passe oublié (clients) : e-mail, puis un lien reçu par e-mail ouvre la page du site
/// où le client choisit lui-même son nouveau mot de passe.
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _email = TextEditingController();

  bool _busy = false;
  String? _notice;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final email = _email.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Veuillez saisir une adresse e-mail valide.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final detail = await ref.read(apiClientProvider).requestPasswordReset(email);
      if (mounted) setState(() => _notice = detail);
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
              _notice != null
                  ? '$_notice Ouvrez le lien reçu pour choisir votre nouveau mot de passe.'
                  : 'Saisissez l’e-mail de votre compte client : vous recevrez un lien pour choisir un nouveau mot de passe. Personnel ou compte sans e-mail : contactez un administrateur.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: tokens.textSecondary,
              ),
            ),
            const SizedBox(height: AxisSpacing.sm),
            if (_notice == null) ...[
              AxisTextField(
                label: 'E-mail',
                controller: _email,
                keyboardType: TextInputType.emailAddress,
              ),
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
                label: 'Recevoir un lien',
                onPressed: _busy ? null : _submit,
                loading: _busy,
              ),
            ] else
              AxisButton(label: 'Retour à la connexion', onPressed: _backToLogin),
          ],
        ),
      ),
    );
  }
}
