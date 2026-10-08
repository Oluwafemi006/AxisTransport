import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/formatters.dart';
import '../../core/models.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';
import '../trips/presentation/trip_search_card.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  List<Trip> _trips = [];
  List<Ticket> _tickets = [];
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
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 40),
        children: [
          Row(
            children: [
              const Brand(),
              const Spacer(),
              TextButton(
                onPressed: () => session.user == null
                    ? context.push('/login')
                    : context.go('/profil'),
                child: Text(
                  session.user?.displayName ?? 'Se connecter',
                  style: const TextStyle(
                    color: AxisColors.navy,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            session.user == null
                ? 'Bonjour 👋'
                : 'Bonjour ${session.user!.firstName.isEmpty ? session.user!.username : session.user!.firstName} 👋',
            style: const TextStyle(
              color: AxisColors.navy,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Où souhaitez-vous aller ?',
            style: TextStyle(
              color: AxisColors.navyDark,
              fontSize: 26,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 5),
          const Text(
            'Réservez votre trajet en toute sérénité.',
            style: TextStyle(color: AxisColors.muted),
          ),
          const SizedBox(height: 18),
          const TripSearchCard(),
          if (_error != null) Notice(_error!, error: true),
          const SizedBox(height: 24),
          const Text(
            'Départs disponibles',
            style: TextStyle(
              color: AxisColors.text,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_trips.isEmpty)
            AxisCard(
              child: Column(
                children: const [
                  Text(
                    'Aucun départ publié',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: AxisColors.text,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Les départs apparaîtront dès qu’ils seront publiés.',
                    style: TextStyle(color: AxisColors.muted),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          else
            ..._trips.map(
              (trip) => AxisCard(
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
                            style: const TextStyle(
                              color: AxisColors.text,
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        Text(
                          trip.currentFare == null
                              ? 'À configurer'
                              : formatMoney(trip.currentFare!.amount, 'F'),
                          style: const TextStyle(
                            color: AxisColors.navy,
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      formatDateTime(trip.departureAt),
                      style: const TextStyle(
                        color: AxisColors.muted,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Text(
                          '${trip.availableSeats} place(s) libre(s)',
                          style: const TextStyle(
                            color: AxisColors.success,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const Spacer(),
                        const Text(
                          'Réserver →',
                          style: TextStyle(
                            color: AxisColors.navy,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                    if (trip.isDemo) ...[
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF5D8),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'Données de démonstration non validées',
                          style: TextStyle(
                            color: AxisColors.warning,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          const SizedBox(height: 12),
          const Text(
            'Mes billets',
            style: TextStyle(
              color: AxisColors.text,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          if (session.user == null && _tickets.isEmpty)
            AxisCard(
              onTap: () => context.push('/login'),
              child: const Column(
                children: [
                  Text(
                    'Connectez-vous pour retrouver vos billets',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: AxisColors.text,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Votre session sera stockée de manière sécurisée.',
                    style: TextStyle(color: AxisColors.muted),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          else if (_tickets.isEmpty)
            const AxisCard(
              child: Text(
                'Aucun billet',
                style: TextStyle(fontWeight: FontWeight.w800),
                textAlign: TextAlign.center,
              ),
            )
          else
            ..._tickets.map(
              (ticket) => AxisCard(
                onTap: () =>
                    context.push('/billets/ticket/${ticket.id}', extra: ticket),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ticket.reference,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${ticket.trip.route.label} · siège ${ticket.seat.number}',
                      style: const TextStyle(
                        color: AxisColors.muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 22),
          const Text(
            'Autres services',
            style: TextStyle(
              color: AxisColors.navyDark,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _ServiceShortcut(
                  label: 'Colis',
                  icon: Icons.inventory_2_outlined,
                  onTap: () => context.go('/colis'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ServiceShortcut(
                  label: 'Location',
                  icon: Icons.directions_car_outlined,
                  onTap: () => context.go('/location'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ServiceShortcut extends StatelessWidget {
  const _ServiceShortcut({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(16),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
        child: Column(
          children: [
            Icon(icon, color: AxisColors.navy),
            const SizedBox(height: 7),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AxisColors.navyDark,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
