import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/formatters.dart';
import '../../core/models.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';

class TicketsScreen extends ConsumerStatefulWidget {
  const TicketsScreen({super.key});

  @override
  ConsumerState<TicketsScreen> createState() => _TicketsScreenState();
}

class _TicketsScreenState extends ConsumerState<TicketsScreen> {
  List<Trip> _trips = [];
  List<Ticket> _tickets = [];
  bool _authenticated = false;
  bool _loadingTrips = true;
  bool _loadingTickets = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = ref.read(apiClientProvider);
    if (mounted) {
      setState(() {
        _loadingTrips = true;
        _loadingTickets = true;
        _error = null;
      });
    }
    var tickets = await api.store.readCachedTickets();
    if (mounted) {
      setState(() {
        _tickets = tickets;
        _loadingTickets = false;
      });
    }
    try {
      final trips = await api.trips();
      if (mounted) {
        setState(() {
          _trips = trips;
          _loadingTrips = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString();
          _loadingTrips = false;
        });
      }
    }
    var authenticated = false;
    try {
      final user = await api.me();
      authenticated = user.isClient;
      if (authenticated) {
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
        _authenticated = authenticated;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 32),
        children: [
          const Text(
            'BILLETTERIE',
            style: TextStyle(
              color: AxisColors.blue,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.6,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Réserver un billet',
            style: TextStyle(
              color: AxisColors.text,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: () => context.push('/billets/recherche'),
            icon: const Icon(Icons.search),
            label: const Text('Rechercher un trajet'),
          ),
          if (_error != null) Notice(_error!, error: true),
          const SizedBox(height: 14),
          if (_loadingTrips)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_trips.isEmpty)
            const AxisCard(
              child: Text(
                'Aucun départ réservable',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w800),
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
                    Text(
                      trip.route.label,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      formatDateTime(trip.departureAt),
                      style: const TextStyle(
                        color: AxisColors.muted,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 15),
                    Row(
                      children: [
                        Text(
                          '${trip.availableSeats} place(s) libre(s)',
                          style: const TextStyle(
                            color: AxisColors.success,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                        const Spacer(),
                        const Text(
                          'Choisir →',
                          style: TextStyle(
                            color: AxisColors.navy,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 8),
          const Text(
            'Mes billets et QR codes',
            style: TextStyle(
              color: AxisColors.text,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 14),
          if (_loadingTickets)
            const Center(child: CircularProgressIndicator())
          else if (!_authenticated && _tickets.isEmpty)
            AxisCard(
              onTap: () => context.push('/login'),
              child: const Text(
                'Se connecter pour voir mes billets',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            )
          else if (_tickets.isEmpty)
            const AxisCard(
              child: Text(
                'Aucun billet',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w800),
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
                    const SizedBox(height: 6),
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
        ],
      ),
    );
  }
}
