import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/formatters.dart';
import '../../core/models.dart';
import '../../core/session.dart';
import '../../core/theme/axis_theme.dart';
import '../../core/widgets/widgets.dart';
import '../trips/domain/segment_offer.dart';
import '../trips/presentation/trip_search_card.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  List<SegmentOffer> _segments = [];
  List<Ticket> _tickets = [];
  TripBanner? _banner;
  SegmentDirection _direction = SegmentDirection.forward;
  bool _segmentsLoading = true;
  String? _segmentsError;
  int _segmentsRequest = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Un seul appel : le serveur renvoie les tronçons du sens choisi, avec prix et prochain départ.
  Future<void> _loadSegments() async {
    final request = ++_segmentsRequest;
    setState(() {
      _segmentsLoading = true;
      _segmentsError = null;
    });
    try {
      final segments = await ref.read(apiClientProvider).segments(_direction);
      if (!mounted || request != _segmentsRequest) return;
      setState(() {
        _segments = segments;
        _segmentsLoading = false;
      });
    } catch (_) {
      if (!mounted || request != _segmentsRequest) return;
      setState(() {
        _segments = [];
        _segmentsLoading = false;
        _segmentsError = 'Impossible de récupérer les trajets pour le moment.';
      });
    }
  }

  void _chooseDirection(SegmentDirection direction) {
    if (direction == _direction) return;
    setState(() {
      _direction = direction;
      _segments = [];
    });
    _loadSegments();
  }

  Future<void> _load() async {
    final api = ref.read(apiClientProvider);
    var tickets = await api.store.readCachedTickets();
    if (mounted) setState(() => _tickets = tickets);
    final segments = _loadSegments();
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
    if (mounted) setState(() => _tickets = tickets);
    await segments;
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final userName = session.user == null
        ? null
        : (session.user!.firstName.isEmpty
              ? session.user!.username
              : session.user!.firstName);

    final sections = _sections(context, userName);

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: AxisSpacing.s24),
        itemCount: sections.length + _segments.length,
        itemBuilder: (context, index) => index < sections.length
            ? sections[index]
            : _SegmentCard(segment: _segments[index - sections.length]),
      ),
    );
  }

  List<Widget> _sections(BuildContext context, String? userName) {
    final theme = Theme.of(context);
    final axis = context.axis;
    return [
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
                    const AxisLogo(),
                    Tooltip(
                      message: 'Notifications',
                      child: Semantics(
                        button: true,
                        label: 'Notifications',
                        child: Material(
                          color: theme.colorScheme.onPrimary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(AxisRadius.small),
                          child: InkWell(
                            onTap: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Aucune notification'),
                                  duration: Duration(seconds: 2),
                                ),
                              );
                            },
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

          // Tronçons du sens choisi : les départs d'une date se voient à la recherche.
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AxisSpacing.screen,
              AxisSpacing.s20,
              AxisSpacing.screen,
              AxisSpacing.s10,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Nos trajets',
                  style: theme.textTheme.titleSmall?.copyWith(color: axis.ink),
                ),
                const SizedBox(height: AxisSpacing.s10),
                SegmentedToggle<SegmentDirection>(
                  options: [
                    for (final direction in SegmentDirection.values)
                      SegmentOption(value: direction, label: direction.label),
                  ],
                  selectedValue: _direction,
                  onChanged: _chooseDirection,
                ),
              ],
            ),
          ),
          if (_segmentsLoading && _segments.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: AxisSpacing.screen),
              child: Column(
                children: [
                  SkeletonBox(height: 84, borderRadius: AxisRadius.card),
                  SizedBox(height: AxisSpacing.s10),
                  SkeletonBox(height: 84, borderRadius: AxisRadius.card),
                  SizedBox(height: AxisSpacing.s10),
                  SkeletonBox(height: 84, borderRadius: AxisRadius.card),
                ],
              ),
            )
          else if (_segmentsError != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AxisSpacing.screen),
              child: EmptyState(
                icon: Icons.wifi_off_rounded,
                title: 'Connexion indisponible',
                description: _segmentsError!,
                actionLabel: 'Réessayer',
                onAction: _loadSegments,
              ),
            )
          else if (_segments.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: AxisSpacing.screen),
              child: EmptyState(
                icon: Icons.directions_bus_outlined,
                title: 'Aucun trajet disponible',
                description: 'Aucun tronçon n’est proposé dans ce sens pour le moment.',
              ),
            ),
    ];
  }
}

class _SegmentCard extends StatelessWidget {
  const _SegmentCard({required this.segment});

  final SegmentOffer segment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final axis = context.axis;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AxisSpacing.screen,
        0,
        AxisSpacing.screen,
        AxisSpacing.s10,
      ),
      child: AxisCard(
        onTap: () => context.push(segment.searchFrom().searchLocation),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    segment.label,
                    style: theme.textTheme.titleMedium?.copyWith(color: axis.ink),
                  ),
                ),
                Text(
                  formatMoney(segment.priceFcfa, 'FCFA'),
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AxisSpacing.s4),
            Text(
              segment.nextDepartureLabel,
              style: theme.textTheme.bodySmall?.copyWith(
                color: axis.textSecondary,
              ),
            ),
          ],
        ),
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
