import 'package:flutter/material.dart';

import '../theme/axis_spacing.dart';
import '../theme/axis_tokens.dart';

/// Donnée d'une photo pour [PhotoSlots].
class PhotoSlotItem {
  const PhotoSlotItem({
    required this.id,
    this.imageUrl,
    this.imageBytes,
    this.label,
  });

  final String id;
  final String? imageUrl;
  final List<int>? imageBytes;
  final String? label;
}

/// Grille d'emplacements photo pour l'enregistrement de colis.
///
/// Gère jusqu'à [maxPhotos] cases avec aperçu, suppression et ajout.
class PhotoSlots extends StatelessWidget {
  const PhotoSlots({
    super.key,
    required this.photos,
    this.maxPhotos = 3,
    required this.onAdd,
    required this.onRemove,
    this.title = 'Photos du colis',
    this.subtitle = '1 photo obligatoire, 3 au maximum. Montrez l’emballage sous plusieurs angles.',
  });

  final List<PhotoSlotItem> photos;
  final int maxPhotos;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final tokens = context.axis;
    final theme = Theme.of(context);
    final count = photos.length;
    final hasPhoto = count > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // En-tête : Titre + Badge "n / max"
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                fontSize: 15,
                color: tokens.ink,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: hasPhoto ? tokens.successSoft : tokens.accentSoft,
                borderRadius: BorderRadius.circular(AxisRadius.pill),
              ),
              child: Text(
                '$count / $maxPhotos',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: hasPhoto ? tokens.success : tokens.onAccentSoft,
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AxisSpacing.xs),
        Text(
          subtitle,
          style: theme.textTheme.bodySmall?.copyWith(
            color: tokens.textSecondary,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: AxisSpacing.sm),
        // Grille des cases
        Row(
          children: List.generate(maxPhotos, (index) {
            final isFilled = index < count;
            final isAddable = index == count;

            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  right: index < maxPhotos - 1 ? AxisSpacing.xs : 0,
                ),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: isFilled
                      ? _buildFilledSlot(context, photos[index], index)
                      : isAddable
                          ? _buildAddSlot(context)
                          : _buildLockedSlot(context),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildFilledSlot(
    BuildContext context,
    PhotoSlotItem item,
    int index,
  ) {
    final tokens = context.axis;

    return ClipRRect(
      borderRadius: BorderRadius.circular(AxisRadius.sm),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Contenu de la photo ou placeholder colis
          Container(
            color: tokens.accentSoft,
            child: Icon(
              Icons.inventory_2_outlined,
              size: 34,
              color: tokens.onAccentSoft,
            ),
          ),
          // Bouton supprimer (28 × 28)
          Positioned(
            top: 4,
            right: 4,
            child: Semantics(
              label: 'Supprimer la photo ${index + 1}',
              button: true,
              child: Material(
                color: tokens.ink.withValues(alpha: 0.8),
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => onRemove(index),
                  child: const SizedBox(
                    width: 28,
                    height: 28,
                    child: Icon(
                      Icons.close_rounded,
                      size: 16,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddSlot(BuildContext context) {
    final tokens = context.axis;
    final theme = Theme.of(context);

    return Material(
      color: tokens.primarySoft,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AxisRadius.sm),
        side: BorderSide(
          color: theme.colorScheme.primary,
          width: 2,
        ),
      ),
      child: InkWell(
        onTap: onAdd,
        borderRadius: BorderRadius.circular(AxisRadius.sm),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.camera_alt_outlined,
              size: 26,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: AxisSpacing.xxs),
            Text(
              'Photo',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLockedSlot(BuildContext context) {
    final tokens = context.axis;

    return Container(
      decoration: BoxDecoration(
        color: tokens.surfaceSoft,
        borderRadius: BorderRadius.circular(AxisRadius.sm),
        border: Border.all(
          color: tokens.border,
          width: 1.5,
        ),
      ),
      alignment: Alignment.center,
      child: Icon(
        Icons.add_photo_alternate_outlined,
        size: 22,
        color: tokens.iconMuted,
      ),
    );
  }
}

