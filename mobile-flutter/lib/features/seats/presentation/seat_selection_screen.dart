import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/formatters.dart';
import '../../../core/models.dart';
import '../../../core/session.dart';
import '../../../core/theme/axis_theme.dart';
import '../../../core/widgets/widgets.dart';
import '../../bookings/application/booking_draft.dart';
import '../../passengers/domain/passenger.dart';

class SeatSelectionScreen extends ConsumerStatefulWidget {
  const SeatSelectionScreen({super.key, required this.tripId});

  final int tripId;

  @override
  ConsumerState<SeatSelectionScreen> createState() =>
      _SeatSelectionScreenState();
}

class _SeatSelectionScreenState extends ConsumerState<SeatSelectionScreen> {
  List<Seat> _seats = [];
  String? _activePassengerId;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    final draft = ref.read(bookingDraftProvider);
    if (draft.trip?.id == widget.tripId && draft.passengers.isNotEmpty) {
      _activePassengerId = draft.passengers
          .firstWhere(
            (passenger) => !draft.seatsByPassenger.containsKey(passenger.id),
            orElse: () => draft.passengers.first,
          )
          .id;
    }
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final seats = await ref.read(apiClientProvider).seats(widget.tripId);
      if (!mounted) return;
      setState(() {
        _seats = seats;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Connexion nécessaire pour connaître les sièges disponibles.';
      });
    }
  }

  void _assign(Seat seat) {
    final passengerId = _activePassengerId;
    if (passengerId == null) return;
    final draft = ref.read(bookingDraftProvider);
    final currentlyAssigned = draft.seatsByPassenger[passengerId];
    if (currentlyAssigned?.id == seat.id) {
      ref.read(bookingDraftProvider.notifier).unassignSeat(passengerId);
      return;
    }
    // Si ce siège est déjà attribué à un autre passager de la même réservation, on l'ignore.
    final assignedToOther = draft.seatsByPassenger.entries.any(
      (entry) => entry.key != passengerId && entry.value.id == seat.id,
    );
    if (assignedToOther) return;

    final passenger = draft.passengers.firstWhere(
      (item) => item.id == passengerId,
      orElse: () => draft.passengers.first,
    );
    if (!seat.isAvailable || !seat.allowsPassengerType(passenger.type.apiValue)) {
      return;
    }
    ref.read(bookingDraftProvider.notifier).assignSeat(passengerId, seat);
    final updated = ref.read(bookingDraftProvider);
    final next = draft.passengers.where(
      (passenger) => !updated.seatsByPassenger.containsKey(passenger.id),
    );
    setState(() {
      _activePassengerId = next.isEmpty ? passengerId : next.first.id;
    });
  }

  void _onSeatNumberSelected(String number) {
    final seat = _seats.where((item) => item.number == number).firstOrNull;
    if (seat != null) {
      _assign(seat);
    }
  }

  List<SeatRowData> _buildSeatRows(
    Passenger activePassenger,
    Map<String, Seat> assignments,
  ) {
    final ordered = [..._seats]..sort(_compareSeats);
    final groupedRows = <List<Seat>>[];

    if (ordered.any((seat) => seat.row != null)) {
      final grouped = <int, List<Seat>>{};
      for (final seat in ordered) {
        grouped.putIfAbsent(seat.row ?? 9999, () => []).add(seat);
      }
      groupedRows.addAll(grouped.values);
    } else {
      for (var i = 0; i < ordered.length; i += 4) {
        groupedRows.add(
          ordered.sublist(i, (i + 4).clamp(0, ordered.length)),
        );
      }
    }

    SeatCellData toCell(Seat seat) {
      final isAssigned = assignments.values.any((s) => s.id == seat.id);
      final allowed = seat.allowsPassengerType(activePassenger.type.apiValue);
      final SeatStatus status;
      if (isAssigned) {
        status = SeatStatus.selected;
      } else if (!seat.isAvailable || !allowed) {
        status = SeatStatus.taken;
      } else {
        status = SeatStatus.free;
      }
      return SeatCellData.seat(number: seat.number, status: status);
    }

    return groupedRows.map((rowSeats) {
      if (rowSeats.length == 5) {
        return SeatRowData(rowSeats.map(toCell).toList());
      }
      final left = rowSeats.take(2).map(toCell).toList();
      final right = rowSeats.skip(2).take(2).map(toCell).toList();
      return SeatRowData([
        ...left,
        if (right.isNotEmpty) const SeatCellData.aisle(),
        ...right,
      ]);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(bookingDraftProvider);
    final passengers = draft.passengers;
    final trip = draft.trip;
    final theme = Theme.of(context);
    final axis = context.axis;

    if (trip?.id != widget.tripId || passengers.isEmpty) {
      return Scaffold(
        body: Column(
          children: [
            AxisHeader(
              title: 'Choisissez votre siège',
              onBack: () => context.canPop()
                  ? context.pop()
                  : context.go('/billets/booking/${widget.tripId}/passagers'),
            ),
            Expanded(
              child: EmptyState(
                icon: Icons.person_outline_rounded,
                title: 'Passagers non renseignés',
                description:
                    'Renseignez les passagers avant de choisir les sièges.',
                actionLabel: 'Renseigner les passagers',
                onAction: () => context.go(
                  '/billets/booking/${widget.tripId}/passagers',
                ),
              ),
            ),
          ],
        ),
      );
    }

    final active = passengers.firstWhere(
      (item) => item.id == _activePassengerId,
      orElse: () => passengers.first,
    );
    final selectedSeats = draft.seatsByPassenger.values.toList();
    final selectionSummary = selectedSeats.isEmpty
        ? 'Aucun siège choisi'
        : 'Siège${selectedSeats.length > 1 ? 's' : ''} ${selectedSeats.map((s) => s.number).join(', ')} · ${passengers.length} passager${passengers.length > 1 ? 's' : ''}';
    final currency = trip!.currentFare?.currency ?? 'XOF';

    return Scaffold(
      body: Column(
        children: [
          // En-tête blanc (Siege.html)
          Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border(bottom: BorderSide(color: axis.border)),
            ),
            padding: const EdgeInsets.fromLTRB(
              AxisSpacing.screen,
              AxisSpacing.s12,
              AxisSpacing.screen,
              AxisSpacing.s12,
            ),
            child: Row(
              children: [
                Tooltip(
                  message: 'Retour',
                  child: Semantics(
                    button: true,
                    label: 'Retour',
                    child: Material(
                      color: axis.inputFill,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AxisRadius.small),
                        side: BorderSide(color: axis.border),
                      ),
                      child: InkWell(
                        onTap: () => context.canPop()
                            ? context.pop()
                            : context.go(
                                '/billets/booking/${widget.tripId}/passagers',
                              ),
                        borderRadius: BorderRadius.circular(AxisRadius.small),
                        child: SizedBox(
                          width: AxisSizes.minTarget,
                          height: AxisSizes.minTarget,
                          child: Icon(
                            Icons.arrow_back_rounded,
                            color: axis.ink,
                            size: AxisSizes.icon,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AxisSpacing.s10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Choisissez votre siège',
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: axis.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${draft.segmentLabel ?? trip.route.label} · ${formatDateTime(trip.departureAt)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: axis.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Contenu principal avec sélection du passager et SeatMap
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AxisSpacing.screen,
                AxisSpacing.s14,
                AxisSpacing.screen,
                AxisSpacing.s24,
              ),
              children: [
                // Sélecteur de passager
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: passengers.map((passenger) {
                      final seat = draft.seatsByPassenger[passenger.id];
                      final isSelectedPassenger = passenger.id == active.id;
                      return Padding(
                        padding: const EdgeInsets.only(right: AxisSpacing.s8),
                        child: ChoiceChip(
                          selected: isSelectedPassenger,
                          avatar: Icon(
                            seat == null
                                ? Icons.person_outline_rounded
                                : Icons.check_circle_rounded,
                            size: 16,
                            color: seat == null
                                ? axis.textMuted
                                : axis.success,
                          ),
                          label: Text(
                            seat == null
                                ? passenger.fullName
                                : '${passenger.fullName} · ${seat.number}',
                          ),
                          onSelected: (_) =>
                              setState(() => _activePassengerId = passenger.id),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: AxisSpacing.s14),

                if (_loading)
                  const Column(
                    children: [
                      SkeletonBox(height: 28, borderRadius: AxisRadius.small),
                      SizedBox(height: AxisSpacing.s14),
                      SkeletonBox(height: 320, borderRadius: AxisRadius.card),
                    ],
                  )
                else if (_error != null)
                  EmptyState(
                    icon: Icons.wifi_off_rounded,
                    title: 'Plan de sièges indisponible',
                    description: _error!,
                    actionLabel: 'Réessayer',
                    onAction: _load,
                  )
                else if (_seats.isEmpty)
                  EmptyState(
                    icon: Icons.event_seat_outlined,
                    title: 'Aucun siège disponible.',
                    description:
                        'Aucun siège n’est disponible pour ce trajet.',
                    actionLabel: 'Réessayer',
                    onAction: _load,
                  )
                else
                  SeatMap(
                    rows: _buildSeatRows(active, draft.seatsByPassenger),
                    onSeatSelected: _onSeatNumberSelected,
                  ),
              ],
            ),
          ),

          // Barre inférieure de validation (Siege.html)
          Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border(top: BorderSide(color: axis.border)),
            ),
            padding: const EdgeInsets.fromLTRB(
              AxisSpacing.screen,
              AxisSpacing.s12,
              AxisSpacing.screen,
              AxisSpacing.s16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'SÉLECTION',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: axis.textMuted,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            selectionSummary,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: axis.ink,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AxisSpacing.s12),
                    Text(
                      formatMoney(draft.totalAmount, currency),
                      style: AxisTypography.price.copyWith(color: axis.ink),
                    ),
                  ],
                ),
                const SizedBox(height: AxisSpacing.s10),
                AxisButton(
                  onPressed: () => context.push(
                    '/billets/booking/${widget.tripId}/recapitulatif',
                  ),
                  label: 'Continuer',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

int _compareSeats(Seat a, Seat b) {
  final byRow = (a.row ?? 9999).compareTo(b.row ?? 9999);
  if (byRow != 0) return byRow;
  final byColumn = (a.column ?? 9999).compareTo(b.column ?? 9999);
  if (byColumn != 0) return byColumn;
  final numA = int.tryParse(a.number);
  final numB = int.tryParse(b.number);
  if (numA != null && numB != null) return numA.compareTo(numB);
  return a.number.compareTo(b.number);
}
