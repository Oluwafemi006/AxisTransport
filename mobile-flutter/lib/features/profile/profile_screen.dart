import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/theme/axis_spacing.dart';
import '../../core/theme/axis_tokens.dart';
import '../../shared/contact_actions.dart';
import '../../shared/widgets.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  int _tickets = 0;
  int _parcels = 0;
  int _rentals = 0;

  @override
  void initState() {
    super.initState();
    _loadCounts();
  }

  Future<void> _loadCounts() async {
    final api = ref.read(apiClientProvider);
    try {
      final results = await Future.wait([
        api.tickets(),
        api.parcels(),
        api.rentals(),
      ]);
      if (mounted) {
        setState(() {
          _tickets = results[0].length;
          _parcels = results[1].length;
          _rentals = results[2].length;
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final user = session.user;
    final theme = Theme.of(context);
    final tokens = context.axis;
    if (!session.ready) return const Center(child: CircularProgressIndicator());
    if (user == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: AxisCard(
            child: Column(
              children: [
                Text(
                  'Mon profil',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: AxisColors.text,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Connectez-vous pour retrouver vos billets, colis et locations.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AxisColors.muted, height: 1.4),
                ),
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: () => context.push('/login'),
                  child: const Text('Se connecter'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        AxisCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: AxisColors.navy,
                    child: Text(
                      user.displayName.characters.first.toUpperCase(),
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: tokens.onDark,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user.displayName,
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: AxisColors.text,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          user.phone.isEmpty ? user.username : user.phone,
                          style: const TextStyle(color: AxisColors.muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  _Count(value: _tickets, label: 'Billets'),
                  const SizedBox(width: 8),
                  _Count(value: _parcels, label: 'Colis'),
                  const SizedBox(width: 8),
                  _Count(value: _rentals, label: 'Locations'),
                ],
              ),
              const SizedBox(height: 22),
              OutlinedButton(
                onPressed: () => context.push('/mon-compte'),
                child: const Text('E-mail et mot de passe'),
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: () async {
                  await ref.read(sessionProvider.notifier).logout();
                  if (context.mounted) context.go('/');
                },
                child: const Text('Se déconnecter'),
              ),
            ],
          ),
        ),
        const ContactActions(),
      ],
    );
  }
}

class _Count extends StatelessWidget {
  const _Count({required this.value, required this.label});
  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.axis;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
        decoration: BoxDecoration(
          color: tokens.primarySoft,
          borderRadius: BorderRadius.circular(AxisRadius.sm),
        ),
        child: Column(
          children: [
            Text(
              '$value',
              style: theme.textTheme.headlineSmall?.copyWith(
                color: AxisColors.navy,
                fontWeight: FontWeight.w900,
              ),
            ),
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: AxisColors.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
