import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/formatters.dart';
import '../../../core/models.dart';
import '../../../core/session.dart';
import '../../../core/theme.dart';
import '../../../shared/widgets.dart';
import '../domain/trip_search.dart';

enum _SortBy { departure, price, seats }

class TripResultsScreen extends ConsumerStatefulWidget {
  const TripResultsScreen({super.key, required this.search});

  final TripSearch search;

  @override
  ConsumerState<TripResultsScreen> createState() => _TripResultsScreenState();
}

class _TripResultsScreenState extends ConsumerState<TripResultsScreen> {
  List<Trip> _trips = [];
  List<Place> _places = [];
  _SortBy _sort = _SortBy.departure;
  bool _loading = true;
  String? _error;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant TripResultsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.search.resultsLocation != widget.search.resultsLocation) {
      _load();
    }
  }

  Future<void> _load() async {
    final api = ref.read(apiClientProvider);
    final search = widget.search;
    final generation = ++_loadGeneration;
    setState(() {
      _loading = true;
      _error = null;
    });
    final placesFuture = api.locations().catchError((_) => <Place>[]);
    try {
      final trips = await api.searchTrips(search);
      final places = await placesFuture;
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _trips = trips;
        _places = places;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _trips = [];
        _loading = false;
        _error =
            'Connexion nécessaire pour connaître les places et tarifs actuels.';
      });
    }
  }

  String _placeName(int id) {
    for (final place in _places) {
      if (place.id == id) return place.name;
    }
    for (final trip in _trips) {
      if (trip.route.origin?.id == id) return trip.route.origin!.name;
      if (trip.route.destination?.id == id) return trip.route.destination!.name;
    }
    return 'Ville à confirmer';
  }

  List<Trip> get _sortedTrips {
    final trips = [..._trips];
    switch (_sort) {
      case _SortBy.departure:
        trips.sort((a, b) => a.departureAt.compareTo(b.departureAt));
      case _SortBy.price:
        trips.sort((a, b) {
          final first = a.currentFare?.amount;
          final second = b.currentFare?.amount;
          if (first == null) return second == null ? 0 : 1;
          if (second == null) return -1;
          return first.compareTo(second);
        });
      case _SortBy.seats:
        trips.sort((a, b) => b.availableSeats.compareTo(a.availableSeats));
    }
    return trips;
  }

  @override
  Widget build(BuildContext context) {
    final search = widget.search;
    final today = DateTime.now();
    final todayOnly = DateTime(today.year, today.month, today.day);
    final days = List.generate(5, (index) {
      final start = search.date.subtract(const Duration(days: 2));
      final first = start.isBefore(todayOnly) ? todayOnly : start;
      return DateTime(first.year, first.month, first.day + index);
    });
    return Scaffold(
      appBar: AppBar(title: const Text('Résultats des trajets')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${_placeName(search.originId)}  →  ${_placeName(search.destinationId)}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AxisColors.navyDark,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      IconButton.filledTonal(
                        tooltip: 'Modifier la recherche',
                        onPressed: () => context.push(search.searchLocation),
                        icon: const Icon(Icons.tune),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${DateFormat('EEE d MMMM y', 'fr_FR').format(search.date)} · ${search.passengers} voyageur${search.passengers > 1 ? 's' : ''}',
                    style: const TextStyle(color: AxisColors.muted),
                  ),
                  const SizedBox(height: 14),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: days.map((date) {
                        final selected =
                            date.year == search.date.year &&
                            date.month == search.date.month &&
                            date.day == search.date.day;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(
                              DateFormat('EEE d MMM', 'fr_FR').format(date),
                            ),
                            selected: selected,
                            onSelected: (_) => context.go(
                              search.withDate(date).resultsLocation,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Wrap(
                spacing: 8,
                children: [
                  _sortChip('Prochain départ', _SortBy.departure),
                  _sortChip('Moins cher', _SortBy.price),
                  _sortChip('Places disponibles', _SortBy.seats),
                ],
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Notice(_error!, error: true),
              ),
            const SizedBox(height: 14),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: OutlinedButton(
                  onPressed: _load,
                  child: const Text('Réessayer la recherche'),
                ),
              )
            else if (_trips.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: AxisCard(
                  child: Column(
                    children: [
                      const Text(
                        'Aucun départ disponible pour cette recherche.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: () => context.push(search.searchLocation),
                        child: const Text('Modifier la recherche'),
                      ),
                    ],
                  ),
                ),
              )
            else
              ..._sortedTrips.map(
                (trip) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _TripResultCard(
                    trip: trip,
                    passengers: search.passengers,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _sortChip(String label, _SortBy value) => ChoiceChip(
    label: Text(label),
    selected: _sort == value,
    onSelected: (_) => setState(() => _sort = value),
  );
}

class _TripResultCard extends StatelessWidget {
  const _TripResultCard({required this.trip, required this.passengers});

  final Trip trip;
  final int passengers;

  @override
  Widget build(BuildContext context) {
    final fare = trip.currentFare;
    final bookable = fare != null && trip.availableSeats >= passengers;
    final departure = DateFormat.Hm('fr_FR').format(trip.departureAt);
    final arrival = trip.arrivalAt == null
        ? null
        : DateFormat.Hm('fr_FR').format(trip.arrivalAt!);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: AxisCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.directions_bus_outlined,
                  size: 18,
                  color: AxisColors.navy,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    trip.route.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                Text(
                  '${trip.availableSeats} place${trip.availableSeats > 1 ? 's' : ''}',
                  style: TextStyle(
                    color: trip.availableSeats > 0
                        ? AxisColors.success
                        : AxisColors.danger,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                _TimePoint(
                  time: departure,
                  place: trip.route.origin?.name ?? 'Départ',
                ),
                const Expanded(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10),
                    child: Row(
                      children: [
                        Expanded(child: Divider()),
                        Icon(
                          Icons.directions_bus,
                          size: 18,
                          color: AxisColors.red,
                        ),
                        Expanded(child: Divider()),
                      ],
                    ),
                  ),
                ),
                _TimePoint(
                  time: arrival ?? '—',
                  place: trip.route.destination?.name ?? 'Arrivée',
                  end: true,
                ),
              ],
            ),
            if (trip.vehicleName != null && trip.vehicleName!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                trip.vehicleName!,
                style: const TextStyle(color: AxisColors.muted, fontSize: 12),
              ),
            ],
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AxisColors.surfaceLow,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Tarif par personne',
                      style: TextStyle(color: AxisColors.muted),
                    ),
                  ),
                  Flexible(
                    child: Text(
                      fare == null
                          ? 'Indisponible'
                          : formatMoney(fare.amount, fare.currency),
                      textAlign: TextAlign.end,
                      style: const TextStyle(
                        color: AxisColors.navyDark,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: bookable
                  ? () => context.push(
                      '/billets/booking/${trip.id}/passagers?passagers=$passengers',
                    )
                  : null,
              child: Text(
                trip.availableSeats < passengers
                    ? 'Complet'
                    : fare == null
                    ? 'Tarif à configurer'
                    : 'Choisir ce voyage',
              ),
            ),
            if (trip.isDemo)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Données de démonstration non validées',
                  style: TextStyle(color: AxisColors.warning, fontSize: 11),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TimePoint extends StatelessWidget {
  const _TimePoint({required this.time, required this.place, this.end = false});

  final String time;
  final String place;
  final bool end;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: end ? CrossAxisAlignment.end : CrossAxisAlignment.start,
    children: [
      Text(
        time,
        style: const TextStyle(
          color: AxisColors.navyDark,
          fontSize: 22,
          fontWeight: FontWeight.w900,
        ),
      ),
      SizedBox(
        width: 100,
        child: Text(
          place,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: end ? TextAlign.end : TextAlign.start,
          style: const TextStyle(color: AxisColors.muted, fontSize: 11),
        ),
      ),
    ],
  );
}
