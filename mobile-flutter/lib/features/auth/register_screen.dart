import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/session.dart';
import '../../core/theme/axis_spacing.dart';
import '../../core/theme/axis_tokens.dart';
import '../../core/widgets/axis_button.dart';
import '../../core/widgets/axis_text_field.dart';

/// Écran d'inscription client selon la maquette Inscription.html.
///
/// L'identifiant est demandé : l'API de connexion n'accepte ni e-mail ni téléphone.
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _username = TextEditingController();
  final _lastName = TextEditingController();
  final _firstName = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();

  bool _busy = false;
  String? _errorMessage;

  @override
  void dispose() {
    _username.dispose();
    _lastName.dispose();
    _firstName.dispose();
    _phone.dispose();
    _email.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final lastName = _lastName.text.trim();
    final firstName = _firstName.text.trim();
    final phone = _phone.text.trim();
    final email = _email.text.trim();
    final password = _password.text;
    final confirm = _confirmPassword.text;

    if (firstName.isEmpty || lastName.isEmpty) {
      setState(() => _errorMessage = 'Veuillez renseigner votre nom et prénom.');
      return;
    }
    if (phone.isEmpty) {
      setState(() => _errorMessage = 'Veuillez renseigner votre numéro de téléphone.');
      return;
    }
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _errorMessage = 'Veuillez saisir une adresse e-mail valide.');
      return;
    }
    if (_username.text.trim().isEmpty) {
      setState(() => _errorMessage = 'Choisissez un identifiant de connexion.');
      return;
    }
    if (password.length < 8) {
      setState(() => _errorMessage = 'Le mot de passe doit comporter au moins 8 caractères.');
      return;
    }
    if (password != confirm) {
      setState(() => _errorMessage = 'Les mots de passe ne correspondent pas.');
      return;
    }

    setState(() {
      _busy = true;
      _errorMessage = null;
    });

    try {
      final username = _username.text.trim();
      final formattedPhone = phone.startsWith('+229') ? phone : '+229$phone';

      await ref.read(sessionProvider.notifier).register(
        username: username,
        password: password,
        firstName: firstName,
        lastName: lastName,
        phone: formattedPhone,
        email: email,
      );

      if (mounted) {
        // Une fois connecté, GoRouter redirige automatiquement vers l'accueil client.
        if (context.canPop()) {
          context.pop();
        } else {
          context.go('/');
        }
      }
    } catch (error) {
      if (mounted) {
        setState(() => _errorMessage = error.toString().replaceFirst('Exception: ', ''));
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
      body: SafeArea(
        child: Column(
          children: [
            // En-tête avec bouton retour
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AxisSpacing.screen,
                AxisSpacing.sm,
                AxisSpacing.screen,
                AxisSpacing.xs,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    label: 'Retour',
                    button: true,
                    child: Material(
                      color: tokens.surfaceSoft,
                      borderRadius: BorderRadius.circular(AxisRadius.small),
                      child: InkWell(
                        onTap: () {
                          if (context.canPop()) {
                            context.pop();
                          } else {
                            context.go('/connexion');
                          }
                        },
                        borderRadius: BorderRadius.circular(AxisRadius.small),
                        child: const SizedBox(
                          width: AxisSizes.minTarget,
                          height: AxisSizes.minTarget,
                          child: Icon(Icons.arrow_back_rounded, size: 22),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AxisSpacing.sm),
                  Text(
                    'Créer un compte',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: tokens.ink,
                      fontSize: 26,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Le même compte sur l’app et sur le site.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: tokens.textSecondary,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            // Formulaire
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: AxisSpacing.screen,
                  vertical: AxisSpacing.xs,
                ),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: AxisTextField(
                          label: 'Nom',
                          controller: _lastName,
                          textInputAction: TextInputAction.next,
                        ),
                      ),
                      const SizedBox(width: AxisSpacing.xs),
                      Expanded(
                        child: AxisTextField(
                          label: 'Prénom',
                          controller: _firstName,
                          textInputAction: TextInputAction.next,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AxisSpacing.sm),
                  AxisTextField(
                    label: 'Téléphone',
                    controller: _phone,
                    isPhone: true,
                    hintText: '01 XX XX XX XX',
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: AxisSpacing.sm),
                  AxisTextField(
                    label: 'E-mail',
                    controller: _email,
                    hintText: 'exemple@mail.com',
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: AxisSpacing.sm),
                  // La connexion n'accepte que l'identifiant (API) : le client le choisit et le connaît.
                  AxisTextField(
                    label: 'Identifiant',
                    controller: _username,
                    helperText: 'Servira à vous connecter',
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: AxisSpacing.sm),
                  AxisTextField(
                    label: 'Mot de passe',
                    controller: _password,
                    isPassword: true,
                    helperText: '8 caractères minimum',
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: AxisSpacing.sm),
                  AxisTextField(
                    label: 'Confirmer le mot de passe',
                    controller: _confirmPassword,
                    isPassword: true,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _submit(),
                  ),
                ],
              ),
            ),
            // Pied de page avec bouton d'action et lien retour
            Container(
              padding: const EdgeInsets.fromLTRB(
                AxisSpacing.screen,
                AxisSpacing.sm,
                AxisSpacing.screen,
                AxisSpacing.lg,
              ),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                border: Border(top: BorderSide(color: tokens.border)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_errorMessage != null) ...[
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
                              _errorMessage!,
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
                  AxisButton(
                    label: 'Créer mon compte',
                    onPressed: _busy ? null : _submit,
                    loading: _busy,
                    variant: AxisButtonVariant.primary,
                  ),
                  const SizedBox(height: AxisSpacing.sm),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Déjà un compte ? ',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: tokens.textSecondary,
                          fontSize: 14,
                        ),
                      ),
                      GestureDetector(
                        onTap: () {
                          if (context.canPop()) {
                            context.pop();
                          } else {
                            context.go('/connexion');
                          }
                        },
                        child: Text(
                          'Se connecter',
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
          ],
        ),
      ),
    );
  }
}

