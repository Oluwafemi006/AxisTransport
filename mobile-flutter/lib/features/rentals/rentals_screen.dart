import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/benin_time.dart';
import '../../core/formatters.dart';
import '../../core/models.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';

class RentalsScreen extends ConsumerStatefulWidget {
  const RentalsScreen({super.key});

  @override
  ConsumerState<RentalsScreen> createState() => _RentalsScreenState();
}

class _RentalsScreenState extends ConsumerState<RentalsScreen> {
  List<Vehicle> _vehicles = [];
  List<RentalBooking> _rentals = [];
  int? _vehicle;
  DateTime? _startsAt;
  DateTime? _endsAt;
  bool _withDriver = false;
  bool _authenticated = false;
  bool _loading = true;
  bool _busy = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = ref.read(apiClientProvider);
    try {
      final vehicles = await api.rentalVehicles();
      var rentals = <RentalBooking>[];
      var authenticated = false;
      try {
        final user = await api.me();
        authenticated = user.isClient;
        if (authenticated) rentals = await api.rentals();
      } catch (_) {}
      if (mounted) {
        setState(() {
          _vehicles = vehicles;
          _rentals = rentals;
          _authenticated = authenticated;
          _loading = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _message = error.toString();
        });
      }
    }
  }

  Future<DateTime?> _pickDateTime(DateTime initial) async {
    final date = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(beninToday()) ? beninToday() : initial,
      // Jours passés grisés : le calendrier commence aujourd'hui au Bénin.
      firstDate: beninToday(),
      lastDate: beninToday().add(const Duration(days: 730)),
    );
    if (date == null || !mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Future<void> _submit() async {
    if (!_authenticated) {
      context.push('/login');
      return;
    }
    if (_vehicle == null) {
      setState(() => _message = 'Choisissez un véhicule.');
      return;
    }
    // Date passée, heure déjà dépassée ou champ vide : message, et aucun appel au serveur.
    final periodProblem = rentalPeriodError(_startsAt, _endsAt);
    if (periodProblem != null) {
      setState(() => _message = periodProblem);
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final booking = await ref
          .read(apiClientProvider)
          .createRental(
            vehicle: _vehicle!,
            startsAt: _startsAt!,
            endsAt: _endsAt!,
            withDriver: _withDriver,
          );
      if (mounted) {
        setState(() {
          _rentals = [booking, ..._rentals];
          _message = 'Demande enregistrée : ${booking.reference}';
        });
      }
    } catch (error) {
      if (mounted) setState(() => _message = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final selected = _vehicles.where((item) => item.id == _vehicle).firstOrNull;
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 32),
      children: [
        const Text(
          'LOCATION DE VÉHICULE',
          style: TextStyle(
            color: AxisColors.blue,
            fontSize: 11,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.6,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Véhicules disponibles',
          style: TextStyle(
            color: AxisColors.text,
            fontSize: 22,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 14),
        if (_vehicles.isEmpty)
          const AxisCard(
            child: Column(
              children: [
                Text(
                  'Aucun véhicule publié',
                  style: TextStyle(
                    color: AxisColors.text,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'La flotte réelle et les tarifs sont configurés par Axis.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AxisColors.muted, height: 1.4),
                ),
              ],
            ),
          )
        else
          ..._vehicles.map(
            (vehicle) => AxisCard(
              onTap: () => setState(() => _vehicle = vehicle.id),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: _vehicle == vehicle.id
                      ? Border.all(color: AxisColors.blue, width: 2)
                      : null,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              vehicle.name,
                              style: const TextStyle(
                                color: AxisColors.text,
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          Text(
                            vehicle.dailyRate == null
                                ? 'Tarif à confirmer'
                                : '${formatMoney(vehicle.dailyRate!, 'F')}/j',
                            style: const TextStyle(
                              color: AxisColors.navy,
                              fontWeight: FontWeight.w900,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(
                        '${vehicle.capacity == null ? 'Capacité à confirmer' : '${vehicle.capacity} places'}${vehicle.baseLocation == null ? '' : ' · ${vehicle.baseLocation!.name}'}',
                        style: const TextStyle(
                          color: AxisColors.muted,
                          fontSize: 12,
                        ),
                      ),
                      if (vehicle.description.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            vehicle.description,
                            style: const TextStyle(
                              color: AxisColors.muted,
                              fontSize: 12,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        const SizedBox(height: 10),
        AxisCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Demande de location',
                style: TextStyle(
                  color: AxisColors.text,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (!_authenticated)
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: OutlinedButton(
                    onPressed: () => context.push('/login'),
                    child: const Text('Se connecter pour envoyer une demande'),
                  ),
                ),
              const SizedBox(height: 16),
              const Text(
                'Véhicule choisi',
                style: TextStyle(
                  color: AxisColors.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                selected?.name ?? 'Touchez un véhicule ci-dessus',
                style: const TextStyle(
                  color: AxisColors.navy,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () async {
                  final value = await _pickDateTime(
                    _startsAt ?? DateTime.now().add(const Duration(days: 1)),
                  );
                  if (value != null) setState(() => _startsAt = value);
                },
                icon: const Icon(Icons.calendar_month),
                label: Text(
                  _startsAt == null
                      ? 'Choisir le début'
                      : 'Début : ${formatDateTime(_startsAt!)}',
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () async {
                  final value = await _pickDateTime(
                    _endsAt ??
                        (_startsAt ?? DateTime.now()).add(
                          const Duration(days: 2),
                        ),
                  );
                  if (value != null) setState(() => _endsAt = value);
                },
                icon: const Icon(Icons.event_available),
                label: Text(
                  _endsAt == null
                      ? 'Choisir la fin'
                      : 'Fin : ${formatDateTime(_endsAt!)}',
                ),
              ),
              const SizedBox(height: 10),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Avec chauffeur',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(
                  selected?.driverAvailable == true
                      ? 'Disponible pour ce véhicule'
                      : 'Sous réserve de disponibilité',
                ),
                value: _withDriver,
                onChanged: (value) => setState(() => _withDriver = value),
              ),
              if (_message != null)
                Notice(
                  _message!,
                  error: !_message!.startsWith('Demande enregistrée'),
                ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed:
                    _busy ||
                        _vehicle == null ||
                        _startsAt == null ||
                        _endsAt == null
                    ? null
                    : _submit,
                child: Text(_busy ? 'Patientez…' : 'Envoyer la demande'),
              ),
              const SizedBox(height: 10),
              const Text(
                'Les justificatifs éventuels seront demandés selon la politique de location configurée par Axis.',
                style: TextStyle(
                  color: AxisColors.muted,
                  fontSize: 11,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        const Text(
          'Mes demandes',
          style: TextStyle(
            color: AxisColors.text,
            fontSize: 22,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 14),
        if (_rentals.isEmpty)
          const AxisCard(
            child: Text(
              'Aucune demande',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          )
        else
          ..._rentals.map(
            (rental) => AxisCard(
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          rental.vehicle.name,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          rental.reference,
                          style: const TextStyle(
                            color: AxisColors.muted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    rental.statusDisplay,
                    style: const TextStyle(
                      color: AxisColors.navy,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
