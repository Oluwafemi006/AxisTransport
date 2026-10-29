import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/session.dart';
import '../../core/theme/axis_spacing.dart';
import '../../core/theme/axis_tokens.dart';
import '../../core/widgets/axis_button.dart';
import '../../core/widgets/axis_text_field.dart';

/// Écran de connexion de l'application Axis Transport selon la maquette Connexion.html.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key, this.required = false});

  /// Vrai quand l'écran est la porte d'entrée de l'application (aucun retour possible).
  final bool required;

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
    final username = _username.text.trim();
    final password = _password.text;

    if (username.isEmpty || password.isEmpty) {
      setState(() => _message = 'Veuillez saisir votre identifiant et votre mot de passe.');
      return;
    }

    setState(() {
      _busy = true;
      _message = null;
    });

    try {
      final session = ref.read(sessionProvider.notifier);
      await session.login(username, password);

      if (mounted) {
        // Redirection gérée par le routeur ou fermeture de l'écran modal
        if (!widget.required && context.canPop()) {
          context.pop();
        } else {
          context.go('/');
        }
      }
    } catch (error) {
      if (mounted) {
        setState(() => _message = error.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.axis;
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // En-tête bleu avec logo A et rayon bas de 28
            Container(
              padding: EdgeInsets.fromLTRB(
                AxisSpacing.screenAuth,
                MediaQuery.paddingOf(context).top + AxisSpacing.xl,
                AxisSpacing.screenAuth,
                AxisSpacing.xl,
              ),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(28),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Logo Axis : carré ambré 44x44 avec "A" + texte "AXIS"
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: tokens.accent,
                          borderRadius: BorderRadius.circular(AxisRadius.sm),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          'A',
                          style: TextStyle(
                            color: theme.colorScheme.primary,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: AxisSpacing.xs),
                      Text(
                        'AXIS',
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.6,
                          fontSize: 22,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AxisSpacing.md),
                  Text(
                    'Connexion',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 28,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Voyager, expédier, louer.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: tokens.borderStrong,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
            // Formulaire
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AxisSpacing.screenAuth,
                AxisSpacing.lg,
                AxisSpacing.screenAuth,
                AxisSpacing.md,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AxisTextField(
                    // L'API de connexion n'accepte que l'identifiant (ni e-mail ni téléphone).
                    label: 'Identifiant',
                    controller: _username,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: AxisSpacing.sm),
                  AxisTextField(
                    label: 'Mot de passe',
                    controller: _password,
                    isPassword: true,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _submit(),
                  ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Veuillez contacter le support de votre agence pour réinitialiser votre mot de passe.',
                            ),
                          ),
                        );
                      },
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        minimumSize: const Size(0, 44),
                        foregroundColor: theme.colorScheme.primary,
                      ),
                      child: const Text(
                        'Mot de passe oublié ?',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  if (_message != null) ...[
                    Container(
                      padding: const EdgeInsets.all(AxisSpacing.sm),
                      margin: const EdgeInsets.only(bottom: AxisSpacing.sm),
                      decoration: BoxDecoration(
                        color: tokens.danger.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(AxisRadius.sm),
                        border: Border.all(
                          color: tokens.danger.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline, color: tokens.danger, size: 20),
                          const SizedBox(width: AxisSpacing.xs),
                          Expanded(
                            child: Text(
                              _message!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: tokens.danger,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  AxisButton(
                    label: 'Se connecter',
                    onPressed: _busy ? null : _submit,
                    loading: _busy,
                    variant: AxisButtonVariant.primary,
                  ),
                  const SizedBox(height: AxisSpacing.md),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Pas encore de compte ? ',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: tokens.textSecondary,
                          fontSize: 14,
                        ),
                      ),
                      GestureDetector(
                        onTap: () => context.push('/inscription'),
                        child: Text(
                          'Créer un compte',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Encadré explicatif pour les contrôleurs
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AxisSpacing.screenAuth,
                AxisSpacing.md,
                AxisSpacing.screenAuth,
                AxisSpacing.xl,
              ),
              child: Container(
                padding: const EdgeInsets.all(AxisSpacing.sm),
                decoration: BoxDecoration(
                  color: tokens.surfaceSoft,
                  borderRadius: BorderRadius.circular(AxisRadius.sm),
                  border: Border.all(color: tokens.border),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.mail_outline_rounded,
                      size: 20,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: AxisSpacing.xs),
                    Expanded(
                      child: Text(
                        'Contrôleur ? Créez votre compte avec le lien reçu par e-mail, puis connectez-vous ici. L’app s’ouvre sur votre espace.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: tokens.textSecondary,
                          fontSize: 12,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
