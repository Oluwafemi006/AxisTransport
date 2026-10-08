import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models.dart';
import '../../../core/session.dart';
import '../../../core/theme.dart';
import '../../../shared/widgets.dart';
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
    final passenger = draft.passengers.firstWhere(
      (item) => item.id == passengerId,
      orElse: () => draft.passengers.first,
    );
    if (!seat.allowsPassengerType(passenger.type.apiValue)) return;
    ref.read(bookingDraftProvider.notifier).assignSeat(passengerId, seat);
    final updated = ref.read(bookingDraftProvider);
    final next = draft.passengers.where(
      (passenger) => !updated.seatsByPassenger.containsKey(passenger.id),
    );
    setState(() {
      _activePassengerId = next.isEmpty ? passengerId : next.first.id;
    });
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(bookingDraftProvider);
    final passengers = draft.passengers;
    if (draft.trip?.id != widget.tripId || passengers.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Choix des sièges')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: AxisCard(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Renseignez les passagers avant de choisir les sièges.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => context.go(
                      '/billets/booking/${widget.tripId}/passagers',
                    ),
                    child: const Text('Renseigner les passagers'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final active = passengers.firstWhere(
      (item) => item.id == _activePassengerId,
      orElse: () => passengers.first,
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Choix des sièges')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          const _BookingProgress(),
          const SizedBox(height: 20),
          const Text(
            'Attribuez un siège à chaque passager',
            style: TextStyle(
              color: AxisColors.navyDark,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Les informations saisies à l’étape précédente seront contrôlées avec les règles de placement avant confirmation.',
            style: TextStyle(color: AxisColors.muted, height: 1.4),
          ),
          const SizedBox(height: 16),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: passengers.map((passenger) {
                final seat = draft.seatsByPassenger[passenger.id];
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    selected: passenger.id == active.id,
                    avatar: Icon(
                      seat == null ? Icons.person_outline : Icons.check_circle,
                      size: 17,
                      color: seat == null
                          ? AxisColors.muted
                          : AxisColors.success,
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
          if (_error != null) Notice(_error!, error: true),
          const SizedBox(height: 18),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_seats.isEmpty)
            const AxisCard(
              child: Text(
                'Aucun siège disponible.',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            )
          else ...[
            _SeatLegend(activeName: active.fullName),
            const SizedBox(height: 12),
            _SeatMap(
              seats: _seats,
              activePassenger: active,
              assignments: draft.seatsByPassenger,
              onSelect: _assign,
            ),
          ],
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: draft.hasAllSeats
                ? () => context.push(
                    '/billets/booking/${widget.tripId}/recapitulatif',
                  )
                : null,
            icon: const Icon(Icons.receipt_long_outlined),
            label: Text(
              draft.hasAllSeats
                  ? 'Voir le récapitulatif'
                  : '${draft.seatsByPassenger.length}/${passengers.length} siège(s) attribué(s)',
            ),
          ),
        ],
      ),
    );
  }
}

class _BookingProgress extends StatelessWidget {
  const _BookingProgress();

  @override
  Widget build(BuildContext context) => Row(
    children: List.generate(3, (index) {
      return Expanded(
        child: Container(
          height: 4,
          margin: EdgeInsets.only(right: index == 2 ? 0 : 6),
          decoration: BoxDecoration(
            color: index < 2 ? AxisColors.navy : AxisColors.border,
            borderRadius: BorderRadius.circular(99),
          ),
        ),
      );
    }),
  );
}

class _SeatLegend extends StatelessWidget {
  const _SeatLegend({required this.activeName});

  final String activeName;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 14,
    runSpacing: 8,
    children: [
      const _LegendItem(color: AxisColors.seatIdle, label: 'Libre'),
      const _LegendItem(color: AxisColors.seatTaken, label: 'Indisponible'),
      const _LegendItem(color: AxisColors.border, label: 'Non adapté'),
      _LegendItem(color: AxisColors.red, label: 'Pour $activeName'),
      const _LegendItem(color: AxisColors.navy, label: 'Déjà attribué'),
    ],
  );
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(3),
        ),
      ),
      const SizedBox(width: 5),
      Text(
        label,
        style: const TextStyle(fontSize: 11, color: AxisColors.muted),
      ),
    ],
  );
}

class _SeatMap extends StatelessWidget {
  const _SeatMap({
    required this.seats,
    required this.activePassenger,
    required this.assignments,
    required this.onSelect,
  });

  final List<Seat> seats;
  final Passenger activePassenger;
  final Map<String, Seat> assignments;
  final ValueChanged<Seat> onSelect;

  List<List<Seat>> get _rows {
    final ordered = [...seats]
      ..sort((a, b) {
        final byRow = (a.row ?? 9999).compareTo(b.row ?? 9999);
        if (byRow != 0) return byRow;
        final byColumn = (a.column ?? 9999).compareTo(b.column ?? 9999);
        return byColumn != 0 ? byColumn : a.number.compareTo(b.number);
      });
    if (ordered.any((seat) => seat.row != null)) {
      final grouped = <int, List<Seat>>{};
      for (final seat in ordered) {
        grouped.putIfAbsent(seat.row ?? 9999, () => []).add(seat);
      }
      return grouped.values.toList();
    }
    return [
      for (var index = 0; index < ordered.length; index += 4)
        ordered.sublist(index, (index + 4).clamp(0, ordered.length)),
    ];
  }

  @override
  Widget build(BuildContext context) => AxisCard(
    child: Column(
      children: [
        const Row(
          children: [
            Icon(Icons.airline_seat_recline_normal, color: AxisColors.muted),
            Spacer(),
            Text(
              'AVANT DU VÉHICULE',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800),
            ),
          ],
        ),
        const Divider(height: 26),
        ..._rows.map((row) {
          final left = row.take(2).toList();
          final right = row.skip(2).take(2).toList();
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                ...left.map((seat) => Expanded(child: _seatButton(seat))),
                const SizedBox(width: 28),
                ...right.map((seat) => Expanded(child: _seatButton(seat))),
                if (right.length < 2)
                  ...List.generate(
                    2 - right.length,
                    (_) => const Expanded(child: SizedBox()),
                  ),
              ],
            ),
          );
        }),
      ],
    ),
  );

  Widget _seatButton(Seat seat) {
    String? assignedTo;
    for (final entry in assignments.entries) {
      if (entry.value.id == seat.id) assignedTo = entry.key;
    }
    final allowedForActive = seat.allowsPassengerType(
      activePassenger.type.apiValue,
    );
    final active = assignedTo == activePassenger.id;
    final assignedElsewhere = assignedTo != null && !active;
    final enabled = seat.isAvailable && !assignedElsewhere && allowedForActive;
    final color = active
        ? AxisColors.red
        : assignedElsewhere
        ? AxisColors.navy
        : !allowedForActive
        ? AxisColors.border
        : seat.isAvailable
        ? AxisColors.seatIdle
        : AxisColors.seatTaken;
    final foreground = active || assignedElsewhere
        ? Colors.white
        : AxisColors.navyDark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Semantics(
        button: true,
        enabled: enabled,
        label: allowedForActive
            ? 'Siège ${seat.number}'
            : 'Siège ${seat.number} non adapté',
        child: InkWell(
          onTap: enabled ? () => onSelect(seat) : null,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              seat.number,
              style: TextStyle(color: foreground, fontWeight: FontWeight.w900),
            ),
          ),
        ),
      ),
    );
  }
}
