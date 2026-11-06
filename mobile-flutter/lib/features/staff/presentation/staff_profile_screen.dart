import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/formatters.dart';
import '../../../core/session.dart';
import '../../../core/theme/axis_spacing.dart';
import '../../../core/widgets/axis_header.dart';
import '../../../shared/contact_actions.dart';
import '../../profile/profile_menu.dart';
import 'staff_home_screen.dart';

/// Libellés des rôles du personnel, tels que le serveur les nomme.
const staffRoleLabels = {
  'COUNTER': 'Guichetier',
  'CONTROLLER': 'Contrôleur',
  'ADMIN': 'Administrateur',
};

/// Résumé du jour de l'agent, calculé par le serveur (/staff/sales/summary/).
final staffDaySummaryProvider = FutureProvider.autoDispose<ControllerDaySummary>((ref) async {
  ref.watch(staffActivityProvider);
  return ControllerDaySummary.fromJson(await ref.read(apiClientProvider).saleSummary());
});

/// Profil d'un membre du personnel : identité, résumé du jour, réglages, déconnexion.
class StaffProfileScreen extends ConsumerWidget {
  const StaffProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final user = ref.watch(sessionProvider).user;
    final summary = ref.watch(staffDaySummaryProvider);
    final contact = ref.watch(contactProvider).value;
    final hasContact = (contact?['phone'] ?? '').isNotEmpty || (contact?['whatsapp'] ?? '').isNotEmpty;
    final site = siteUrlFromApi();

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
                if (user != null) ProfileHeader(user: user, roleLabel: staffRoleLabels[user.role] ?? user.role),
                Card(
                  margin: const EdgeInsets.only(top: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: summary.when(
                      loading: () => const Text('Résumé du jour : chargement…'),
                      error: (_, _) => const Text('Résumé du jour indisponible (connexion).'),
                      data: (day) => Column(
                        key: const Key('staff-day-summary'),
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Aujourd’hui', style: theme.textTheme.titleSmall),
                          const SizedBox(height: 6),
                          Text('Billets vendus : ${day.soldTickets} · Billets scannés : ${day.scannedTickets}'),
                          Text('Colis enregistrés : ${day.parcelsCount}'),
                          Text(
                            'Espèces : ${formatMoney(day.cashAmountFcfa, 'XOF')} · '
                            'Mobile Money : ${formatMoney(day.mobileMoneyAmountFcfa, 'XOF')}',
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                ProfileMenuGroup(
                  items: [
                    ProfileMenuItem(
                      icon: Icons.lock_outline,
                      label: 'Changer le mot de passe',
                      onTap: () => context.push('/mon-compte'),
                    ),
                    ProfileMenuItem(
                      icon: Icons.fingerprint,
                      label: 'Paramètres de connexion',
                      keyName: 'menu-connection',
                      onTap: () => context.push('/parametres-connexion'),
                    ),
                  ],
                ),
                ProfileMenuGroup(
                  items: [
                    if (hasContact)
                      ProfileMenuItem(
                        icon: Icons.help_outline,
                        label: 'Aide et suggestions',
                        onTap: () => context.push('/aide'),
                      ),
                    if (site.isNotEmpty)
                      ProfileMenuItem(
                        icon: Icons.share_outlined,
                        label: 'Partager l’application',
                        onTap: () => shareApp(site),
                      ),
                    ProfileMenuItem(
                      icon: Icons.info_outline,
                      label: 'À propos',
                      keyName: 'menu-about',
                      onTap: () => context.push('/a-propos'),
                    ),
                  ],
                ),
                ProfileMenuGroup(
                  items: [
                    ProfileMenuItem(
                      icon: Icons.logout_rounded,
                      label: 'Déconnexion',
                      keyName: 'menu-logout',
                      onTap: () => ref.read(sessionProvider.notifier).logout(),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
