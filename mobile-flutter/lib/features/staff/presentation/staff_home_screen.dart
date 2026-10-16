import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/session.dart';
import '../../../core/theme.dart';
import '../../../shared/shell.dart';
import '../../../shared/widgets.dart';

/// Accueil du personnel : accès direct au scanner et à la vente.
class StaffHomeScreen extends ConsumerWidget {
  const StaffHomeScreen({super.key});

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
          const Align(alignment: Alignment.centerLeft, child: Brand()),
          const SizedBox(height: 26),
          Text(
            'Bonjour ${name.isEmpty ? (user?.username ?? '') : name}',
            style: const TextStyle(
              color: AxisColors.navyDark,
              fontSize: 26,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Espace équipe Axis Transport',
            style: TextStyle(color: AxisColors.muted),
          ),
          const SizedBox(height: 28),
          FilledButton.icon(
            onPressed: () => context.go('/scanner'),
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Ouvrir le Scanner QR'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => context.go('/vendre'),
            icon: const Icon(Icons.confirmation_number_outlined),
            label: const Text('Vendre un billet'),
          ),
        ],
      ),
    );
  }
}
