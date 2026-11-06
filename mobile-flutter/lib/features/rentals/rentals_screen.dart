import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/formatters.dart';
import '../../core/models.dart';
import '../../core/session.dart';
import '../../core/theme/axis_spacing.dart';
import '../../core/theme/axis_tokens.dart';
import '../../core/theme/axis_typography.dart';
import '../../core/widgets/axis_button.dart';
import '../../core/widgets/axis_card.dart';
import '../../core/widgets/choice_card.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/segmented_toggle.dart';
import '../../core/widgets/skeleton_box.dart';
import '../../core/widgets/status_chip.dart';

/// Date du jour au Bénin (UTC+1).
DateTime beninToday([DateTime? now]) {
  final benin = (now ?? DateTime.now()).toUtc().add(const Duration(hours: 1));
  return DateTime(benin.year, benin.month, benin.day);
}

/// Vérifie la période de location (dates au Bénin, UTC+1).
String? rentalPeriodError(DateTime startsAt, DateTime endsAt, DateTime today) {
  final startDay = DateTime(startsAt.year, startsAt.month, startsAt.day);
  final todayDay = DateTime(today.year, today.month, today.day);
  if (startDay.isBefore(todayDay)) {
    return 'La date de début ne peut pas être dans le passé.';
  }
  if (!endsAt.isAfter(startsAt)) {
    return 'La fin de location doit être après le début.';
  }
  return null;
}

/// Écran client de location de véhicules (`Location.html`).
class RentalsScreen extends ConsumerStatefulWidget {
  const RentalsScreen({super.key});

  @override
  ConsumerState<RentalsScreen> createState() => _RentalsScreenState();
}

class _RentalsScreenState extends ConsumerState<RentalsScreen> {
  List<Vehicle> _vehicles = const [];
  List<RentalBooking> _rentals = const [];
  bool _loading = true;
  bool _withDriver = false;
  String? _error;
  String? _confirmation;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final api = ref.read(apiClientProvider);
    final signedIn = ref.read(sessionProvider).user != null;
    try {
      final vehicles = await api.rentalVehicles();
      final rentals = signedIn ? await api.rentals() : const <RentalBooking>[];
      if (!mounted) return;
      setState(() {
        _vehicles = vehicles;
        _rentals = rentals;
        _loading = false;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _loading = false;
      });
    }
  }

  Future<void> _openRentalDetail(Vehicle vehicle, bool withDriver) async {
    final result = await Navigator.of(context, rootNavigator: true).push<String>(
      MaterialPageRoute(
        builder: (context) => RentalDetailScreen(
          vehicle: vehicle,
          initialWithDriver: withDriver,
        ),
      ),
    );
    if (!mounted) return;
    if (result != null && result.isNotEmpty) {
      setState(() => _confirmation = result);
      await _load();
    }
  }

  String get _agencyLabel {
    for (final v in _vehicles) {
      final loc = v.baseLocation?.name.trim();
      if (loc != null && loc.isNotEmpty) return loc;
    }
    return 'Agence Axis';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final axis = context.axis;
    final onPrimary = theme.colorScheme.onPrimary;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: RefreshIndicator(
        onRefresh: _load,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: AxisSpacing.s24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── En-tête bleu marine (`Location.html`) ────────────────────────
              Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(AxisRadius.sheet),
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(
                  AxisSpacing.screen,
                  AxisSpacing.s16,
                  AxisSpacing.screen,
                  AxisSpacing.s20,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Material(
                                color: onPrimary.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(
                                  AxisRadius.small,
                                ),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(
                                    AxisRadius.small,
                                  ),
                                  onTap: () {
                                    if (Navigator.of(context).canPop()) {
                                      Navigator.of(context).pop();
                                    } else {
                                      context.go('/');
                                    }
                                  },
                                  child: SizedBox(
                                    width: AxisSizes.minTarget,
                                    height: AxisSizes.minTarget,
                                    child: Icon(
                                      Icons.chevron_left_rounded,
                                      color: onPrimary,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: AxisSpacing.s10),
                              Flexible(
                                child: Text(
                                  'Location de véhicules',
                                  style: theme.textTheme.headlineSmall?.copyWith(
                                    color: onPrimary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: AxisSpacing.s8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AxisSpacing.s10,
                            vertical: AxisSpacing.s6,
                          ),
                          decoration: BoxDecoration(
                            color: onPrimary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(AxisRadius.pill),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.place_outlined,
                                size: AxisSizes.icon,
                                color: axis.accent,
                              ),
                              const SizedBox(width: AxisSpacing.s4),
                              Text(
                                _agencyLabel,
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: onPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AxisSpacing.s6),
                    Text(
                      'Choisissez la formule, puis le véhicule disponible.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: onPrimary.withValues(alpha: 0.8),
                      ),
                    ),
                    const SizedBox(height: AxisSpacing.s14),
                    SegmentedToggle<bool>(
                      style: SegmentedToggleStyle.header,
                      selectedValue: _withDriver,
                      onChanged: (value) => setState(() => _withDriver = value),
                      options: const [
                        SegmentOption<bool>(
                          value: false,
                          label: 'Sans chauffeur',
                        ),
                        SegmentOption<bool>(
                          value: true,
                          label: 'Avec chauffeur',
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // ── Contenu principal ────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AxisSpacing.screen,
                  AxisSpacing.s16,
                  AxisSpacing.screen,
                  0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_confirmation != null) ...[
                      AxisCard(
                        backgroundColor: axis.successSoft,
                        child: Row(
                          children: [
                            Icon(
                              Icons.check_circle_outline_rounded,
                              color: axis.success,
                            ),
                            const SizedBox(width: AxisSpacing.s10),
                            Expanded(
                              child: Text(
                                _confirmation!,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: axis.success,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AxisSpacing.s14),
                    ],

                    if (_loading)
                      const _RentalsSkeletonList()
                    else if (_error != null)
                      EmptyState(
                        title: 'Impossible de charger les véhicules',
                        description: _error!,
                        icon: Icons.wifi_off_rounded,
                        actionLabel: 'Réessayer',
                        onAction: _load,
                      )
                    else if (_vehicles.isEmpty)
                      const EmptyState(
                        title: 'Bientôt disponible',
                        description:
                            'Aucun véhicule n’est disponible à la location pour le moment.',
                        icon: Icons.directions_car_outlined,
                      )
                    else ...[
                      for (final vehicle in _vehicles) ...[
                        RentalVehicleCard(
                          vehicle: vehicle,
                          withDriver: _withDriver,
                          onSwitchMode: (targetWithDriver) {
                            setState(() => _withDriver = targetWithDriver);
                          },
                          onReserve: () => _openRentalDetail(
                            vehicle,
                            _withDriver,
                          ),
                        ),
                        const SizedBox(height: AxisSpacing.s14),
                      ],
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AxisSpacing.s8,
                          vertical: AxisSpacing.s4,
                        ),
                        child: Text(
                          'Carburant non inclus. Réduction possible pour plusieurs jours, appliquée par l’agence.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],

                    if (_rentals.isNotEmpty) ...[
                      const SizedBox(height: AxisSpacing.s20),
                      Text(
                        'Mes demandes',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: AxisSpacing.s10),
                      for (final rental in _rentals) ...[
                        _RentalBookingCard(rental: rental),
                        const SizedBox(height: AxisSpacing.s10),
                      ],
                    ],
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

/// Carte d'un véhicule dans la liste de location (`Location.html`).
class RentalVehicleCard extends StatelessWidget {
  const RentalVehicleCard({
    super.key,
    required this.vehicle,
    required this.withDriver,
    required this.onSwitchMode,
    required this.onReserve,
  });

  final Vehicle vehicle;
  final bool withDriver;
  final ValueChanged<bool> onSwitchMode;
  final VoidCallback onReserve;

  /// Indique si le véhicule ne peut être loué qu'avec chauffeur.
  bool get _isDriverOnly => vehicle.onlyWithDriver;

  /// Indique si la formule courante est indisponible pour ce véhicule.
  bool get _unavailableInSelectedMode {
    if (!withDriver && _isDriverOnly) return true;
    if (withDriver && !vehicle.driverAvailable && !_isDriverOnly) return true;
    return false;
  }

  num? get _effectiveDailyRate {
    if (withDriver) {
      return vehicle.dailyRateWithDriver ?? vehicle.dailyRate;
    }
    return vehicle.dailyRate;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final axis = context.axis;
    final rate = _effectiveDailyRate;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AxisRadius.card),
        border: Border.all(color: axis.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Zone illustration (132 px, fond primarySoft)
          Container(
            height: 132,
            color: axis.primarySoft,
            child: Stack(
              children: [
                // Photo du véhicule ; pictogramme de secours si elle manque ou ne se charge pas.
                if (vehicle.photoUrl.isNotEmpty)
                  Positioned.fill(
                    child: Image.network(
                      vehicle.photoUrl,
                      key: const Key('vehicle-photo'),
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Center(
                        child: Icon(Icons.directions_car_filled_rounded, size: 64, color: theme.colorScheme.primary),
                      ),
                    ),
                  )
                else
                  Center(
                    child: Icon(
                      Icons.directions_car_filled_rounded,
                      key: const Key('vehicle-photo-fallback'),
                      size: 64,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                if (_isDriverOnly)
                  Positioned(
                    top: AxisSpacing.s10,
                    right: AxisSpacing.s10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AxisSpacing.s10,
                        vertical: AxisSpacing.s4,
                      ),
                      decoration: BoxDecoration(
                        color: axis.accentSoft,
                        borderRadius: BorderRadius.circular(AxisRadius.pill),
                      ),
                      child: Text(
                        'Avec chauffeur uniquement',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: axis.onAccentSoft,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Corps de la carte
          Padding(
            padding: const EdgeInsets.all(AxisSpacing.s14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (vehicle.category.trim().isNotEmpty)
                            Text(
                              vehicle.category.toUpperCase(),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          const SizedBox(height: AxisSpacing.s4),
                          Text(
                            vehicle.name,
                            style: theme.textTheme.titleMedium,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AxisSpacing.s12),
                    if (_unavailableInSelectedMode)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '—',
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: axis.textMuted,
                            ),
                          ),
                          Text(
                            !withDriver
                                ? 'non disponible sans chauffeur'
                                : 'non disponible avec chauffeur',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: axis.textMuted,
                            ),
                          ),
                        ],
                      )
                    else if (rate != null)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            formatMoney(rate, 'XOF'),
                            style: AxisTypography.price.copyWith(
                              color: theme.colorScheme.primary,
                            ),
                          ),
                          Text(
                            'FCFA / jour',
                            style: theme.textTheme.labelSmall,
                          ),
                        ],
                      )
                    else
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            'À renseigner',
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: axis.textMuted,
                            ),
                          ),
                          Text(
                            'Tarif / jour',
                            style: theme.textTheme.labelSmall,
                          ),
                        ],
                      ),
                  ],
                ),

                const SizedBox(height: AxisSpacing.s12),

                // Puces de caractéristiques issues de l'API
                Wrap(
                  spacing: AxisSpacing.s8,
                  runSpacing: AxisSpacing.s8,
                  children: [
                    if ('${vehicle.brand} ${vehicle.modelName}'.trim().isNotEmpty)
                      _CharacteristicChip(
                        icon: Icons.directions_car_outlined,
                        label: '${vehicle.brand} ${vehicle.modelName}'.trim(),
                      ),
                    if (vehicle.transmissionDisplay.isNotEmpty)
                      _CharacteristicChip(icon: Icons.settings_outlined, label: vehicle.transmissionDisplay),
                    if (vehicle.fuelDisplay.isNotEmpty)
                      _CharacteristicChip(icon: Icons.local_gas_station_outlined, label: vehicle.fuelDisplay),
                    if (vehicle.capacity != null)
                      _CharacteristicChip(
                        icon: Icons.people_outline_rounded,
                        label: '${vehicle.capacity} places',
                      ),
                    if (vehicle.category.trim().isNotEmpty)
                      _CharacteristicChip(
                        icon: Icons.directions_car_outlined,
                        label: vehicle.category,
                      ),
                    if (vehicle.description.trim().isNotEmpty)
                      _CharacteristicChip(
                        icon: Icons.info_outline_rounded,
                        label: vehicle.description,
                      ),
                    if (vehicle.baseLocation != null &&
                        vehicle.baseLocation!.name.trim().isNotEmpty)
                      _CharacteristicChip(
                        icon: Icons.place_outlined,
                        label: vehicle.baseLocation!.name,
                      ),
                  ],
                ),

                const SizedBox(height: AxisSpacing.s14),

                if (!vehicle.rentable)
                  const AxisButton(
                    key: Key('vehicle-unavailable'),
                    label: 'Indisponible',
                    variant: AxisButtonVariant.outline,
                    height: AxisSizes.minTarget,
                    onPressed: null,
                  )
                else if (_unavailableInSelectedMode)
                  AxisButton(
                    label: !withDriver
                        ? 'Voir avec chauffeur'
                        : 'Voir sans chauffeur',
                    variant: AxisButtonVariant.outline,
                    height: AxisSizes.minTarget,
                    onPressed: () => onSwitchMode(!withDriver),
                  )
                else
                  AxisButton(
                    label: 'Réserver',
                    variant: AxisButtonVariant.primary,
                    height: AxisSizes.minTarget,
                    onPressed: onReserve,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CharacteristicChip extends StatelessWidget {
  const _CharacteristicChip({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final axis = context.axis;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AxisSpacing.s8,
        vertical: AxisSpacing.s6,
      ),
      decoration: BoxDecoration(
        color: axis.surfaceSoft,
        borderRadius: BorderRadius.circular(AxisRadius.chip),
        border: Border.all(color: axis.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: AxisSpacing.s14,
            color: axis.textMuted,
          ),
          const SizedBox(width: AxisSpacing.s4),
          Flexible(
            child: Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: axis.textSecondary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _RentalBookingCard extends StatelessWidget {
  const _RentalBookingCard({required this.rental});

  final RentalBooking rental;

  StatusChipVariant get _chipVariant {
    final s = rental.status.toUpperCase();
    if (s.contains('CONFIRM') || s.contains('APPROVED') || s.contains('ACTIVE')) {
      return StatusChipVariant.success;
    }
    if (s.contains('CANCEL') || s.contains('REJECT')) {
      return StatusChipVariant.danger;
    }
    return StatusChipVariant.warning;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AxisCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  '${rental.vehicle.name} · ${rental.reference}',
                  style: theme.textTheme.titleSmall,
                ),
              ),
              const SizedBox(width: AxisSpacing.s8),
              StatusChip(
                label: rental.statusDisplay.isNotEmpty
                    ? rental.statusDisplay
                    : rental.status,
                variant: _chipVariant,
                dense: true,
              ),
            ],
          ),
          const SizedBox(height: AxisSpacing.s6),
          Text(
            '${formatDateTime(rental.startsAt)} → ${formatDateTime(rental.endsAt)}',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: AxisSpacing.s4),
          Text(
            rental.withDriver ? 'Avec chauffeur' : 'Sans chauffeur',
            style: theme.textTheme.labelSmall,
          ),
        ],
      ),
    );
  }
}

class _RentalsSkeletonList extends StatelessWidget {
  const _RentalsSkeletonList();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (int i = 0; i < 2; i++) ...[
          AxisCard(
            padding: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SkeletonBox(
                  height: 132,
                  borderRadius: AxisRadius.card,
                ),
                Padding(
                  padding: const EdgeInsets.all(AxisSpacing.s14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      SkeletonBox(width: 90, height: 12),
                      SizedBox(height: AxisSpacing.s8),
                      SkeletonBox(width: 180, height: 18),
                      SizedBox(height: AxisSpacing.s12),
                      SkeletonBox(height: AxisSizes.minTarget),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AxisSpacing.s14),
        ],
      ],
    );
  }
}

/// Écran de demande de location d'un véhicule (`LocationDetail.html`).
///
/// Aucun paiement n'est effectué dans l'application.
class RentalDetailScreen extends ConsumerStatefulWidget {
  const RentalDetailScreen({
    super.key,
    required this.vehicle,
    this.initialWithDriver = false,
  });

  final Vehicle vehicle;
  final bool initialWithDriver;

  @override
  ConsumerState<RentalDetailScreen> createState() => _RentalDetailScreenState();
}

class _RentalDetailScreenState extends ConsumerState<RentalDetailScreen> {
  late bool _withDriver;
  late DateTime _startsAt;
  late DateTime _endsAt;
  bool _conditionsExpanded = true;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.vehicle.onlyWithDriver) {
      _withDriver = true;
    } else if (!widget.vehicle.driverAvailable) {
      _withDriver = false;
    } else {
      _withDriver = widget.initialWithDriver;
    }
    final tomorrow = beninToday().add(const Duration(days: 1));
    _startsAt = DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 8);
    _endsAt = _startsAt.add(const Duration(days: 2));
  }

  int get _days {
    final diffHours = _endsAt.difference(_startsAt).inHours;
    if (diffHours <= 0) return 1;
    final days = (diffHours / 24).ceil();
    return days < 1 ? 1 : days;
  }

  num? get _effectiveDailyRate {
    if (_withDriver) {
      return widget.vehicle.dailyRateWithDriver ?? widget.vehicle.dailyRate;
    }
    return widget.vehicle.dailyRate;
  }

  String get _estimationLabel {
    final rate = _effectiveDailyRate;
    if (rate == null) return 'À renseigner';
    return formatMoney(rate * _days, 'XOF');
  }

  String get _subtitleSpecs {
    final parts = <String>[];
    if (widget.vehicle.capacity != null) {
      parts.add('${widget.vehicle.capacity} places');
    }
    if (widget.vehicle.description.trim().isNotEmpty) {
      parts.add(widget.vehicle.description.trim());
    }
    if (widget.vehicle.baseLocation != null &&
        widget.vehicle.baseLocation!.name.trim().isNotEmpty) {
      parts.add(widget.vehicle.baseLocation!.name.trim());
    }
    return parts.join(' · ');
  }

  Future<void> _pickDateTime({required bool start}) async {
    final current = start ? _startsAt : _endsAt;
    final firstDate = beninToday();
    final date = await showDatePicker(
      context: context,
      initialDate: current.isBefore(firstDate) ? firstDate : current,
      firstDate: firstDate,
      lastDate: firstDate.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (time == null || !mounted) return;
    final chosen = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    setState(() {
      if (start) {
        _startsAt = chosen;
        if (!_endsAt.isAfter(_startsAt)) {
          _endsAt = _startsAt.add(const Duration(days: 1));
        }
      } else {
        _endsAt = chosen;
      }
    });
  }

  Future<void> _submit() async {
    final user = ref.read(sessionProvider).user;
    if (user == null) {
      context.push('/connexion');
      return;
    }
    final periodError = rentalPeriodError(_startsAt, _endsAt, beninToday());
    if (periodError != null) {
      setState(() => _error = periodError);
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final rental = await ref.read(apiClientProvider).createRental(
            vehicle: widget.vehicle.id,
            startsAt: _startsAt,
            endsAt: _endsAt,
            withDriver: _withDriver,
          );
      if (!mounted) return;
      final message =
          'Demande ${rental.reference} envoyée (${rental.statusDisplay}).';
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop(message);
      } else {
        setState(() => _sending = false);
      }
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _error = error.message;
          _sending = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final axis = context.axis;
    final periodError = rentalPeriodError(_startsAt, _endsAt, beninToday());

    final selfDriveRateLabel = widget.vehicle.dailyRate != null
        ? formatMoney(widget.vehicle.dailyRate!, 'XOF')
        : null;
    final driverRate =
        widget.vehicle.dailyRateWithDriver ?? widget.vehicle.dailyRate;
    final driverRateLabel =
        driverRate != null ? formatMoney(driverRate, 'XOF') : null;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── En-tête visuel du véhicule (`LocationDetail.html`) ─────
                  Container(
                    height: 200,
                    color: axis.primarySoft,
                    child: Stack(
                      children: [
                        Center(
                          child: Icon(
                            Icons.directions_car_filled_rounded,
                            size: 84,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        Positioned(
                          top: AxisSpacing.s16,
                          left: AxisSpacing.screen,
                          child: Container(
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surface,
                              borderRadius: BorderRadius.circular(
                                AxisRadius.small,
                              ),
                              boxShadow: axis.floatingShadow,
                            ),
                            child: Material(
                              type: MaterialType.transparency,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(
                                  AxisRadius.small,
                                ),
                                onTap: () => Navigator.of(context).maybePop(),
                                child: SizedBox(
                                  width: AxisSizes.minTarget,
                                  height: AxisSizes.minTarget,
                                  child: Icon(
                                    Icons.chevron_left_rounded,
                                    color: axis.ink,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ── Feuille principale ─────────────────────────────────────
                  Container(
                    decoration: BoxDecoration(
                      color: theme.scaffoldBackgroundColor,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(AxisRadius.sheet),
                      ),
                    ),
                    padding: const EdgeInsets.fromLTRB(
                      AxisSpacing.screen,
                      AxisSpacing.s20,
                      AxisSpacing.screen,
                      AxisSpacing.s24,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (widget.vehicle.category.trim().isNotEmpty)
                          Text(
                            widget.vehicle.category.toUpperCase(),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        const SizedBox(height: AxisSpacing.s4),
                        Text(
                          widget.vehicle.name,
                          style: theme.textTheme.headlineSmall,
                        ),
                        if (_subtitleSpecs.isNotEmpty) ...[
                          const SizedBox(height: AxisSpacing.s4),
                          Text(
                            _subtitleSpecs,
                            style: theme.textTheme.bodySmall,
                          ),
                        ],

                        const SizedBox(height: AxisSpacing.s16),

                        // ── Formule ──────────────────────────────────────────
                        Text(
                          'FORMULE',
                          style: theme.textTheme.labelSmall,
                        ),
                        const SizedBox(height: AxisSpacing.s8),
                        Row(
                          children: [
                            Expanded(
                              child: ChoiceCard(
                                title: 'Sans chauffeur',
                                subtitle: widget.vehicle.onlyWithDriver
                                    ? 'Non disponible'
                                    : 'Vous conduisez',
                                price: !widget.vehicle.onlyWithDriver
                                    ? selfDriveRateLabel
                                    : null,
                                unit: !widget.vehicle.onlyWithDriver &&
                                        selfDriveRateLabel != null
                                    ? '/j'
                                    : null,
                                selected: !_withDriver,
                                enabled: !widget.vehicle.onlyWithDriver,
                                onTap: () =>
                                    setState(() => _withDriver = false),
                              ),
                            ),
                            const SizedBox(width: AxisSpacing.s10),
                            Expanded(
                              child: ChoiceCard(
                                title: 'Avec chauffeur',
                                subtitle: widget.vehicle.driverAvailable ||
                                        widget.vehicle.onlyWithDriver
                                    ? 'Chauffeur Axis inclus'
                                    : 'Non disponible',
                                price: (widget.vehicle.driverAvailable ||
                                        widget.vehicle.onlyWithDriver)
                                    ? driverRateLabel
                                    : null,
                                unit: (widget.vehicle.driverAvailable ||
                                            widget.vehicle.onlyWithDriver) &&
                                        driverRateLabel != null
                                    ? '/j'
                                    : null,
                                selected: _withDriver,
                                enabled: widget.vehicle.driverAvailable ||
                                    widget.vehicle.onlyWithDriver,
                                onTap: () => setState(() => _withDriver = true),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: AxisSpacing.s16),

                        // ── Dates ────────────────────────────────────────────
                        Text(
                          'DATES',
                          style: theme.textTheme.labelSmall,
                        ),
                        const SizedBox(height: AxisSpacing.s8),
                        AxisCard(
                          padding: const EdgeInsets.all(AxisSpacing.s14),
                          child: Column(
                            children: [
                              _DateRowTile(
                                key: const Key('rental-pickup-date'),
                                icon: Icons.calendar_today_outlined,
                                label: 'PRISE DU VÉHICULE',
                                value: formatDateTime(_startsAt),
                                onTap: () => _pickDateTime(start: true),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: AxisSpacing.s10,
                                ),
                                child: Divider(
                                  height: 1,
                                  color: axis.border,
                                ),
                              ),
                              _DateRowTile(
                                key: const Key('rental-return-date'),
                                icon: Icons.event_available_outlined,
                                label: 'RETOUR DU VÉHICULE',
                                value: formatDateTime(_endsAt),
                                onTap: () => _pickDateTime(start: false),
                              ),
                            ],
                          ),
                        ),
                        if (periodError != null) ...[
                          const SizedBox(height: AxisSpacing.s8),
                          Text(
                            periodError,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: axis.danger,
                            ),
                          ),
                        ],

                        const SizedBox(height: AxisSpacing.s16),

                        // ── Conditions de location ───────────────────────────
                        AxisCard(
                          padding: const EdgeInsets.all(AxisSpacing.s14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              InkWell(
                                key: const Key('rental-conditions-toggle'),
                                onTap: () => setState(
                                  () => _conditionsExpanded =
                                      !_conditionsExpanded,
                                ),
                                borderRadius: BorderRadius.circular(
                                  AxisRadius.small,
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.verified_user_outlined,
                                          size: AxisSizes.icon,
                                          color: theme.colorScheme.primary,
                                        ),
                                        const SizedBox(width: AxisSpacing.s8),
                                        Text(
                                          'Conditions de location',
                                          style: theme.textTheme.titleSmall,
                                        ),
                                      ],
                                    ),
                                    Icon(
                                      _conditionsExpanded
                                          ? Icons.expand_less_rounded
                                          : Icons.expand_more_rounded,
                                      color: axis.textMuted,
                                    ),
                                  ],
                                ),
                              ),
                              if (_conditionsExpanded) ...[
                                const SizedBox(height: AxisSpacing.s10),
                                if (!_withDriver) ...[
                                  const _ConditionBullet(
                                    text:
                                        'Permis valide depuis au moins 2 ans, conducteur de 23 ans minimum',
                                  ),
                                  const SizedBox(height: AxisSpacing.s6),
                                  const _ConditionBullet(
                                    text:
                                        'Caution remboursable (montant communiqué par l’agence)',
                                  ),
                                  const SizedBox(height: AxisSpacing.s6),
                                ],
                                const _ConditionBullet(
                                  text:
                                      'Carburant à votre charge (rendu au même niveau)',
                                ),
                                const SizedBox(height: AxisSpacing.s6),
                                const _ConditionBullet(
                                  text:
                                      'Circulation au Bénin uniquement (hors frontières sur accord écrit)',
                                ),
                              ],
                            ],
                          ),
                        ),

                        const SizedBox(height: AxisSpacing.s14),

                        // ── Bandeau d'information (aucun paiement dans l'app) ─
                        Container(
                          padding: const EdgeInsets.all(AxisSpacing.s12),
                          decoration: BoxDecoration(
                            color: axis.primarySoft,
                            borderRadius: BorderRadius.circular(
                              AxisRadius.button,
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.info_outline_rounded,
                                size: AxisSizes.icon,
                                color: theme.colorScheme.primary,
                              ),
                              const SizedBox(width: AxisSpacing.s10),
                              Expanded(
                                child: Text(
                                  'Aucun paiement maintenant. L’agence vous appelle pour confirmer, puis vous réglez à la remise du véhicule.',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: axis.primaryDark,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        if (_error != null) ...[
                          const SizedBox(height: AxisSpacing.s12),
                          Text(
                            _error!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: axis.danger,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Pied de page : estimation + bouton d'envoi ────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(
              AxisSpacing.screen,
              AxisSpacing.s12,
              AxisSpacing.screen,
              AxisSpacing.s20,
            ),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border(top: BorderSide(color: axis.border)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Estimation · $_days ${_days > 1 ? 'jours' : 'jour'}',
                        style: theme.textTheme.labelSmall,
                      ),
                      const SizedBox(height: AxisSpacing.s4),
                      Text(
                        _estimationLabel,
                        style: AxisTypography.price.copyWith(
                          color: axis.ink,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AxisSpacing.s12),
                Expanded(
                  child: AxisButton(
                    label: 'Envoyer la demande',
                    loading: _sending,
                    onPressed: periodError != null ? null : _submit,
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

class _DateRowTile extends StatelessWidget {
  const _DateRowTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final axis = context.axis;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AxisRadius.small),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: axis.primarySoft,
                    borderRadius: BorderRadius.circular(AxisRadius.small),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    icon,
                    size: AxisSizes.icon,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(width: AxisSpacing.s10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: theme.textTheme.labelSmall,
                      ),
                      const SizedBox(height: AxisSpacing.s4),
                      Text(
                        value,
                        style: theme.textTheme.titleSmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Text(
            'Modifier',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _ConditionBullet extends StatelessWidget {
  const _ConditionBullet({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final axis = context.axis;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: AxisSpacing.s6),
          child: Container(
            width: AxisSpacing.s6,
            height: AxisSpacing.s6,
            decoration: BoxDecoration(
              color: axis.textMuted,
              shape: BoxShape.circle,
            ),
          ),
        ),
        const SizedBox(width: AxisSpacing.s8),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(
              color: axis.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}
