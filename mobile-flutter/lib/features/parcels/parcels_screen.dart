import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/formatters.dart';
import '../../core/models.dart';
import '../../core/session.dart';
import '../../core/theme/axis_spacing.dart';
import '../../core/theme/axis_tokens.dart';
import '../../core/widgets/axis_card.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/skeleton_box.dart';
import '../../core/widgets/status_chip.dart';
import '../../core/widgets/timeline_steps.dart';

/// Écran client de suivi de colis (`ColisSuiviPhotos.html`).
class ParcelsScreen extends ConsumerStatefulWidget {
  const ParcelsScreen({
    super.key,
    this.initialTracking,
  });

  /// Permet d'injecter un état initial lors des tests de composants.
  final ParcelTracking? initialTracking;

  @override
  ConsumerState<ParcelsScreen> createState() => _ParcelsScreenState();
}

class _ParcelsScreenState extends ConsumerState<ParcelsScreen> {
  late final TextEditingController _code;
  ParcelTracking? _tracking;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tracking = widget.initialTracking;
    _code = TextEditingController(
      text: widget.initialTracking?.trackingNumber ?? '',
    );
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _track() async {
    final code = _code.text.trim();
    if (code.isEmpty) {
      setState(() {
        _error = 'Saisissez le code inscrit sur le récépissé de dépôt.';
        _tracking = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final tracking = await ref.read(apiClientProvider).trackParcel(code);
      if (!mounted) return;
      setState(() {
        _tracking = tracking;
        _loading = false;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _tracking = null;
        _loading = false;
      });
    }
  }

  (String, StatusChipVariant) _resolveStatus(ParcelTracking tracking) {
    final steps = tracking.steps;
    if (steps.isEmpty) {
      return ('Enregistré', StatusChipVariant.info);
    }
    final allDone = steps.every((s) => s.done && !s.current);
    if (allDone) {
      return (steps.last.label, StatusChipVariant.success);
    }
    for (final step in steps) {
      if (step.current) {
        return (step.label, StatusChipVariant.warning);
      }
    }
    final lastDone = steps.lastIndexWhere((s) => s.done);
    if (lastDone >= 0) {
      return (steps[lastDone].label, StatusChipVariant.info);
    }
    return (steps.first.label, StatusChipVariant.neutral);
  }

  List<TimelineStepItem> _buildTimelineSteps(List<ParcelStep> steps) {
    return steps.map((step) {
      final state = step.current
          ? TimelineStepState.now
          : (step.done ? TimelineStepState.done : TimelineStepState.todo);
      final subtitle = step.reachedAt != null
          ? formatDateTime(step.reachedAt!)
          : (step.current ? 'En cours' : 'À venir');
      return TimelineStepItem(
        title: step.label,
        meta: subtitle,
        state: state,
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final axis = context.axis;
    final onPrimary = theme.colorScheme.onPrimary;
    final tracking = _tracking;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: AxisSpacing.s24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── En-tête bleu marine avec barre de recherche (`ColisSuiviPhotos.html`) ──
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
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Material(
                        color: onPrimary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(AxisRadius.small),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(AxisRadius.small),
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
                      Expanded(
                        child: Text(
                          'Suivi de colis',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            color: onPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AxisSpacing.s14),
                  Container(
                    padding: const EdgeInsets.all(AxisSpacing.s6),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(AxisRadius.button),
                    ),
                    child: Row(
                      children: [
                        const SizedBox(width: AxisSpacing.s8),
                        Icon(
                          Icons.search_rounded,
                          size: AxisSizes.icon,
                          color: axis.textMuted,
                        ),
                        const SizedBox(width: AxisSpacing.s8),
                        Expanded(
                          child: TextField(
                            key: const Key('parcel-tracking-input'),
                            controller: _code,
                            textCapitalization: TextCapitalization.characters,
                            onSubmitted: (_) => _track(),
                            style: theme.textTheme.titleSmall,
                            decoration: InputDecoration(
                              hintText: 'Code de suivi',
                              isDense: true,
                              filled: false,
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: AxisSpacing.s8,
                              ),
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                            ),
                          ),
                        ),
                        const SizedBox(width: AxisSpacing.s8),
                        Material(
                          color: axis.accent,
                          borderRadius: BorderRadius.circular(AxisRadius.small),
                          child: InkWell(
                            key: const Key('parcel-track-button'),
                            borderRadius: BorderRadius.circular(
                              AxisRadius.small,
                            ),
                            onTap: _loading ? null : _track,
                            child: Container(
                              constraints: const BoxConstraints(
                                minHeight: AxisSizes.minTarget,
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: AxisSpacing.s14,
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                'Suivre',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ── Corps de l'écran ─────────────────────────────────────────────
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
                  if (_loading)
                    const _ParcelTrackingSkeleton()
                  else if (_error != null)
                    EmptyState(
                      title: 'Colis introuvable',
                      description: _error!,
                      icon: Icons.inventory_2_outlined,
                      actionLabel: 'Réessayer',
                      onAction: _track,
                    )
                  else if (tracking == null)
                    const EmptyState(
                      title: 'Suivez votre colis',
                      description:
                          'Saisissez le code inscrit sur votre récépissé de dépôt pour afficher le statut et l’historique d’acheminement.',
                      icon: Icons.local_shipping_outlined,
                    )
                  else ...[
                    // Carte principale du colis
                    AxisCard(
                      child: Builder(
                        builder: (context) {
                          final (statusLabel, statusVariant) = _resolveStatus(
                            tracking,
                          );
                          final hasMeta = (tracking.senderLabel != null &&
                                  tracking.senderLabel!.trim().isNotEmpty) ||
                              (tracking.recipientLabel != null &&
                                  tracking.recipientLabel!.trim().isNotEmpty) ||
                              (tracking.description != null &&
                                  tracking.description!.trim().isNotEmpty);

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  StatusChip(
                                    label: statusLabel,
                                    variant: statusVariant,
                                    icon: Icons.local_shipping_outlined,
                                  ),
                                  const SizedBox(width: AxisSpacing.s8),
                                  Flexible(
                                    child: Text(
                                      tracking.trackingNumber,
                                      style: theme.textTheme.labelMedium
                                          ?.copyWith(color: axis.textMuted),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: AxisSpacing.s12),
                              Text(
                                '${tracking.origin} → ${tracking.destination}',
                                style: theme.textTheme.titleLarge,
                              ),

                              if (tracking.photos.isNotEmpty) ...[
                                const SizedBox(height: AxisSpacing.s14),
                                ParcelPhotoGallery(photos: tracking.photos),
                              ],

                              if (hasMeta) ...[
                                const SizedBox(height: AxisSpacing.s12),
                                if (tracking.senderLabel != null &&
                                    tracking.senderLabel!.trim().isNotEmpty)
                                  _ParcelMetaRow(
                                    label: 'Expéditeur',
                                    value: tracking.senderLabel!,
                                  ),
                                if (tracking.recipientLabel != null &&
                                    tracking.recipientLabel!.trim().isNotEmpty)
                                  _ParcelMetaRow(
                                    label: 'Destinataire',
                                    value: tracking.recipientLabel!,
                                  ),
                                if (tracking.description != null &&
                                    tracking.description!.trim().isNotEmpty)
                                  _ParcelMetaRow(
                                    label: 'Colis',
                                    value: tracking.description!,
                                    showBottomBorder: false,
                                  ),
                              ],
                            ],
                          );
                        },
                      ),
                    ),

                    const SizedBox(height: AxisSpacing.s14),

                    // Carte de la frise chronologique (TimelineSteps)
                    AxisCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'ÉTAPES',
                            style: theme.textTheme.labelSmall,
                          ),
                          const SizedBox(height: AxisSpacing.s12),
                          if (tracking.steps.isEmpty)
                            Text(
                              'Aucune étape enregistrée.',
                              style: theme.textTheme.bodySmall,
                            )
                          else
                            TimelineSteps(
                              steps: _buildTimelineSteps(tracking.steps),
                            ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Galerie de 1 à 3 photos prises au dépôt avec agrandissement au toucher (`ColisSuiviPhotos.html`).
///
/// Composant en UI pure tant que l'endpoint `/client/parcels/track/` ne renvoie pas `photos`.
class ParcelPhotoGallery extends StatelessWidget {
  const ParcelPhotoGallery({
    super.key,
    required this.photos,
  });

  final List<String> photos;

  void _openLightbox(BuildContext context, int index) {
    final visiblePhotos = photos.take(3).toList();
    final photoUrl = visiblePhotos[index];

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        final axis = dialogContext.axis;
        final onPrimary = theme.colorScheme.onPrimary;

        return Dialog(
          backgroundColor: axis.ink,
          insetPadding: const EdgeInsets.all(AxisSpacing.screen),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AxisRadius.card),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AxisSpacing.s16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Photo ${index + 1} / ${visiblePhotos.length}',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: onPrimary,
                        ),
                      ),
                      IconButton(
                        key: const Key('parcel-photo-close'),
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        icon: Icon(
                          Icons.close_rounded,
                          color: onPrimary,
                        ),
                        tooltip: 'Fermer',
                      ),
                    ],
                  ),
                  const SizedBox(height: AxisSpacing.s12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AxisRadius.button),
                    child: SizedBox(
                      height: 240,
                      child: Container(
                        color: axis.primarySoft,
                        child: _ParcelPhotoImage(
                          url: photoUrl,
                          enlarged: true,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AxisSpacing.s12),
                  Text(
                    'Photo prise au dépôt en agence Axis',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: onPrimary.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final axis = context.axis;
    final onPrimary = theme.colorScheme.onPrimary;
    final visiblePhotos = photos.take(3).toList();
    if (visiblePhotos.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(AxisSpacing.s12),
      decoration: BoxDecoration(
        color: axis.surfaceSoft,
        borderRadius: BorderRadius.circular(AxisRadius.button),
        border: Border.all(color: axis.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.photo_camera_outlined,
                    size: AxisSpacing.s16,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: AxisSpacing.s6),
                  Text(
                    'Photos prises au dépôt',
                    style: theme.textTheme.labelMedium,
                  ),
                ],
              ),
              Text(
                '${visiblePhotos.length} / 3 · toucher pour agrandir',
                style: theme.textTheme.labelSmall,
              ),
            ],
          ),
          const SizedBox(height: AxisSpacing.s10),
          Row(
            children: [
              for (int i = 0; i < visiblePhotos.length; i++) ...[
                if (i > 0) const SizedBox(width: AxisSpacing.s8),
                Expanded(
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: Material(
                      color: axis.primarySoft,
                      borderRadius: BorderRadius.circular(AxisRadius.small),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        key: Key('parcel-photo-thumb-$i'),
                        onTap: () => _openLightbox(context, i),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            _ParcelPhotoImage(
                              url: visiblePhotos[i],
                              enlarged: false,
                            ),
                            Positioned(
                              right: AxisSpacing.s6,
                              bottom: AxisSpacing.s6,
                              child: Container(
                                width: 22,
                                height: 22,
                                decoration: BoxDecoration(
                                  color: axis.ink.withValues(alpha: 0.55),
                                  borderRadius: BorderRadius.circular(
                                    AxisRadius.chip,
                                  ),
                                ),
                                alignment: Alignment.center,
                                child: Icon(
                                  Icons.zoom_in_rounded,
                                  size: AxisSpacing.s14,
                                  color: onPrimary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _ParcelPhotoImage extends StatelessWidget {
  const _ParcelPhotoImage({
    required this.url,
    required this.enlarged,
  });

  final String url;
  final bool enlarged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isNetwork = url.startsWith('http://') || url.startsWith('https://');
    if (isNetwork) {
      return Image.network(
        url,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _placeholder(theme),
      );
    }
    return _placeholder(theme);
  }

  Widget _placeholder(ThemeData theme) {
    return Center(
      child: Icon(
        Icons.inventory_2_outlined,
        size: enlarged ? 72 : 36,
        color: theme.colorScheme.primary,
      ),
    );
  }
}

class _ParcelMetaRow extends StatelessWidget {
  const _ParcelMetaRow({
    required this.label,
    required this.value,
    this.showBottomBorder = true,
  });

  final String label;
  final String value;
  final bool showBottomBorder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final axis = context.axis;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: AxisSpacing.s6),
      decoration: showBottomBorder
          ? BoxDecoration(
              border: Border(bottom: BorderSide(color: axis.border)),
            )
          : null,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(width: AxisSpacing.s12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: theme.textTheme.titleSmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _ParcelTrackingSkeleton extends StatelessWidget {
  const _ParcelTrackingSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AxisCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              SkeletonBox(width: 110, height: 22),
              SizedBox(height: AxisSpacing.s12),
              SkeletonBox(width: 200, height: 24),
              SizedBox(height: AxisSpacing.s14),
              SkeletonBox(height: 96),
            ],
          ),
        ),
        const SizedBox(height: AxisSpacing.s14),
        AxisCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              SkeletonBox(width: 80, height: 14),
              SizedBox(height: AxisSpacing.s12),
              SkeletonBox(height: 44),
              SizedBox(height: AxisSpacing.s10),
              SkeletonBox(height: 44),
              SizedBox(height: AxisSpacing.s10),
              SkeletonBox(height: 44),
            ],
          ),
        ),
      ],
    );
  }
}
