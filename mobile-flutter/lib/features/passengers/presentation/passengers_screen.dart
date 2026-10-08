import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/formatters.dart';
import '../../../core/models.dart';
import '../../../core/session.dart';
import '../../../core/theme.dart';
import '../../../shared/widgets.dart';
import '../../bookings/application/booking_draft.dart';
import '../domain/passenger.dart';

class PassengersScreen extends ConsumerStatefulWidget {
  const PassengersScreen({
    super.key,
    required this.tripId,
    this.passengerCount = 1,
  });

  final int tripId;
  final int passengerCount;

  @override
  ConsumerState<PassengersScreen> createState() => _PassengersScreenState();
}

class _PassengersScreenState extends ConsumerState<PassengersScreen> {
  final _formKey = GlobalKey<FormState>();
  late final List<TextEditingController> _names;
  late final List<TextEditingController> _phones;
  late final List<PassengerType> _types;
  Trip? _trip;
  bool _loading = true;
  String? _error;

  int get _count => widget.passengerCount.clamp(1, 8);

  @override
  void initState() {
    super.initState();
    _names = List.generate(_count, (_) => TextEditingController());
    _phones = List.generate(_count, (_) => TextEditingController());
    _types = List.generate(_count, (_) => PassengerType.adult);
    _load();
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
    try {
      final trip = await api.trip(widget.tripId);
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
      ref.read(bookingDraftProvider.notifier).start(trip);
      if (!mounted) return;
      setState(() {
        _trip = trip;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Connexion nécessaire pour préparer cette réservation.';
      });
    }
  }

  void _continue() {
    if (!_formKey.currentState!.validate() || _trip == null) return;
    final passengers = List.generate(
      _count,
      (index) => Passenger(
        id: 'passenger-${index + 1}',
        fullName: _names[index].text.trim(),
        phone: _phones[index].text.trim(),
        type: _types[index],
      ),
    );
    ref.read(bookingDraftProvider.notifier).setPassengers(passengers);
    context.push('/billets/booking/${widget.tripId}/sieges');
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
                    _TripSummary(trip: trip),
                  ],
                  if (_error != null) Notice(_error!, error: true),
                  const SizedBox(height: 22),
                  const Text(
                    'Qui voyage ?',
                    style: TextStyle(
                      color: AxisColors.navyDark,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Ces informations servent à appliquer les règles de placement avant le choix des sièges.',
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
                            Text(
                              'Passager ${index + 1}',
                              style: const TextStyle(
                                color: AxisColors.navyDark,
                                fontSize: 17,
                                fontWeight: FontWeight.w900,
                              ),
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
            borderRadius: BorderRadius.circular(99),
          ),
        ),
      );
    }),
  );
}

class _TripSummary extends StatelessWidget {
  const _TripSummary({required this.trip});

  final Trip trip;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AxisColors.navy,
      borderRadius: BorderRadius.circular(18),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          trip.route.label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          formatFullDateTime(trip.departureAt),
          style: const TextStyle(color: Color(0xFFD3E4FE)),
        ),
      ],
    ),
  );
}
