import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/formatters.dart';
import '../../core/models.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/theme/axis_spacing.dart';
import '../../core/theme/axis_tokens.dart';
import '../../shared/widgets.dart';

class BookingScreen extends ConsumerStatefulWidget {
  const BookingScreen({super.key, required this.tripId});
  final int tripId;

  @override
  ConsumerState<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends ConsumerState<BookingScreen> {
  final _passenger = TextEditingController();
  final _phone = TextEditingController();
  Trip? _trip;
  List<Seat> _seats = [];
  List<PaymentMethod> _methods = [];
  int? _selectedSeat;
  Ticket? _pending;
  bool _loading = true;
  bool _busy = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _passenger.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final api = ref.read(apiClientProvider);
    try {
      final results = await Future.wait([
        api.trips(),
        api.seats(widget.tripId),
        api.paymentMethods(),
      ]);
      final trips = results[0] as List<Trip>;
      try {
        final user = await api.me();
        _passenger.text = user.displayName;
        _phone.text = user.phone;
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _trip = trips.where((item) => item.id == widget.tripId).firstOrNull;
        _seats = results[1] as List<Seat>;
        _methods = (results[2] as List<PaymentMethod>)
            .where((item) => item.active)
            .toList();
        _loading = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _message = error.toString();
        });
      }
    }
  }

  Future<void> _reserve() async {
    if (_selectedSeat == null || _passenger.text.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final ticket = await ref
          .read(apiClientProvider)
          .reserve(
            trip: widget.tripId,
            seat: _selectedSeat!,
            passengerName: _passenger.text.trim(),
            passengerPhone: _phone.text.trim(),
          );
      if (mounted) {
        setState(() {
          _pending = ticket;
          _message = 'Siège bloqué. Finalisez le paiement avant expiration.';
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _message = error.toString());
      if (error.toString().toLowerCase().contains('authent')) {
        context.push('/login');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pay(PaymentMethod method) async {
    final pending = _pending;
    if (pending == null) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final ticket = await ref
          .read(apiClientProvider)
          .pay(pending.id, method.id);
      await ref.read(apiClientProvider).store.upsertTicket(ticket);
      if (mounted) context.go('/billets/ticket/${ticket.id}', extra: ticket);
    } catch (error) {
      if (mounted) setState(() => _message = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final trip = _trip;
    final theme = Theme.of(context);
    final tokens = context.axis;
    return Scaffold(
      appBar: AppBar(title: const Text('Réserver un billet')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 32),
              children: [
                if (trip != null)
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: AxisColors.navy,
                      borderRadius: BorderRadius.circular(AxisRadius.lg),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          trip.route.label,
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: tokens.onDark,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 7),
                        Text(
                          formatFullDateTime(trip.departureAt),
                          style: TextStyle(color: tokens.borderStrong),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          trip.currentFare == null
                              ? 'Tarif à configurer'
                              : formatMoney(trip.currentFare!.amount, 'FCFA'),
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: tokens.borderStrong,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 22),
                Text(
                  '1. Informations du passager',
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: AxisColors.text,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _passenger,
                  onChanged: (_) => setState(() => _selectedSeat = null),
                  decoration: const InputDecoration(
                    labelText: 'Nom du passager',
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Téléphone'),
                ),
                const SizedBox(height: 22),
                Text(
                  '2. Choix du siège',
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: AxisColors.text,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 12),
                if (_passenger.text.trim().isEmpty)
                  const Notice(
                    'Renseignez le passager avant de choisir un siège.',
                  )
                else
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 4,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                        ),
                    itemCount: _seats.length,
                    itemBuilder: (context, index) {
                      final seat = _seats[index];
                      final selected = seat.id == _selectedSeat;
                      return InkWell(
                        onTap: seat.isAvailable
                            ? () => setState(() => _selectedSeat = seat.id)
                            : null,
                        borderRadius: BorderRadius.circular(AxisRadius.sm),
                        child: Container(
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: selected
                                ? AxisColors.navy
                                : seat.isAvailable
                                ? AxisColors.seatIdle
                                : AxisColors.seatTaken,
                            borderRadius: BorderRadius.circular(AxisRadius.sm),
                          ),
                          child: Text(
                            seat.number,
                            style: TextStyle(
                              color: selected
                                  ? tokens.onDark
                                  : seat.isAvailable
                                  ? AxisColors.navy
                                  : tokens.textMuted,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                if (_message != null)
                  Notice(_message!, error: _pending == null),
                const SizedBox(height: 14),
                if (_pending == null)
                  FilledButton(
                    onPressed:
                        _busy ||
                            _selectedSeat == null ||
                            trip?.currentFare == null
                        ? null
                        : _reserve,
                    child: Text(_busy ? 'Patientez…' : 'Réserver ce siège'),
                  )
                else ...[
                  Text(
                    'Paiement de test',
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: AxisColors.text,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  ..._methods.map(
                    (method) => Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: FilledButton(
                        onPressed: _busy ? null : () => _pay(method),
                        child: Text('Payer avec ${method.label}'),
                      ),
                    ),
                  ),
                  if (_methods.isEmpty)
                    const Notice('Aucun moyen de paiement actif.', error: true),
                ],
              ],
            ),
    );
  }
}
