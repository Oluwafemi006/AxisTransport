import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/formatters.dart';
import '../../core/models.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';
import '../bookings/application/booking_checkout.dart';
import '../bookings/application/booking_draft.dart';
import '../bookings/presentation/booking_review_screen.dart';
import '../passengers/domain/passenger.dart';

class TicketsScreen extends ConsumerStatefulWidget {
  const TicketsScreen({super.key});

  @override
  ConsumerState<TicketsScreen> createState() => _TicketsScreenState();
}

class _TicketsScreenState extends ConsumerState<TicketsScreen> {
  List<Trip> _trips = [];
  List<Ticket> _tickets = [];
  List<BookingReservation> _bookings = [];
  bool _authenticated = false;
  bool _loadingTrips = true;
  bool _loadingTickets = true;
  bool _busyBookingAction = false;
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
    var bookings = const <BookingReservation>[];
    try {
      final user = await api.me();
      authenticated = user.isClient;
      if (authenticated) {
        await api.store.setActiveClient(user.id);
        tickets = await api.tickets();
        await api.store.cacheTickets(tickets);
        try {
          bookings = await api.myBookings();
        } catch (_) {
          bookings = const [];
        }
      }
    } catch (_) {
      tickets = await api.store.readCachedTickets();
    }
    if (mounted) {
      setState(() {
        _tickets = tickets;
        _bookings = bookings;
        _authenticated = authenticated;
      });
    }
  }

  Future<void> _cancelBookingFromList(BookingReservation booking) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Annuler la réservation ?'),
        content: const Text('Les places retenues seront libérées immédiatement.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Non'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Oui, annuler'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busyBookingAction = true);
    try {
      await ref.read(apiClientProvider).cancelBooking(bookingId: booking.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Réservation annulée. Les places sont libérées.'),
          ),
        );
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _busyBookingAction = false);
    }
  }

  void _resumeBookingFromList(BookingReservation booking) {
    final trip = booking.tripDetail ??
        (booking.tickets.isNotEmpty ? booking.tickets.first.trip : null);
    if (trip == null) return;
    final passengers = booking.tickets
        .asMap()
        .entries
        .map(
          (entry) => Passenger(
            id: 'passenger-${entry.key + 1}',
            fullName: entry.value.passengerName,
            phone: entry.value.passengerPhone,
            type: PassengerType.adult,
          ),
        )
        .toList();
    ref.read(bookingDraftProvider.notifier).start(
      trip,
      originName: booking.originName,
      destinationName: booking.destinationName,
      segmentLabel: booking.segmentLabel,
    );
    ref.read(bookingDraftProvider.notifier).setPassengers(passengers);
    for (var i = 0; i < booking.tickets.length; i++) {
      final t = booking.tickets[i];
      if (t.seatPreference) {
        ref
            .read(bookingDraftProvider.notifier)
            .assignSeat(passengers[i].id, t.seat);
      }
    }
    ref
        .read(bookingCheckoutProvider.notifier)
        .loadExistingReservation(booking);
    context.push('/billets/booking/${trip.id}/recapitulatif');
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
          if (_authenticated) ...[
            const SizedBox(height: 8),
            const Text(
              'Mes réservations',
              style: TextStyle(
                color: AxisColors.text,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 14),
            if (_bookings.isEmpty)
              const AxisCard(
                child: Text(
                  'Aucune réservation',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              )
            else
              ..._bookings.map((b) {
                final holdValid = b.status == 'HELD' && !b.isExpired;
                final statusLabel = b.status == 'HELD' && b.isExpired
                    ? 'Expirée'
                    : (b.clientStatusDisplay ??
                          (b.status == 'HELD'
                              ? 'En attente de paiement'
                              : b.status == 'CONFIRMED'
                              ? 'Payée'
                              : b.status == 'EXPIRED'
                              ? 'Expirée'
                              : b.status == 'CANCELLED'
                              ? 'Annulée'
                              : b.status == 'REFUND_DUE'
                              ? 'Payée, places indisponibles'
                              : b.statusDisplay));
                final routeLabel =
                    b.segmentLabel ??
                    b.tripDetail?.route.label ??
                    (b.tickets.isNotEmpty
                        ? b.tickets.first.trip.route.label
                        : b.reference);
                final depAt =
                    b.effectiveDepartureAt ??
                    b.tripDetail?.departureAt ??
                    (b.tickets.isNotEmpty
                        ? b.tickets.first.trip.departureAt
                        : null);
                return AxisCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              routeLabel,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: b.isConfirmed
                                  ? const Color(0xFFECFDF3)
                                  : AxisColors.surfaceLow,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              statusLabel,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: b.isConfirmed
                                    ? AxisColors.success
                                    : AxisColors.navy,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Réf. ${b.reference}'
                        '${depAt == null ? '' : ' · ${b.departureLabel ?? 'Départ'} : ${formatDateTime(depAt)}'}',
                        style: const TextStyle(
                          color: AxisColors.muted,
                          fontSize: 12,
                        ),
                      ),
                      if (b.tickets.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          b.tickets
                              .map(
                                (t) => b.isConfirmed
                                    ? '${t.passengerName} (Siège ${t.seat.number})'
                                    : !t.seatPreference
                                    ? '${t.passengerName} (places attribuées après paiement)'
                                    : '${t.passengerName} (Siège ${t.seat.number} — préférence)',
                              )
                              .join(' · '),
                          style: const TextStyle(fontSize: 13),
                        ),
                      ],
                      const SizedBox(height: 6),
                      Text(
                        'Total : ${formatMoney(b.amount, b.currency)}',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      if (holdValid && b.reservationExpiresAt != null) ...[
                        const SizedBox(height: 6),
                        HoldCountdown(expiresAt: b.reservationExpiresAt!),
                      ],
                      if (holdValid) ...[
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton(
                                onPressed: _busyBookingAction
                                    ? null
                                    : () => _resumeBookingFromList(b),
                                child: const Text('Payer'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            OutlinedButton(
                              onPressed: _busyBookingAction
                                  ? null
                                  : () => _cancelBookingFromList(b),
                              child: const Text('Annuler'),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                );
              }),
          ],
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
