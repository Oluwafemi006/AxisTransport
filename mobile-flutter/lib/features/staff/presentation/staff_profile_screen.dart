import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/session.dart';
import '../../../core/theme.dart';
import '../../../shared/shell.dart';
import '../../../shared/widgets.dart';

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
    final user = ref.watch(sessionProvider).user;
    final name = [
      user?.firstName ?? '',
      user?.lastName ?? '',
    ].where((item) => item.isNotEmpty).join(' ');
    return AxisScaffold(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(22, 24, 22, 32),
        children: [
          AxisCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name.isEmpty ? (user?.username ?? '') : name,
                  style: const TextStyle(
                    color: AxisColors.navyDark,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Identifiant : ${user?.username ?? ''}',
                  style: const TextStyle(color: AxisColors.muted),
                ),
                Text(
                  'Rôle : ${staffRoleLabels[user?.role] ?? user?.role ?? ''}',
                  style: const TextStyle(color: AxisColors.muted),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          OutlinedButton(
            onPressed: () => ref.read(sessionProvider.notifier).logout(),
            child: const Text('Se déconnecter'),
          ),
        ],
      ),
    );
  }
}
