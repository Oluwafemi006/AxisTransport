import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api_client.dart';
import '../../../core/formatters.dart';
import '../../../core/session.dart';
import '../../../core/theme/axis_spacing.dart';
import '../../../core/theme/axis_tokens.dart';
import '../../../core/widgets/route_stops_bar.dart';
import '../../../core/widgets/skeleton_box.dart';
import '../../sales/sale_models.dart';

/// Incrémenté après une vente ou un scan : l'accueil recharge alors ses compteurs.
class StaffActivity extends Notifier<int> {
  @override
  int build() => 0;

  void changed() => state++;
}

final staffActivityProvider = NotifierProvider<StaffActivity, int>(
  StaffActivity.new,
);

/// Résumé d'activité journalier du contrôleur (maquette `CtrlAccueil.html`).
class ControllerDaySummary {
  const ControllerDaySummary({
    required this.scannedTickets,
    required this.soldTickets,
    required this.parcelsCount,
    required this.cashAmountFcfa,
    required this.mobileMoneyAmountFcfa,
  });

  final int scannedTickets;
  final int soldTickets;
  final int parcelsCount;
  final num cashAmountFcfa;
  final num mobileMoneyAmountFcfa;

  factory ControllerDaySummary.fromJson(Map<String, dynamic> json) =>
      ControllerDaySummary(
        scannedTickets: json['scanned_tickets'] as int? ?? 0,
        soldTickets: json['sold_tickets'] as int? ?? 0,
        parcelsCount: json['parcels'] as int? ?? 0,
        cashAmountFcfa: json['cash_fcfa'] as num? ?? 0,
        mobileMoneyAmountFcfa: json['mobile_money_fcfa'] as num? ?? 0,
      );
}

/// Accueil de l'espace contrôleur (`CtrlAccueil.html`).
class StaffHomeScreen extends ConsumerStatefulWidget {
  const StaffHomeScreen({
    super.key,
    this.activeTrip,
    this.stops,
    this.nextStopName,
    this.onConfirmArrival,
    this.daySummary,
  });

  final SaleTrip? activeTrip;
  final List<RouteStopItem>? stops;
  final String? nextStopName;
  final VoidCallback? onConfirmArrival;
  final ControllerDaySummary? daySummary;

  @override
  ConsumerState<StaffHomeScreen> createState() => _StaffHomeScreenState();
}

class _StaffHomeScreenState extends ConsumerState<StaffHomeScreen> {
  SaleTrip? _loadedTrip;
  ControllerDaySummary? _summary;
  bool _loadingTrip = false;
  bool _offline = false;

  @override
  void initState() {
    super.initState();
    if (widget.activeTrip == null) {
      _fetchActiveTrip();
    }
    if (widget.daySummary == null) _fetchSummary();
  }

  Future<void> _fetchSummary() async {
    try {
      final payload = await ref.read(apiClientProvider).saleSummary();
      if (mounted) {
        setState(() => _summary = ControllerDaySummary.fromJson(payload));
      }
    } catch (_) {
      // Sans réponse du serveur, les compteurs restent à « — » : rien n'est estimé ici.
    }
  }

  Future<void> _fetchActiveTrip() async {
    setState(() {
      _loadingTrip = true;
    });
    try {
      final payload = await ref.read(apiClientProvider).saleOptions();
      final rawTrips = payload['trips'];
      final trips = rawTrips is List
          ? rawTrips
                .whereType<Map>()
                .map((item) => SaleTrip.fromJson(Map<String, dynamic>.from(item)))
                .toList()
          : const <SaleTrip>[];
      if (!mounted) return;
      setState(() {
        _loadedTrip = trips.isNotEmpty ? trips.first : null;
        _offline = false;
        _loadingTrip = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _offline = e.statusCode == null;
        _loadingTrip = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingTrip = false;
      });
    }
  }

  /// Le prochain arrêt est facultatif : le contrôleur peut confirmer directement le terminus.
  Future<void> _confirmArrival(SaleTrip trip, String stopName) async {
    final stop = trip.stops.where((item) => item.name == stopName).firstOrNull;
    if (stop == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(apiClientProvider).confirmArrival(trip.id, stop.id);
      messenger.showSnackBar(
        SnackBar(content: Text('Arrivée à $stopName confirmée. L’agence est informée.')),
      );
      await _fetchActiveTrip();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  List<RouteStopItem> _buildStopsForTrip(SaleTrip trip) {
    if (widget.stops != null && widget.stops!.isNotEmpty) {
      return widget.stops!;
    }
    if (trip.stops.length >= 2) {
      final lastArrived = trip.stops.lastIndexWhere(
        (stop) => trip.arrivedStopIds.contains(stop.id),
      );
      final current = lastArrived < 0 ? 0 : lastArrived;
      return [
        for (var index = 0; index < trip.stops.length; index++)
          RouteStopItem(
            name: trip.stops[index].name,
            state: index == current
                ? RouteStopState.current
                : index < current
                ? RouteStopState.passed
                : RouteStopState.upcoming,
          ),
      ];
    }
    final parts = trip.label
        .split('→')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (parts.length >= 2) {
      return [
        RouteStopItem(name: parts.first, state: RouteStopState.current),
        ...parts
            .sublist(1, parts.length - 1)
            .map((name) => RouteStopItem(name: name, state: RouteStopState.upcoming)),
        RouteStopItem(name: parts.last, state: RouteStopState.upcoming),
      ];
    }
    return [RouteStopItem(name: trip.label, state: RouteStopState.current)];
  }

  String? _resolveNextStop(List<RouteStopItem> stops) {
    if (widget.nextStopName != null && widget.nextStopName!.trim().isNotEmpty) {
      return widget.nextStopName!.trim();
    }
    for (final stop in stops) {
      if (stop.state == RouteStopState.upcoming) {
        return stop.name;
      }
    }
    return stops.length >= 2 ? stops.last.name : null;
  }

  @override
  Widget build(BuildContext context) {
    final axis = context.axis;
    final theme = Theme.of(context);
    final onDark = theme.colorScheme.onPrimary;
    final user = ref.watch(sessionProvider).user;
    final firstName = (user?.firstName ?? '').trim();
    final displayName = firstName.isNotEmpty
        ? firstName
        : ((user?.username ?? '').trim().isNotEmpty
              ? user!.username
              : 'Contrôleur');

    final trip = widget.activeTrip ?? _loadedTrip;
    final stops = trip != null ? _buildStopsForTrip(trip) : const <RouteStopItem>[];
    final nextStop = _resolveNextStop(stops);
    final lastStop = stops.isNotEmpty ? stops.last.name : null;
    final finalStop = lastStop != nextStop ? lastStop : null;
    final summary = widget.daySummary ?? _summary;
    ref.listen(staffActivityProvider, (_, _) => _fetchSummary());

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: RefreshIndicator(
        color: axis.ink,
        onRefresh: _fetchActiveTrip,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            // En-tête contrôleur (fond ink + badge CONTRÔLEUR + trajet en cours)
            Container(
              width: double.infinity,
              color: axis.ink,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AxisSpacing.lg,
                    AxisSpacing.sm,
                    AxisSpacing.lg,
                    AxisSpacing.lg,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: AxisSpacing.xs,
                                    vertical: AxisSpacing.xxs,
                                  ),
                                  decoration: BoxDecoration(
                                    color: axis.accent,
                                    borderRadius: BorderRadius.circular(
                                      AxisRadius.xs,
                                    ),
                                  ),
                                  child: Text(
                                    'CONTRÔLEUR',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: axis.ink,
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: AxisSpacing.xs),
                                Text(
                                  'Bonjour, $displayName',
                                  style: theme.textTheme.headlineSmall?.copyWith(
                                    color: onDark,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: AxisSpacing.sm),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AxisSpacing.sm,
                              vertical: AxisSpacing.xs,
                            ),
                            decoration: BoxDecoration(
                              color: onDark.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(
                                AxisRadius.pill,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 7,
                                  height: 7,
                                  decoration: BoxDecoration(
                                    color: _offline
                                        ? axis.warning
                                        : axis.success,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: AxisSpacing.xs),
                                Text(
                                  _offline ? 'Hors ligne' : 'En ligne',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: onDark,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AxisSpacing.md),
                      _ActiveTripCard(
                        loading: _loadingTrip,
                        trip: trip,
                        stops: stops,
                        nextStop: nextStop,
                        onConfirmArrival:
                            widget.onConfirmArrival ??
                            (trip != null && nextStop != null
                                ? () => _confirmArrival(trip, nextStop)
                                : null),
                        finalStop: finalStop,
                        onConfirmFinal: trip != null && finalStop != null
                            ? () => _confirmArrival(trip, finalStop)
                            : null,
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Corps : Actions + Ma journée
            Padding(
              padding: const EdgeInsets.all(AxisSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ACTIONS',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: axis.textSecondary,
                      letterSpacing: 0.7,
                    ),
                  ),
                  const SizedBox(height: AxisSpacing.sm),

                  // Tuile principale : Scanner un billet
                  Material(
                    color: axis.accent,
                    borderRadius: BorderRadius.circular(AxisRadius.lg),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(AxisRadius.lg),
                      onTap: () => context.go('/scanner'),
                      child: Padding(
                        padding: const EdgeInsets.all(AxisSpacing.md),
                        child: Row(
                          children: [
                            Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                color: axis.ink.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(
                                  AxisRadius.md,
                                ),
                              ),
                              alignment: Alignment.center,
                              child: Icon(
                                Icons.qr_code_scanner_rounded,
                                color: axis.ink,
                                size: 28,
                              ),
                            ),
                            const SizedBox(width: AxisSpacing.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Scanner un billet',
                                    style: theme.textTheme.titleMedium?.copyWith(
                                      color: axis.ink,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Contrôle à l’embarquement',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: axis.ink.withValues(alpha: 0.8),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.chevron_right_rounded,
                              color: axis.ink,
                              size: 24,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AxisSpacing.sm),

                  // Grille 2 colonnes : Vendre un billet / Enregistrer un colis
                  Row(
                    children: [
                      Expanded(
                        child: _SecondaryActionTile(
                          icon: Icons.confirmation_number_outlined,
                          title: 'Vendre un billet',
                          subtitle: 'Passager monté en route',
                          onTap: () => context.go('/vendre'),
                        ),
                      ),
                      const SizedBox(width: AxisSpacing.sm),
                      Expanded(
                        child: _SecondaryActionTile(
                          icon: Icons.inventory_2_outlined,
                          title: 'Enregistrer un colis',
                          subtitle: 'Photo obligatoire',
                          onTap: () => context.push('/staff/colis'),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: AxisSpacing.lg),

                  // Section Ma journée
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'MA JOURNÉE',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: axis.textSecondary,
                          letterSpacing: 0.7,
                        ),
                      ),
                      if (trip != null)
                        Flexible(
                          child: Text(
                            trip.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: axis.textSecondary,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: AxisSpacing.sm),

                  Container(
                    padding: const EdgeInsets.all(AxisSpacing.md),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(AxisRadius.lg),
                      border: Border.all(color: axis.border),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _DayStatCell(
                                value: summary != null
                                    ? '${summary.scannedTickets}'
                                    : '—',
                                label: 'billets scannés',
                              ),
                            ),
                            Container(
                              width: 1,
                              height: 36,
                              color: axis.border,
                            ),
                            Expanded(
                              child: _DayStatCell(
                                value: summary != null
                                    ? '${summary.soldTickets}'
                                    : '—',
                                label: 'billets vendus',
                              ),
                            ),
                            Container(
                              width: 1,
                              height: 36,
                              color: axis.border,
                            ),
                            Expanded(
                              child: _DayStatCell(
                                value: summary != null
                                    ? '${summary.parcelsCount}'
                                    : '—',
                                label: 'colis',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AxisSpacing.sm),
                        Divider(height: 1, color: axis.border),
                        const SizedBox(height: AxisSpacing.sm),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                'Espèces à remettre',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: axis.textSecondary,
                                ),
                              ),
                            ),
                            const SizedBox(width: AxisSpacing.xs),
                            Text(
                              summary != null
                                  ? formatMoney(summary.cashAmountFcfa, 'FCFA')
                                  : '—',
                              style: theme.textTheme.titleSmall?.copyWith(
                                color: axis.ink,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AxisSpacing.xs),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                'Mobile Money (encaissé auto)',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: axis.textSecondary,
                                ),
                              ),
                            ),
                            const SizedBox(width: AxisSpacing.xs),
                            Text(
                              summary != null
                                  ? formatMoney(
                                      summary.mobileMoneyAmountFcfa,
                                      'FCFA',
                                    )
                                  : '—',
                              style: theme.textTheme.titleSmall?.copyWith(
                                color: summary != null
                                    ? axis.success
                                    : axis.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActiveTripCard extends StatelessWidget {
  const _ActiveTripCard({
    required this.loading,
    required this.trip,
    required this.stops,
    required this.nextStop,
    required this.onConfirmArrival,
    this.finalStop,
    this.onConfirmFinal,
  });

  final bool loading;
  final SaleTrip? trip;
  final List<RouteStopItem> stops;
  final String? nextStop;
  final VoidCallback? onConfirmArrival;
  final String? finalStop;
  final VoidCallback? onConfirmFinal;

  @override
  Widget build(BuildContext context) {
    final axis = context.axis;
    final theme = Theme.of(context);
    final onDark = theme.colorScheme.onPrimary;

    if (loading) {
      return const SkeletonBox(
        height: 108,
        borderRadius: AxisRadius.lg,
      );
    }

    final currentTrip = trip;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AxisSpacing.md),
      decoration: BoxDecoration(
        color: onDark.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AxisRadius.lg),
        border: Border.all(color: onDark.withValues(alpha: 0.10)),
      ),
      child: currentTrip == null
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'TRAJET EN COURS',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: axis.borderStrong,
                  ),
                ),
                const SizedBox(height: AxisSpacing.xs),
                Text(
                  'Aucun départ actif assigné pour le moment',
                  style: theme.textTheme.bodyMedium?.copyWith(color: onDark),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'TRAJET EN COURS',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: axis.borderStrong,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            currentTrip.label,
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: onDark,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AxisSpacing.sm),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          currentTrip.departureAt != null
                              ? 'Départ ${formatTime(currentTrip.departureAt!)}'
                              : 'En cours',
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: axis.accent,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${currentTrip.availableSeats} pl. libres',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: axis.borderStrong,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                if (stops.isNotEmpty) ...[
                  const SizedBox(height: AxisSpacing.sm),
                  RouteStopsBar(stops: stops, isDark: true),
                ],
                if (nextStop != null) ...[
                  const SizedBox(height: AxisSpacing.sm),
                  InkWell(
                    borderRadius: BorderRadius.circular(AxisRadius.md),
                    onTap: onConfirmArrival,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: AxisSpacing.sm,
                        vertical: AxisSpacing.sm,
                      ),
                      decoration: BoxDecoration(
                        color: axis.accent.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(AxisRadius.md),
                        border: Border.all(
                          color: axis.accent.withValues(alpha: 0.45),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.check_rounded,
                            size: 16,
                            color: axis.accent,
                          ),
                          const SizedBox(width: AxisSpacing.xs),
                          Flexible(
                            child: Text(
                              'Confirmer l’arrivée à $nextStop',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: axis.accent,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (finalStop != null)
                    TextButton(
                      onPressed: onConfirmFinal,
                      child: Text(
                        'Arrivée finale à $finalStop',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: onDark,
                        ),
                      ),
                    ),
                ],
              ],
            ),
    );
  }
}

class _SecondaryActionTile extends StatelessWidget {
  const _SecondaryActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final axis = context.axis;
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(AxisRadius.lg),
      child: InkWell(
        borderRadius: BorderRadius.circular(AxisRadius.lg),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(AxisSpacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AxisRadius.lg),
            border: Border.all(color: axis.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: axis.surfaceSoft,
                  borderRadius: BorderRadius.circular(AxisRadius.md),
                ),
                alignment: Alignment.center,
                child: Icon(icon, color: axis.ink, size: 20),
              ),
              const SizedBox(height: AxisSpacing.sm),
              Text(title, style: theme.textTheme.titleSmall),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: axis.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DayStatCell extends StatelessWidget {
  const _DayStatCell({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final axis = context.axis;
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(value, style: theme.textTheme.headlineSmall),
        const SizedBox(height: 2),
        Text(
          label,
          textAlign: TextAlign.center,
          style: theme.textTheme.labelSmall?.copyWith(
            color: axis.textSecondary,
          ),
        ),
      ],
    );
  }
}
