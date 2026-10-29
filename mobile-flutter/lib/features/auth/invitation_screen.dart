import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/session.dart';
import '../../core/theme/axis_spacing.dart';
import '../../core/theme/axis_tokens.dart';
import '../../core/widgets/axis_button.dart';
import '../../core/widgets/axis_text_field.dart';

/// Écran d'activation de compte contrôleur suite à une invitation par e-mail.
///
/// L'accès se fait par deep link (ex. `/invitation?token=...`).
/// L'e-mail invité est verrouillé et le rôle vient exclusivement du serveur.
class InvitationScreen extends ConsumerStatefulWidget {
  const InvitationScreen({
    super.key,
    required this.token,
  });

  final String? token;

  @override
  ConsumerState<InvitationScreen> createState() => _InvitationScreenState();
}

class _InvitationScreenState extends ConsumerState<InvitationScreen> {
  final _lastName = TextEditingController();
  final _firstName = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();

  bool _loadingToken = true;
  bool _submitting = false;
  String? _invitationEmail;
  String? _invitationGroup;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _checkToken();
  }

  @override
  void dispose() {
    _lastName.dispose();
    _firstName.dispose();
    _phone.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  Future<void> _checkToken() async {
    final token = widget.token;
    if (token == null || token.trim().isEmpty) {
      setState(() {
        _loadingToken = false;
        _errorMessage = 'Le jeton d’invitation est manquant ou invalide.';
      });
      return;
    }

    try {
      final api = ref.read(apiClientProvider);
      final res = await api.checkStaffInvitation(token.trim());
      if (mounted) {
        setState(() {
          _loadingToken = false;
          _invitationEmail = res['email'] as String? ?? '';
          _invitationGroup = res['group'] as String? ?? 'Contrôleur';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingToken = false;
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  Future<void> _submit() async {
    final token = widget.token;
    final password = _password.text;
    final confirm = _confirmPassword.text;

    if (token == null || token.trim().isEmpty) {
      setState(() => _errorMessage = 'Jeton d’invitation introuvable.');
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
      _submitting = true;
      _errorMessage = null;
    });

    try {
      final api = ref.read(apiClientProvider);
      await api.acceptStaffInvitation(
        token: token.trim(),
        password: password,
      );

      // Si l'e-mail est connu, tenter la connexion immédiate pour ouvrir l'espace contrôleur
      if (_invitationEmail != null && _invitationEmail!.isNotEmpty) {
        await ref.read(sessionProvider.notifier).login(
          _invitationEmail!,
          password,
        );
      }

      if (mounted) {
        // GoRouter redirigera vers l'espace personnel
        context.go('/');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
        });
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.axis;
    final theme = Theme.of(context);

    if (_loadingToken) {
      return Scaffold(
        backgroundColor: theme.colorScheme.surface,
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: Column(
          children: [
            // En-tête sombre contrôleur
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(
                AxisSpacing.screen,
                AxisSpacing.lg,
                AxisSpacing.screen,
                AxisSpacing.md,
              ),
              color: tokens.ink,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: tokens.accent,
                      borderRadius: BorderRadius.circular(AxisRadius.badge),
                    ),
                    child: Text(
                      'INVITATION ${_invitationGroup?.toUpperCase() ?? "CONTRÔLEUR"}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: tokens.ink,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                  const SizedBox(height: AxisSpacing.sm),
                  Text(
                    'Activez votre compte',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: tokens.onDark,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'AXIS TRANSPORT LOGISTIQUE vous a invité à rejoindre l’équipe.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: tokens.borderStrong,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            // Formulaire
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(AxisSpacing.screen),
                children: [
                  // Champ E-mail verrouillé
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'E-mail de l’invitation',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: tokens.textSecondary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: AxisSpacing.xxs),
                      Container(
                        height: 50,
                        padding: const EdgeInsets.symmetric(
                          horizontal: AxisSpacing.sm,
                        ),
                        decoration: BoxDecoration(
                          color: tokens.surfaceSoft,
                          borderRadius: BorderRadius.circular(AxisRadius.sm),
                          border: Border.all(color: tokens.border),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _invitationEmail?.isNotEmpty == true
                                  ? _invitationEmail!
                                  : '[e-mail invité]',
                              style: theme.textTheme.bodyLarge?.copyWith(
                                color: tokens.textSecondary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Icon(
                              Icons.lock_outline_rounded,
                              size: 18,
                              color: tokens.iconMuted,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AxisSpacing.sm),
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
                  const SizedBox(height: AxisSpacing.md),
                  // Encadré d'avertissement d'expiration
                  Container(
                    padding: const EdgeInsets.all(AxisSpacing.sm),
                    decoration: BoxDecoration(
                      color: tokens.accentSoft,
                      borderRadius: BorderRadius.circular(AxisRadius.sm),
                    ),
                    child: Text(
                      'Ce lien est personnel et ne fonctionne qu’une seule fois. Il expire après 48h.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: tokens.onAccentSoft,
                        fontWeight: FontWeight.w600,
                        height: 1.4,
                      ),
                    ),
                  ),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: AxisSpacing.sm),
                    Container(
                      padding: const EdgeInsets.all(AxisSpacing.sm),
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
                ],
              ),
            ),
            // Bouton d'action
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
              child: AxisButton(
                label: 'Activer mon compte',
                onPressed: _submitting ? null : _submit,
                loading: _submitting,
                variant: AxisButtonVariant.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

