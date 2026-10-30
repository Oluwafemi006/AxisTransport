import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/formatters.dart';
import '../../../core/models.dart';
import '../../../core/session.dart';
import '../../../core/theme/axis_theme.dart';
import '../../../core/widgets/widgets.dart';
import '../../bookings/application/booking_draft.dart';
import '../domain/trip_search.dart';

class TripResultsScreen extends ConsumerStatefulWidget {
  const TripResultsScreen({super.key, required this.search});

  final TripSearch search;

  @override
  ConsumerState<TripResultsScreen> createState() => _TripResultsScreenState();
}

class _TripResultsScreenState extends ConsumerState<TripResultsScreen> {
  List<Trip> _trips = [];
  NextAvailable? _nextAvailable;
  List<Place> _places = [];
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
      final result = await api.searchTripsDetailed(search);
      final places = await placesFuture;
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _trips = result.trips;
        _nextAvailable = result.nextAvailable;
        _places = places;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _trips = [];
        _nextAvailable = null;
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
      for (final stop in trip.route.stops) {
        if (stop.id == id) return stop.name;
      }
    }
    return 'À renseigner';
  }

  List<Trip> get _sortedTrips {
    final trips = [..._trips];
    trips.sort((a, b) => a.departureAt.compareTo(b.departureAt));
    return trips;
  }

  @override
  Widget build(BuildContext context) {
    final search = widget.search;
    final theme = Theme.of(context);
    final axis = context.axis;
    final today = DateTime.now();
    final todayOnly = DateTime(today.year, today.month, today.day);
    final days = List.generate(5, (index) {
      final start = search.date.subtract(const Duration(days: 1));
      final first = start.isBefore(todayOnly) ? todayOnly : start;
      return DateTime(first.year, first.month, first.day + index);
    });

    final originLabel = _placeName(search.originId);
    final destinationLabel = _placeName(search.destinationId);

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.only(bottom: AxisSpacing.s24),
          children: [
            // En-tête blanc avec route + sélecteur horizontal de date (Resultats.html)
            Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                border: Border(bottom: BorderSide(color: axis.border)),
              ),
              padding: const EdgeInsets.fromLTRB(
                AxisSpacing.screen,
                AxisSpacing.s12,
                AxisSpacing.screen,
                AxisSpacing.s14,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Tooltip(
                        message: 'Retour',
                        child: Semantics(
                          button: true,
                          label: 'Retour',
                          child: Material(
                            color: axis.inputFill,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                AxisRadius.small,
                              ),
                              side: BorderSide(color: axis.border),
                            ),
                            child: InkWell(
                              onTap: () => context.canPop()
                                  ? context.pop()
                                  : context.go('/'),
                              borderRadius: BorderRadius.circular(
                                AxisRadius.small,
                              ),
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
                              '$originLabel → $destinationLabel',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleLarge?.copyWith(
                                color: axis.ink,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${search.passengers} adulte${search.passengers > 1 ? 's' : ''} · Aller simple',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: axis.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: AxisSpacing.s8),
                      Tooltip(
                        message: 'Modifier la recherche',
                        child: Semantics(
                          button: true,
                          label: 'Modifier la recherche',
                          child: Material(
                            color: axis.inputFill,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                AxisRadius.small,
                              ),
                              side: BorderSide(color: axis.border),
                            ),
                            child: InkWell(
                              onTap: () => context.push(search.searchLocation),
                              borderRadius: BorderRadius.circular(
                                AxisRadius.small,
                              ),
                              child: SizedBox(
                                width: AxisSizes.minTarget,
                                height: AxisSizes.minTarget,
                                child: Icon(
                                  Icons.tune_rounded,
                                  color: theme.colorScheme.primary,
                                  size: AxisSizes.icon,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AxisSpacing.s12),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: days.map((date) {
                        final selected =
                            date.year == search.date.year &&
                            date.month == search.date.month &&
                            date.day == search.date.day;
                        final dow = DateFormat('EEE', 'fr_FR')
                            .format(date)
                            .replaceAll('.', '')
                            .toUpperCase();
                        final month = DateFormat('MMM', 'fr_FR')
                            .format(date)
                            .replaceAll('.', '');

                        return Padding(
                          padding: const EdgeInsets.only(right: AxisSpacing.s8),
                          child: Material(
                            color: selected
                                ? theme.colorScheme.primary
                                : axis.inputFill,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                AxisRadius.button,
                              ),
                              side: BorderSide(
                                color: selected
                                    ? theme.colorScheme.primary
                                    : axis.border,
                              ),
                            ),
                            child: InkWell(
                              onTap: () => context.go(
                                search.withDate(date).resultsLocation,
                              ),
                              borderRadius: BorderRadius.circular(
                                AxisRadius.button,
                              ),
                              child: Container(
                                constraints: const BoxConstraints(
                                  minWidth: 58,
                                  minHeight: 64,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AxisSpacing.s10,
                                  vertical: AxisSpacing.s8,
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      dow,
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(
                                            color: selected
                                                ? axis.borderStrong
                                                : axis.textMuted,
                                          ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${date.day}',
                                      style: theme.textTheme.titleMedium
                                          ?.copyWith(
                                            color: selected
                                                ? theme.colorScheme.onPrimary
                                                : axis.ink,
                                          ),
                                    ),
                                    Text(
                                      month,
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(
                                            color: selected
                                                ? axis.borderStrong
                                                : axis.textMuted,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),

            // Contenu principal : états SkeletonBox / EmptyState / liste de trajets
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(AxisSpacing.screen),
                child: Column(
                  children: [
                    SkeletonBox(height: 190, borderRadius: AxisRadius.card),
                    SizedBox(height: AxisSpacing.s12),
                    SkeletonBox(height: 190, borderRadius: AxisRadius.card),
                  ],
                ),
              )
            else if (_error != null)
              EmptyState(
                icon: Icons.wifi_off_rounded,
                title: 'Impossible de charger les trajets',
                description: _error!,
                actionLabel: 'Réessayer',
                onAction: _load,
              )
            else if (_trips.isEmpty)
              if (_nextAvailable != null)
                Padding(
                  padding: const EdgeInsets.all(AxisSpacing.screen),
                  child: AxisCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Aucun départ ce jour. Prochain départ pour ce trajet : ${_nextAvailable!.formattedDate} à ${_nextAvailable!.formattedTime}',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: axis.ink,
                          ),
                        ),
                        const SizedBox(height: AxisSpacing.s14),
                        AxisButton(
                          label:
                              'Voir le départ du ${_nextAvailable!.formattedDate}',
                          icon: const Icon(Icons.arrow_forward_rounded),
                          onPressed: () => context.go(
                            search.withDate(_nextAvailable!.date).resultsLocation,
                          ),
                        ),
                        const SizedBox(height: AxisSpacing.s10),
                        AxisButton(
                          variant: AxisButtonVariant.outline,
                          height: AxisSizes.secondaryButton,
                          label: 'Modifier la recherche',
                          onPressed: () => context.push(search.searchLocation),
                        ),
                      ],
                    ),
                  ),
                )
              else
                EmptyState(
                  icon: Icons.directions_bus_outlined,
                  title: 'Aucun départ disponible pour cette recherche.',
                  description:
                      'Sélectionnez un autre jour ci-dessus ou modifiez vos critères.',
                  actionLabel: 'Modifier la recherche',
                  onAction: () => context.push(search.searchLocation),
                )
            else ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AxisSpacing.screen,
                  AxisSpacing.s14,
                  AxisSpacing.screen,
                  AxisSpacing.s10,
                ),
                child: Text(
                  '${_sortedTrips.length} départ${_sortedTrips.length > 1 ? 's' : ''} ce jour · Horaires en heure du Bénin (UTC+1)',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: axis.textSecondary,
                  ),
                ),
              ),
              ..._sortedTrips.map(
                (trip) => Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AxisSpacing.screen,
                    0,
                    AxisSpacing.screen,
                    AxisSpacing.s12,
                  ),
                  child: _TripResultCard(
                    trip: trip,
                    passengers: search.passengers,
                    search: search,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TripResultCard extends ConsumerWidget {
  const _TripResultCard({
    required this.trip,
    required this.passengers,
    this.search,
  });

  final Trip trip;
  final int passengers;
  final TripSearch? search;

  List<RouteStopItem> _buildStopItems() {
    if (trip.route.stops.isNotEmpty) {
      final sorted = [...trip.route.stops]
        ..sort((a, b) => a.position.compareTo(b.position));
      return sorted
          .map((stop) => RouteStopItem(name: stop.name))
          .toList();
    }
    final items = <RouteStopItem>[];
    if (trip.route.origin != null && trip.route.origin!.name.isNotEmpty) {
      items.add(RouteStopItem(name: trip.route.origin!.name));
    }
    if (trip.route.destination != null &&
        trip.route.destination!.name.isNotEmpty) {
      items.add(RouteStopItem(name: trip.route.destination!.name));
    }
    return items;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final axis = context.axis;
    final fare = trip.currentFare;
    final bookable = fare != null && trip.availableSeats >= passengers;
    final departure = DateFormat.Hm('fr_FR').format(trip.departureAt);
    // Heure d'embarquement = champ boardingAt du serveur ou départ − 30 min à l'affichage.
    final boardingAt =
        trip.boardingAt ??
        trip.departureAt.subtract(const Duration(minutes: 30));
    final boarding = DateFormat.Hm('fr_FR').format(boardingAt);
    final stops = _buildStopItems();

    return AxisCard(
      padding: const EdgeInsets.all(AxisSpacing.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Ligne supérieure : heure de départ + embarquement à gauche, prix TTC à droite
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      departure,
                      style: theme.textTheme.displaySmall?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: AxisSpacing.s4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.access_time_rounded,
                          size: 14,
                          color: axis.onAccentSoft,
                        ),
                        const SizedBox(width: AxisSpacing.s4),
                        Flexible(
                          child: Text(
                            'Embarquement $boarding',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: axis.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    fare == null
                        ? 'À renseigner'
                        : formatMoney(fare.amount, fare.currency),
                    style: AxisTypography.price.copyWith(color: axis.ink),
                  ),
                  Text(
                    'TTC',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: axis.textMuted,
                    ),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: AxisSpacing.s8),
          Text(
            trip.route.label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: axis.textSecondary,
            ),
          ),

          // Frise horizontale des arrêts
          if (stops.length >= 2) ...[
            const SizedBox(height: AxisSpacing.s14),
            RouteStopsBar(stops: stops),
          ],

          const SizedBox(height: AxisSpacing.s14),
          const Divider(height: 1),
          const SizedBox(height: AxisSpacing.s12),

          // Puces d'état (places disponibles, véhicule)
          Wrap(
            spacing: AxisSpacing.s8,
            runSpacing: AxisSpacing.s8,
            children: [
              StatusChip(
                label:
                    '${trip.availableSeats} place${trip.availableSeats > 1 ? 's' : ''} libre${trip.availableSeats > 1 ? 's' : ''}',
                variant: trip.availableSeats > 0
                    ? StatusChipVariant.success
                    : StatusChipVariant.danger,
                icon: Icons.event_seat_outlined,
              ),
              if (trip.vehicleName != null && trip.vehicleName!.isNotEmpty)
                StatusChip(
                  label: trip.vehicleName!,
                  variant: StatusChipVariant.neutral,
                  icon: Icons.directions_bus_outlined,
                ),
            ],
          ),

          const SizedBox(height: AxisSpacing.s12),
          AxisButton(
            variant: AxisButtonVariant.secondary,
            height: AxisSizes.secondaryButton,
            onPressed: bookable
                ? () {
                    ref.read(bookingDraftProvider.notifier).start(
                          trip,
                          originId: search?.originId,
                          destinationId: search?.destinationId,
                        );
                    context.push(
                      '/billets/booking/${trip.id}/passagers?passagers=$passengers${search != null ? '&origin=${search!.originId}&destination=${search!.destinationId}' : ''}',
                    );
                  }
                : null,
            label: trip.availableSeats < passengers
                ? 'Complet'
                : fare == null
                ? 'Tarif à renseigner'
                : 'Choisir ce trajet',
          ),
        ],
      ),
    );
  }
}
