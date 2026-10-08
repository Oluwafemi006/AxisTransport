import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/models.dart';
import '../../../core/session.dart';
import '../../../core/theme.dart';
import '../../../shared/widgets.dart';
import '../domain/trip_search.dart';

class TripSearchCard extends ConsumerStatefulWidget {
  const TripSearchCard({super.key, this.initialSearch});

  final TripSearch? initialSearch;

  @override
  ConsumerState<TripSearchCard> createState() => _TripSearchCardState();
}

class _TripSearchCardState extends ConsumerState<TripSearchCard> {
  List<Place> _places = [];
  int? _originId;
  int? _destinationId;
  late DateTime _date;
  late int _passengers;
  bool _loading = true;
  String? _error;
  // Échec du chargement des villes : message dédié avec « Réessayer ».
  String? _loadError;

  bool get _canSearch =>
      _originId != null && _destinationId != null && _originId != _destinationId;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _date =
        widget.initialSearch?.date ?? DateTime(now.year, now.month, now.day);
    _originId = widget.initialSearch?.originId;
    _destinationId = widget.initialSearch?.destinationId;
    _passengers = widget.initialSearch?.passengers ?? 1;
    _loadPlaces();
  }

  Future<void> _loadPlaces() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    }
    try {
      final places = await ref.read(apiClientProvider).locations();
      if (!mounted) return;
      setState(() {
        _places = places;
        if (!places.any((place) => place.id == _originId)) _originId = null;
        if (!places.any((place) => place.id == _destinationId)) {
          _destinationId = null;
        }
        _loading = false;
        _error = null;
        _loadError = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = e.toString();
        });
      }
    }
  }

  Future<void> _chooseDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final selected = await showDatePicker(
      context: context,
      initialDate: _date.isBefore(today) ? today : _date,
      firstDate: today,
      lastDate: DateTime(today.year + 2, today.month, today.day),
    );
    if (selected != null && mounted) setState(() => _date = selected);
  }

  Future<void> _choosePassengers() async {
    final selected = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(
              title: Text(
                'Nombre de voyageurs',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              subtitle: Text(
                'Les informations seront demandées avant les sièges.',
              ),
            ),
            ...List.generate(8, (index) {
              final count = index + 1;
              return ListTile(
                title: Text('$count voyageur${count > 1 ? 's' : ''}'),
                selected: count == _passengers,
                trailing: count == _passengers
                    ? const Icon(Icons.check_circle, color: AxisColors.navy)
                    : null,
                onTap: () => Navigator.pop(context, count),
              );
            }),
          ],
        ),
      ),
    );
    if (selected != null && mounted) setState(() => _passengers = selected);
  }

  void _search() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (_date.isBefore(today)) {
      setState(() => _error = 'Choisissez une date à partir d’aujourd’hui.');
      return;
    }
    if (_originId == null || _destinationId == null) {
      setState(() => _error = 'Choisissez un départ et une destination.');
      return;
    }
    if (_originId == _destinationId) {
      setState(() => _error = 'Choisissez deux villes différentes.');
      return;
    }
    final search = TripSearch(
      originId: _originId!,
      destinationId: _destinationId!,
      date: _date,
      passengers: _passengers,
    );
    context.go(search.resultsLocation);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x120F2552),
            blurRadius: 24,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _LocationField(
            label: 'Point de départ',
            icon: Icons.trip_origin,
            iconColor: AxisColors.navy,
            value: _originId,
            places: _places,
            onChanged: _loading
                ? null
                : (value) => setState(() {
                    _originId = value;
                    _error = null;
                  }),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: IconButton.filledTonal(
              tooltip: 'Intervertir les villes',
              onPressed: _loading
                  ? null
                  : () => setState(() {
                      final previous = _originId;
                      _originId = _destinationId;
                      _destinationId = previous;
                    }),
              icon: const Icon(Icons.swap_vert),
            ),
          ),
          _LocationField(
            label: 'Destination',
            icon: Icons.location_on_outlined,
            iconColor: AxisColors.red,
            value: _destinationId,
            places: _places,
            onChanged: _loading
                ? null
                : (value) => setState(() {
                    _destinationId = value;
                    _error = null;
                  }),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _SearchDetail(
                  label: 'Départ',
                  value: DateFormat('EEE d MMM', 'fr_FR').format(_date),
                  icon: Icons.calendar_today_outlined,
                  onTap: _chooseDate,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _SearchDetail(
                  label: 'Voyageurs',
                  value: '$_passengers voyageur${_passengers > 1 ? 's' : ''}',
                  icon: Icons.group_outlined,
                  onTap: _choosePassengers,
                ),
              ),
            ],
          ),
          if (_error != null) Notice(_error!, error: true),
          if (_loadError != null) ...[
            Notice(
              'Impossible de charger les villes de départ et de destination. '
              'Vérifiez votre connexion Internet, puis réessayez.\n$_loadError',
              error: true,
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _loadPlaces,
              icon: const Icon(Icons.refresh),
              label: const Text('Réessayer'),
            ),
          ] else if (!_loading && _places.isEmpty) ...[
            const Notice('Aucune ville n\'est encore ouverte à la réservation.'),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _loadPlaces,
              icon: const Icon(Icons.refresh),
              label: const Text('Réessayer'),
            ),
          ],
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: _canSearch ? _search : null,
            icon: const Icon(Icons.search),
            label: const Text('Rechercher un trajet'),
          ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}

class _LocationField extends StatelessWidget {
  const _LocationField({
    required this.label,
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.places,
    required this.onChanged,
  });

  final String label;
  final IconData icon;
  final Color iconColor;
  final int? value;
  final List<Place> places;
  final ValueChanged<int?>? onChanged;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: AxisColors.surfaceLow,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        Icon(icon, color: iconColor),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label.toUpperCase(),
                style: const TextStyle(
                  color: AxisColors.muted,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
              DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  value: value,
                  isExpanded: true,
                  isDense: true,
                  hint: const Text('Choisir une ville'),
                  items: places
                      .map(
                        (place) => DropdownMenuItem<int>(
                          value: place.id,
                          child: Text(
                            place.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: onChanged,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _SearchDetail extends StatelessWidget {
  const _SearchDetail({
    required this.label,
    required this.value,
    required this.icon,
    this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: AxisColors.surfaceLow,
    borderRadius: BorderRadius.circular(12),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: AxisColors.muted),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    label.toUpperCase(),
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AxisColors.muted,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    ),
  );
}
