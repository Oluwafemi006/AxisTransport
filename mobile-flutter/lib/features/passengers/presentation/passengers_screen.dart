import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/formatters.dart';
import '../../../core/api_client.dart';
import '../../../core/models.dart';
import '../../../core/session.dart';
import '../../../core/theme.dart';
import '../../../core/theme/axis_spacing.dart';
import '../../../core/theme/axis_tokens.dart';
import '../../../shared/widgets.dart';
import '../../bookings/application/booking_draft.dart';
import '../domain/passenger.dart';

class PassengersScreen extends ConsumerStatefulWidget {
  const PassengersScreen({
    super.key,
    required this.tripId,
    this.passengerCount = 1,
    this.originId,
    this.destinationId,
  });

  final int tripId;
  final int passengerCount;
  final int? originId;
  final int? destinationId;

  @override
  ConsumerState<PassengersScreen> createState() => _PassengersScreenState();
}

class _PassengersScreenState extends ConsumerState<PassengersScreen> {
  final _formKey = GlobalKey<FormState>();
  late final List<TextEditingController> _names;
  late final List<TextEditingController> _phones;
  late final List<PassengerType> _types;
  late int _count;
  Trip? _trip;
  int? _originId;
  int? _destinationId;
  int? _boardingPointId;
  int? _alightingPointId;
  bool _loading = true;
  String? _error;

  List<BoardingPointInfo> _pointsFor(Trip trip, int? locationId, {required bool isOrigin}) {
    if (locationId != null) {
      final stop = trip.route.stops.where((s) => s.id == locationId).firstOrNull;
      if (stop != null && stop.boardingPoints.isNotEmpty) {
        return stop.boardingPoints.where((p) => p.active).toList();
      }
      if (trip.route.origin?.id == locationId) {
        return (trip.route.origin?.boardingPoints ?? const []).where((p) => p.active).toList();
      }
      if (trip.route.destination?.id == locationId) {
        return (trip.route.destination?.boardingPoints ?? const []).where((p) => p.active).toList();
      }
    }
    final fallback = isOrigin ? trip.route.origin : trip.route.destination;
    return (fallback?.boardingPoints ?? const []).where((p) => p.active).toList();
  }

  @override
  void initState() {
    super.initState();
    final draft = ref.read(bookingDraftProvider);
    _count = (draft.trip?.id == widget.tripId && draft.passengers.isNotEmpty)
        ? draft.passengers.length
        : widget.passengerCount.clamp(1, 8);
    _names = List.generate(_count, (_) => TextEditingController());
    _phones = List.generate(_count, (_) => TextEditingController());
    _types = List.generate(_count, (_) => PassengerType.adult);
    _load();
  }

  void _addPassenger() {
    if (_count >= 8) return;
    setState(() {
      _count++;
      _names.add(TextEditingController());
      _phones.add(TextEditingController());
      _types.add(PassengerType.adult);
    });
  }

  void _removePassenger(int index) {
    if (_count <= 1) return;
    setState(() {
      _names[index].dispose();
      _names.removeAt(index);
      _phones[index].dispose();
      _phones.removeAt(index);
      _types.removeAt(index);
      _count--;
    });
  }

  @override
  void dispose() {
    for (final controller in [..._names, ..._phones]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final api = ref.read(apiClientProvider);
    final startDraft = ref.read(bookingDraftProvider);
    try {
      // Avec le tronçon choisi, le serveur renvoie son tarif (sinon celui du parcours entier).
      final trip = await api.trip(
        widget.tripId,
        originId: widget.originId ?? startDraft.originId,
        destinationId: widget.destinationId ?? startDraft.destinationId,
      );
      final draft = ref.read(bookingDraftProvider);
      if (draft.trip?.id == trip.id && draft.passengers.length == _count) {
        for (var index = 0; index < _count; index++) {
          _names[index].text = draft.passengers[index].fullName;
          _phones[index].text = draft.passengers[index].phone;
          _types[index] = draft.passengers[index].type;
        }
      } else {
        try {
          final user = await api.me();
          _names.first.text = user.displayName;
          _phones.first.text = user.phone;
        } catch (_) {
          // Guest booking starts with an empty passenger form.
        }
      }
      final origId = widget.originId ?? draft.originId ?? trip.route.origin?.id;
      final destId = widget.destinationId ?? draft.destinationId ?? trip.route.destination?.id;
      final origStop = origId == null ? null : trip.route.stops.where((s) => s.id == origId).firstOrNull;
      final destStop = destId == null ? null : trip.route.stops.where((s) => s.id == destId).firstOrNull;
      final oName = origStop?.name ?? trip.route.origin?.name;
      final dName = destStop?.name ?? trip.route.destination?.name;
      String? segLabel;
      if (oName != null && dName != null) {
        segLabel = '$oName → $dName';
      }
      final origPoints = _pointsFor(trip, origId, isOrigin: true);
      final destPoints = _pointsFor(trip, destId, isOrigin: false);
      int? initialBoardingId;
      if (origPoints.length == 1) {
        initialBoardingId = origPoints.first.id;
      } else if (origPoints.length > 1 && origPoints.any((p) => p.id == draft.boardingPointId)) {
        initialBoardingId = draft.boardingPointId;
      }
      int? initialAlightingId;
      if (destPoints.length == 1) {
        initialAlightingId = destPoints.first.id;
      } else if (destPoints.length > 1 && destPoints.any((p) => p.id == draft.alightingPointId)) {
        initialAlightingId = draft.alightingPointId;
      }
      ref.read(bookingDraftProvider.notifier).start(
        trip,
        originId: origId,
        destinationId: destId,
        originName: oName,
        destinationName: dName,
        segmentLabel: segLabel,
      );
      ref.read(bookingDraftProvider.notifier).setBoardingPoints(
        boardingPointId: initialBoardingId,
        boardingPointName: origPoints.where((p) => p.id == initialBoardingId).firstOrNull?.name,
        alightingPointId: initialAlightingId,
        alightingPointName: destPoints.where((p) => p.id == initialAlightingId).firstOrNull?.name,
      );
      if (!mounted) return;
      setState(() {
        _trip = trip;
        _originId = origId;
        _destinationId = destId;
        _boardingPointId = initialBoardingId;
        _alightingPointId = initialAlightingId;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error is ApiException && error.isSegmentFareMissing
            ? error.message
            : 'Connexion nécessaire pour préparer cette réservation.';
      });
    }
  }

  void _continue() {
    if (!_formKey.currentState!.validate() || _trip == null) return;
    final trip = _trip!;
    final origPoints = _pointsFor(trip, _originId, isOrigin: true);
    final destPoints = _pointsFor(trip, _destinationId, isOrigin: false);
    final passengers = List.generate(
      _count,
      (index) => Passenger(
        id: 'passenger-${index + 1}',
        fullName: _names[index].text.trim(),
        phone: _phones[index].text.trim(),
        type: _types[index],
      ),
    );
    ref.read(bookingDraftProvider.notifier).setBoardingPoints(
      boardingPointId: _boardingPointId,
      boardingPointName: origPoints.where((p) => p.id == _boardingPointId).firstOrNull?.name,
      alightingPointId: _alightingPointId,
      alightingPointName: destPoints.where((p) => p.id == _alightingPointId).firstOrNull?.name,
    );
    ref.read(bookingDraftProvider.notifier).setPassengers(passengers);
    context.push('/billets/booking/${widget.tripId}/sieges');
  }

  List<Widget> _buildBoardingPointSelectors(Trip trip) {
    final origPoints = _pointsFor(trip, _originId, isOrigin: true);
    final destPoints = _pointsFor(trip, _destinationId, isOrigin: false);
    if (origPoints.isEmpty && destPoints.isEmpty) return const [];
    final origStop = _originId == null ? null : trip.route.stops.where((s) => s.id == _originId).firstOrNull;
    final destStop = _destinationId == null ? null : trip.route.stops.where((s) => s.id == _destinationId).firstOrNull;
    final origName = origStop?.name ?? trip.route.origin?.name ?? '';
    final destName = destStop?.name ?? trip.route.destination?.name ?? '';
    return [
      const SizedBox(height: 14),
      AxisCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Points d\'embarquement et de débarquement',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: AxisColors.navyDark,
                fontWeight: FontWeight.w900,
              ),
            ),
            if (origPoints.isNotEmpty) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: _boardingPointId,
                decoration: InputDecoration(
                  labelText: 'Embarquement ($origName)',
                ),
                items: origPoints
                    .map(
                      (p) => DropdownMenuItem<int>(
                        value: p.id,
                        child: Text(p.name),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() => _boardingPointId = value),
                validator: origPoints.length > 1
                    ? (value) => value == null ? 'Veuillez choisir un point d\'embarquement.' : null
                    : null,
              ),
            ],
            if (destPoints.isNotEmpty) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: _alightingPointId,
                decoration: InputDecoration(
                  labelText: 'Débarquement ($destName)',
                ),
                items: destPoints
                    .map(
                      (p) => DropdownMenuItem<int>(
                        value: p.id,
                        child: Text(p.name),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() => _alightingPointId = value),
                validator: destPoints.length > 1
                    ? (value) => value == null ? 'Veuillez choisir un point de débarquement.' : null
                    : null,
              ),
            ],
          ],
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final trip = _trip;
    return Scaffold(
      appBar: AppBar(title: const Text('Informations des passagers')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                children: [
                  const _BookingProgress(currentStep: 1),
                  if (trip != null) ...[
                    const SizedBox(height: 18),
                    _TripSummary(
                      trip: trip,
                      segmentLabel: ref.watch(
                        bookingDraftProvider.select((d) => d.segmentLabel),
                      ),
                    ),
                    ..._buildBoardingPointSelectors(trip),
                  ],
                  if (_error != null) Notice(_error!, error: true),
                  const SizedBox(height: 22),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Qui voyage ?',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: AxisColors.navyDark,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AxisColors.surfaceLow,
                          borderRadius: BorderRadius.circular(AxisRadius.sm),
                        ),
                        child: Text(
                          '$_count passager${_count > 1 ? "s" : ""}',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AxisColors.navy,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Ces informations servent à attribuer les billets et préparer le placement.',
                    style: TextStyle(color: AxisColors.muted, height: 1.4),
                  ),
                  const SizedBox(height: 16),
                  ...List.generate(
                    _count,
                    (index) => Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: AxisCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Passager ${index + 1}',
                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    color: AxisColors.navyDark,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                if (index > 0)
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, color: AxisColors.red, size: 22),
                                    tooltip: 'Supprimer ce passager',
                                    onPressed: () => _removePassenger(index),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            SegmentedButton<PassengerType>(
                              segments: PassengerType.values
                                  .map(
                                    (type) => ButtonSegment(
                                      value: type,
                                      label: Text(type.label),
                                    ),
                                  )
                                  .toList(),
                              selected: {_types[index]},
                              onSelectionChanged: (value) =>
                                  setState(() => _types[index] = value.single),
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              key: Key('passenger-name-$index'),
                              controller: _names[index],
                              textCapitalization: TextCapitalization.words,
                              decoration: const InputDecoration(
                                labelText: 'Nom complet',
                              ),
                              validator: (value) =>
                                  value == null || value.trim().length < 2
                                  ? 'Saisissez le nom complet.'
                                  : null,
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              key: Key('passenger-phone-$index'),
                              controller: _phones[index],
                              keyboardType: TextInputType.phone,
                              decoration: InputDecoration(
                                labelText: index == 0
                                    ? 'Téléphone de contact'
                                    : 'Téléphone (facultatif)',
                              ),
                              validator: index == 0
                                  ? (value) =>
                                        value == null || value.trim().length < 6
                                        ? 'Saisissez un téléphone de contact.'
                                        : null
                                  : null,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (_count < 8) ...[
                    OutlinedButton.icon(
                      onPressed: _addPassenger,
                      icon: const Icon(Icons.person_add_outlined),
                      label: const Text('Ajouter un passager'),
                    ),
                    const SizedBox(height: 14),
                  ],
                  FilledButton.icon(
                    onPressed: trip == null ? null : _continue,
                    icon: const Icon(Icons.airline_seat_recline_normal),
                    label: const Text('Continuer vers les sièges'),
                  ),
                ],
              ),
            ),
    );
  }
}

class _BookingProgress extends StatelessWidget {
  const _BookingProgress({required this.currentStep});

  final int currentStep;

  @override
  Widget build(BuildContext context) => Row(
    children: List.generate(3, (index) {
      final step = index + 1;
      return Expanded(
        child: Container(
          height: 4,
          margin: EdgeInsets.only(right: index == 2 ? 0 : 6),
          decoration: BoxDecoration(
            color: step <= currentStep ? AxisColors.navy : AxisColors.border,
            borderRadius: BorderRadius.circular(AxisRadius.pill),
          ),
        ),
      );
    }),
  );
}

class _TripSummary extends StatelessWidget {
  const _TripSummary({required this.trip, this.segmentLabel});

  final Trip trip;

  /// Tronçon choisi par le client ; à défaut, le parcours entier.
  final String? segmentLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.axis;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AxisColors.navy,
        borderRadius: BorderRadius.circular(AxisRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            segmentLabel ?? trip.route.label,
            style: theme.textTheme.titleLarge?.copyWith(
              color: tokens.onDark,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            formatFullDateTime(trip.departureAt),
            style: TextStyle(color: tokens.borderStrong),
          ),
        ],
      ),
    );
  }
}
