import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/formatters.dart';
import '../../core/models.dart';
import '../../core/session.dart';
import '../../core/theme/axis_theme.dart';
import '../../core/widgets/widgets.dart';
import '../trips/presentation/trip_search_card.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  List<Trip> _trips = [];
  List<Ticket> _tickets = [];
  TripBanner? _banner;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final api = ref.read(apiClientProvider);
    var tickets = await api.store.readCachedTickets();
    if (mounted) setState(() => _tickets = tickets);
    try {
      final trips = await api.trips();
      if (!mounted) return;
      setState(() {
        _trips = trips;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
    try {
      final banner = await api.tripBanner();
      if (mounted) setState(() => _banner = banner);
    } catch (_) {}
    try {
      final user = await api.me();
      if (user.isClient) {
        await api.store.setActiveClient(user.id);
        tickets = await api.tickets();
        await api.store.cacheTickets(tickets);
      }
    } catch (_) {
      tickets = await api.store.readCachedTickets();
    }
    if (mounted) {
      setState(() {
        _tickets = tickets;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final theme = Theme.of(context);
    final axis = context.axis;
    final userName = session.user == null
        ? null
        : (session.user!.firstName.isEmpty
              ? session.user!.username
              : session.user!.firstName);

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.only(bottom: AxisSpacing.s24),
        children: [
          // En-tête bleu marine (Main.html)
          Container(
            color: theme.colorScheme.primary,
            padding: const EdgeInsets.fromLTRB(
              AxisSpacing.s20,
              AxisSpacing.s16,
              AxisSpacing.s20,
              AxisSpacing.s20,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: axis.accent,
                            borderRadius: BorderRadius.circular(AxisRadius.small),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            'A',
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ),
                        const SizedBox(width: AxisSpacing.s10),
                        Text(
                          'AXIS',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: theme.colorScheme.onPrimary,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ],
                    ),
                    Tooltip(
                      message: 'Notifications',
                      child: Semantics(
                        button: true,
                        label: 'Notifications',
                        child: Material(
                          color: theme.colorScheme.onPrimary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(AxisRadius.small),
                          child: InkWell(
                            onTap: () => session.user == null
                                ? context.push('/connexion')
                                : context.go('/profil'),
                            borderRadius: BorderRadius.circular(AxisRadius.small),
                            child: SizedBox(
                              width: AxisSizes.minTarget,
                              height: AxisSizes.minTarget,
                              child: Icon(
                                Icons.notifications_none_rounded,
                                color: theme.colorScheme.onPrimary,
                                size: AxisSizes.icon,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AxisSpacing.s20),
                Text(
                  userName == null ? 'Bonjour' : 'Bonjour, $userName',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: axis.borderStrong,
                  ),
                ),
                const SizedBox(height: AxisSpacing.s4),
                Text(
                  'Où voyagez-vous aujourd’hui ?',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    color: theme.colorScheme.onPrimary,
                  ),
                ),
              ],
            ),
          ),

          // Carte de recherche flottante à cheval sur l'en-tête bleu marine
          Stack(
            children: [
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 68,
                child: ColoredBox(color: theme.colorScheme.primary),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: AxisSpacing.screen),
                child: TripSearchCard(),
              ),
            ],
          ),

          // Bandeau dynamique du jour (si fourni par l'API)
          if (_banner != null && _banner!.bannerText.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AxisSpacing.screen,
                AxisSpacing.s14,
                AxisSpacing.screen,
                0,
              ),
              child: AxisCard(
                backgroundColor: axis.surfaceSoft,
                padding: const EdgeInsets.symmetric(
                  horizontal: AxisSpacing.s14,
                  vertical: AxisSpacing.s12,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.directions_bus_outlined,
                      color: theme.colorScheme.primary,
                      size: AxisSizes.icon,
                    ),
                    const SizedBox(width: AxisSpacing.s10),
                    Expanded(
                      child: Text(
                        _banner!.bannerText,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: axis.ink,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Bandeau d'information d'embarquement (départ − 30 min)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AxisSpacing.screen,
              AxisSpacing.s14,
              AxisSpacing.screen,
              0,
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AxisSpacing.s14,
                vertical: AxisSpacing.s12,
              ),
              decoration: BoxDecoration(
                color: axis.primarySoft,
                borderRadius: BorderRadius.circular(AxisRadius.button),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(AxisRadius.small),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.access_time_rounded,
                      color: theme.colorScheme.primary,
                      size: AxisSizes.icon,
                    ),
                  ),
                  const SizedBox(width: AxisSpacing.s12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Embarquement 30 min avant le départ',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Présentez-vous à l’arrêt muni de votre billet QR.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: axis.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Section Services (3 tuiles : Louer un véhicule, Suivre un colis, Mes billets)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AxisSpacing.screen,
              AxisSpacing.s16,
              AxisSpacing.screen,
              0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Services',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: axis.ink,
                  ),
                ),
                const SizedBox(height: AxisSpacing.s10),
                Row(
                  children: [
                    Expanded(
                      child: _ServiceTile(
                        label: 'Louer un véhicule',
                        icon: Icons.directions_car_outlined,
                        iconBg: axis.accentSoft,
                        iconFg: axis.onAccentSoft,
                        onTap: () => context.go('/location'),
                      ),
                    ),
                    const SizedBox(width: AxisSpacing.s10),
                    Expanded(
                      child: _ServiceTile(
                        label: 'Suivre un colis',
                        icon: Icons.inventory_2_outlined,
                        iconBg: axis.successSoft,
                        iconFg: axis.success,
                        onTap: () => context.go('/colis'),
                      ),
                    ),
                    const SizedBox(width: AxisSpacing.s10),
                    Expanded(
                      child: _ServiceTile(
                        label: 'Mes billets',
                        icon: Icons.confirmation_number_outlined,
                        iconBg: axis.primarySoft,
                        iconFg: theme.colorScheme.primary,
                        onTap: () => context.go('/billets'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Billets récents / en cache hors ligne (ex. consultation immédiate hors connexion)
          if (_tickets.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AxisSpacing.screen,
                AxisSpacing.s20,
                AxisSpacing.screen,
                AxisSpacing.s10,
              ),
              child: Text(
                'Mes billets récents',
                style: theme.textTheme.titleSmall?.copyWith(color: axis.ink),
              ),
            ),
            ..._tickets.map(
              (ticket) => Padding(
                padding: const EdgeInsets.fromLTRB(
                  AxisSpacing.screen,
                  0,
                  AxisSpacing.screen,
                  AxisSpacing.s10,
                ),
                child: AxisCard(
                  onTap: () => context.push(
                    '/billets/ticket/${ticket.id}',
                    extra: ticket,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              ticket.reference,
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: axis.ink,
                              ),
                            ),
                            const SizedBox(height: AxisSpacing.s4),
                            Text(
                              '${ticket.trip.route.label} · siège ${ticket.seat.number}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: axis.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: theme.colorScheme.primary,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],

          // Départs disponibles ou état de chargement / erreur réseau
          if (_loading)
            const Padding(
              padding: EdgeInsets.fromLTRB(
                AxisSpacing.screen,
                AxisSpacing.s20,
                AxisSpacing.screen,
                0,
              ),
              child: Column(
                children: [
                  SkeletonBox(height: 84, borderRadius: AxisRadius.card),
                  SizedBox(height: AxisSpacing.s10),
                  SkeletonBox(height: 84, borderRadius: AxisRadius.card),
                ],
              ),
            )
          else if (_error != null && _tickets.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AxisSpacing.screen,
                AxisSpacing.s16,
                AxisSpacing.screen,
                0,
              ),
              child: EmptyState(
                icon: Icons.wifi_off_rounded,
                title: 'Connexion indisponible',
                description:
                    'Impossible de récupérer les prochains départs pour le moment.',
                actionLabel: 'Réessayer',
                onAction: _load,
              ),
            )
          else if (_trips.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AxisSpacing.screen,
                AxisSpacing.s20,
                AxisSpacing.screen,
                AxisSpacing.s10,
              ),
              child: Text(
                'Départs disponibles',
                style: theme.textTheme.titleSmall?.copyWith(color: axis.ink),
              ),
            ),
            ..._trips.map(
              (trip) => Padding(
                padding: const EdgeInsets.fromLTRB(
                  AxisSpacing.screen,
                  0,
                  AxisSpacing.screen,
                  AxisSpacing.s10,
                ),
                child: AxisCard(
                  onTap: () =>
                      context.push('/billets/booking/${trip.id}/passagers'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              trip.route.label,
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: axis.ink,
                              ),
                            ),
                          ),
                          Text(
                            trip.currentFare == null
                                ? 'À renseigner'
                                : formatMoney(
                                    trip.currentFare!.amount,
                                    trip.currentFare!.currency,
                                  ),
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AxisSpacing.s4),
                      Text(
                        formatDateTime(trip.departureAt),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: axis.textSecondary,
                        ),
                      ),
                      const SizedBox(height: AxisSpacing.s12),
                      Row(
                        children: [
                          StatusChip(
                            label: '${trip.availableSeats} place(s) libre(s)',
                            variant: trip.availableSeats > 0
                                ? StatusChipVariant.success
                                : StatusChipVariant.danger,
                            dense: true,
                          ),
                          const Spacer(),
                          Text(
                            'Réserver →',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ServiceTile extends StatelessWidget {
  const _ServiceTile({
    required this.label,
    required this.icon,
    required this.iconBg,
    required this.iconFg,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color iconBg;
  final Color iconFg;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final axis = context.axis;

    return AxisCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(
        horizontal: AxisSpacing.s10,
        vertical: AxisSpacing.s14,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(AxisRadius.small),
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: iconFg, size: AxisSizes.icon),
          ),
          const SizedBox(height: AxisSpacing.s10),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium?.copyWith(
              color: axis.ink,
            ),
          ),
        ],
      ),
    );
  }
}
