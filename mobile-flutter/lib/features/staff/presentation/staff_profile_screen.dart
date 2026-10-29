import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/session.dart';
import '../../../core/theme/axis_spacing.dart';
import '../../../core/theme/axis_tokens.dart';
import '../../../core/widgets/axis_button.dart';
import '../../../core/widgets/axis_header.dart';

/// Libellés des rôles du personnel, tels que le serveur les nomme.
const staffRoleLabels = {
  'COUNTER': 'Guichetier',
  'CONTROLLER': 'Contrôleur',
  'ADMIN': 'Administrateur',
};

/// Profil d'un membre du personnel : identité, rôle, déconnexion.
class StaffProfileScreen extends ConsumerWidget {
  const StaffProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final axis = context.axis;
    final theme = Theme.of(context);
    final user = ref.watch(sessionProvider).user;
    final name = [
      user?.firstName ?? '',
      user?.lastName ?? '',
    ].where((item) => item.isNotEmpty).join(' ');

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Column(
        children: [
          const AxisHeader(
            variant: AxisHeaderVariant.controller,
            title: 'Profil',
            subtitle: 'Compte personnel Axis Transport',
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(AxisSpacing.md),
              children: [
                Container(
                  padding: const EdgeInsets.all(AxisSpacing.md),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(AxisRadius.lg),
                    border: Border.all(color: axis.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name.isEmpty ? (user?.username ?? '') : name,
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: AxisSpacing.xs),
                      Text(
                        'Identifiant : ${user?.username ?? ''}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: axis.textSecondary,
                        ),
                      ),
                      const SizedBox(height: AxisSpacing.xxs),
                      Text(
                        'Rôle : ${staffRoleLabels[user?.role] ?? user?.role ?? ''}',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: axis.ink,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AxisSpacing.md),
                AxisButton(
                  label: 'Se déconnecter',
                  variant: AxisButtonVariant.secondary,
                  icon: const Icon(Icons.logout_rounded),
                  onPressed: () => ref.read(sessionProvider.notifier).logout(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
