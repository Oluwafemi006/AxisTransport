import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/benin_time.dart';
import '../../../core/models.dart';
import '../../../core/session.dart';
import '../../../core/theme/axis_theme.dart';
import '../../../core/widgets/widgets.dart';
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
    _date = widget.initialSearch?.date ?? beninToday();
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
    // Jours passés grisés : le calendrier commence aujourd'hui au Bénin.
    final today = beninToday();
    final selected = await showDatePicker(
      context: context,
      initialDate: _date.isBefore(today) ? today : _date,
      firstDate: today,
      lastDate: DateTime(today.year + 2, today.month, today.day),
    );
    if (selected != null && mounted) setState(() => _date = selected);
  }

  Future<void> _choosePassengers() async {
    final theme = Theme.of(context);
    final selected = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: Text(
                'Nombre de passagers',
                style: theme.textTheme.titleMedium,
              ),
              subtitle: Text(
                'Les informations seront demandées avant le choix des sièges.',
                style: theme.textTheme.bodySmall,
              ),
            ),
            ...List.generate(8, (index) {
              final count = index + 1;
              return ListTile(
                title: Text(
                  '$count adulte${count > 1 ? 's' : ''}',
                  style: theme.textTheme.bodyMedium,
                ),
                selected: count == _passengers,
                trailing: count == _passengers
                    ? Icon(Icons.check_circle, color: theme.colorScheme.primary)
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
    final dateProblem = tripDateError(_date);
    if (dateProblem != null) {
      setState(() => _error = dateProblem);
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
    final theme = Theme.of(context);
    final axis = context.axis;

    return AxisCard(
      floating: true,
      padding: const EdgeInsets.all(AxisSpacing.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Stack(
            alignment: Alignment.centerRight,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _LocationField(
                    label: 'Départ',
                    dotColor: theme.colorScheme.primary,
                    dotHaloColor: axis.primarySoft,
                    value: _originId,
                    places: _places,
                    onChanged: _loading
                        ? null
                        : (value) => setState(() {
                            _originId = value;
                            _error = null;
                          }),
                  ),
                  const SizedBox(height: AxisSpacing.s8),
                  _LocationField(
                    label: 'Arrivée',
                    dotColor: axis.accent,
                    dotHaloColor: axis.accentSoft,
                    value: _destinationId,
                    places: _places,
                    onChanged: _loading
                        ? null
                        : (value) => setState(() {
                            _destinationId = value;
                            _error = null;
                          }),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(right: AxisSpacing.s14),
                child: Tooltip(
                  message: 'Inverser le départ et l’arrivée',
                  child: Semantics(
                    button: true,
                    label: 'Inverser le départ et l’arrivée',
                    child: Container(
                      width: AxisSizes.minTarget,
                      height: AxisSizes.minTarget,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: theme.colorScheme.surface,
                          width: 3,
                        ),
                      ),
                      child: Material(
                        color: theme.colorScheme.primary,
                        shape: const CircleBorder(),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: _loading
                              ? null
                              : () => setState(() {
                                  final previous = _originId;
                                  _originId = _destinationId;
                                  _destinationId = previous;
                                }),
                          child: Icon(
                            Icons.swap_vert_rounded,
                            color: theme.colorScheme.onPrimary,
                            size: AxisSizes.icon,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AxisSpacing.s10),
          Row(
            children: [
              Expanded(
                child: _SearchDetail(
                  label: 'Date',
                  value: DateFormat('EEE d MMM', 'fr_FR').format(_date),
                  icon: Icons.calendar_today_outlined,
                  onTap: _chooseDate,
                ),
              ),
              const SizedBox(width: AxisSpacing.s10),
              Expanded(
                child: _SearchDetail(
                  label: 'Passagers',
                  value: '$_passengers adulte${_passengers > 1 ? 's' : ''}',
                  icon: Icons.person_outline_rounded,
                  onTap: _choosePassengers,
                ),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: AxisSpacing.s10),
            _InlineAlert(message: _error!, isDanger: true),
          ],
          if (_loadError != null) ...[
            const SizedBox(height: AxisSpacing.s10),
            _InlineAlert(
              message:
                  'Impossible de charger les villes de départ et de destination. '
                  'Vérifiez votre connexion Internet, puis réessayez.\n$_loadError',
              isDanger: true,
            ),
            const SizedBox(height: AxisSpacing.s8),
            AxisButton(
              variant: AxisButtonVariant.outline,
              height: AxisSizes.secondaryButton,
              icon: const Icon(Icons.refresh_rounded),
              label: 'Réessayer',
              onPressed: _loadPlaces,
            ),
          ] else if (!_loading && _places.isEmpty) ...[
            const SizedBox(height: AxisSpacing.s10),
            const _InlineAlert(
              message: 'Aucune ville n’est encore ouverte à la réservation.',
              isDanger: false,
            ),
            const SizedBox(height: AxisSpacing.s8),
            AxisButton(
              variant: AxisButtonVariant.outline,
              height: AxisSizes.secondaryButton,
              icon: const Icon(Icons.refresh_rounded),
              label: 'Réessayer',
              onPressed: _loadPlaces,
            ),
          ],
          if (_loading) ...[
            const SizedBox(height: AxisSpacing.s10),
            const SkeletonBox(
              height: AxisSpacing.s12,
              borderRadius: AxisRadius.chip,
            ),
          ],
          const SizedBox(height: AxisSpacing.s12),
          AxisButton(
            onPressed: _canSearch ? _search : null,
            icon: const Icon(Icons.search_rounded),
            label: 'Rechercher les trajets',
          ),
        ],
      ),
    );
  }
}

class _LocationField extends StatelessWidget {
  const _LocationField({
    required this.label,
    required this.dotColor,
    required this.dotHaloColor,
    required this.value,
    required this.places,
    required this.onChanged,
  });

  final String label;
  final Color dotColor;
  final Color dotHaloColor;
  final int? value;
  final List<Place> places;
  final ValueChanged<int?>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final axis = context.axis;

    return Container(
      padding: const EdgeInsets.fromLTRB(
        AxisSpacing.s14,
        AxisSpacing.s10,
        56,
        AxisSpacing.s10,
      ),
      decoration: BoxDecoration(
        color: axis.inputFill,
        borderRadius: BorderRadius.circular(AxisRadius.field),
        border: Border.all(color: axis.border),
      ),
      child: Row(
        children: [
          Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: dotHaloColor,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                shape: BoxShape.circle,
                border: Border.all(color: dotColor, width: 3),
              ),
            ),
          ),
          const SizedBox(width: AxisSpacing.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: axis.textMuted,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 2),
                DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: value,
                    isExpanded: true,
                    isDense: true,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: axis.ink,
                    ),
                    hint: Text(
                      'Choisir une ville',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: axis.textMuted,
                      ),
                    ),
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final axis = context.axis;

    return Material(
      color: axis.inputFill,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AxisRadius.field),
        side: BorderSide(color: axis.border),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AxisRadius.field),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AxisSpacing.s12,
            vertical: AxisSpacing.s10,
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: AxisSizes.icon,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: AxisSpacing.s10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label.toUpperCase(),
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: axis.textMuted,
                        letterSpacing: 0.6,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: axis.ink,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InlineAlert extends StatelessWidget {
  const _InlineAlert({required this.message, required this.isDanger});

  final String message;
  final bool isDanger;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final axis = context.axis;
    final bg = isDanger ? axis.danger.withValues(alpha: 0.1) : axis.accentSoft;
    final fg = isDanger ? axis.danger : axis.onAccentSoft;

    return Container(
      padding: const EdgeInsets.all(AxisSpacing.s12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AxisRadius.small),
      ),
      child: Text(
        message,
        style: theme.textTheme.bodySmall?.copyWith(color: fg),
      ),
    );
  }
}
