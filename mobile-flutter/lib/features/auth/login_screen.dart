import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/session.dart';
import '../../core/theme/axis_spacing.dart';
import '../../core/theme/axis_tokens.dart';
import '../../core/widgets/axis_button.dart';
import '../../core/widgets/axis_text_field.dart';
import '../../router.dart' show safeReturnLocation;
import 'auth_header.dart';

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

  // Paramètres de l'adresse (session expirée, écran à retrouver) ; aucun hors du routeur (tests, écran modal).
  Map<String, String> _query(BuildContext context) {
    try {
      return GoRouterState.of(context).uri.queryParameters;
    } catch (_) {
      return const {};
    }
  }

  Future<void> _submit() async {
    final username = _username.text.trim();
    final password = _password.text;

    if (username.isEmpty || password.isEmpty) {
      setState(
        () => _message =
            'Veuillez saisir votre identifiant et votre mot de passe.',
      );
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
        // Session expirée : retour à l'écran quitté. Sinon, redirection du routeur ou fermeture de l'écran modal.
        final back = safeReturnLocation(_query(context)['retour']);
        if (back != null) {
          context.go(back);
        } else if (!widget.required && context.canPop()) {
          context.pop();
        } else {
          context.go('/');
        }
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _message = error.toString().replaceFirst('Exception: ', ''),
        );
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
      // En-tête fixe ; le formulaire, centré dans l'espace restant, défile seul si l'écran est trop petit.
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AuthHeader(
            title: 'Bon retour,\nconnectez-vous',
            subtitle: 'Voyager, expédier, louer.',
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.paddingOf(context).bottom,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight:
                        constraints.maxHeight -
                        MediaQuery.paddingOf(context).bottom,
                  ),
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AxisSpacing.screenAuth,
                        AxisSpacing.lg,
                        AxisSpacing.screenAuth,
                        AxisSpacing.md,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_query(context)['expiree'] == '1') ...[
                            Container(
                              key: const Key('session-expired-banner'),
                              padding: const EdgeInsets.all(AxisSpacing.sm),
                              margin: const EdgeInsets.only(bottom: AxisSpacing.sm),
                              decoration: BoxDecoration(
                                color: tokens.warning.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(AxisRadius.sm),
                              ),
                              child: Text(
                                'Votre session a expiré. Reconnectez-vous pour reprendre là où vous étiez.',
                                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                          AxisTextField(
                            // L'API de connexion n'accepte que l'identifiant (ni e-mail ni téléphone).
                            label: 'Identifiant',
                            hintText: 'Votre identifiant',
                            borderRadius: AxisRadius.authField,
                            controller: _username,
                            textInputAction: TextInputAction.next,
                          ),
                          const SizedBox(height: AxisSpacing.sm),
                          AxisTextField(
                            label: 'Mot de passe',
                            hintText: 'Votre mot de passe',
                            borderRadius: AxisRadius.authField,
                            controller: _password,
                            isPassword: true,
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => _submit(),
                          ),
                          const SizedBox(height: 6),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: () =>
                                  context.push('/mot-de-passe-oublie'),
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 6,
                                ),
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
                              margin: const EdgeInsets.only(
                                bottom: AxisSpacing.sm,
                              ),
                              decoration: BoxDecoration(
                                color: tokens.danger.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(
                                  AxisRadius.sm,
                                ),
                                border: Border.all(
                                  color: tokens.danger.withValues(alpha: 0.3),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.error_outline,
                                    color: tokens.danger,
                                    size: 20,
                                  ),
                                  const SizedBox(width: AxisSpacing.xs),
                                  Expanded(
                                    child: Text(
                                      _message!,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
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
                          // Passe à la ligne sur un écran étroit ou avec un texte agrandi.
                          Wrap(
                            alignment: WrapAlignment.center,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                'Pas encore de compte ? ',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: tokens.textSecondary,
                                ),
                              ),
                              TextButton(
                                onPressed: () => context.push('/inscription'),
                                style: TextButton.styleFrom(
                                  minimumSize: const Size(
                                    0,
                                    AxisSizes.minTarget,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                  ),
                                ),
                                child: Text(
                                  'Créer un compte',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.primary,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
