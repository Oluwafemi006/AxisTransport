import 'package:flutter/material.dart';

import '../theme/axis_spacing.dart';
import '../theme/axis_tokens.dart';
import 'axis_button.dart';

/// Type de résultat pour le scan d'un billet.
enum ScanResultType {
  /// Billet valide et payé.
  valid,

  /// Billet déjà scanné auparavant.
  alreadyUsed,

  /// Billet inconnu ou introuvable.
  notFound,
}

/// Données contextuelles pour l'affichage de la feuille de résultat de scan.
class ScanResultData {
  const ScanResultData({
    required this.type,
    this.ticketNumber,
    this.passengerName,
    this.seatNumber,
    this.tripRoute,
    this.usedTimestamp,
    this.scannedBy,
  });

  final ScanResultType type;
  final String? ticketNumber;
  final String? passengerName;
  final String? seatNumber;
  final String? tripRoute;
  final String? usedTimestamp;
  final String? scannedBy;
}

/// Feuille modale (ou panneau inférieur) affichant le verdict d'un scan de billet.
class ScanResultSheet extends StatelessWidget {
  const ScanResultSheet({
    super.key,
    required this.data,
    required this.onPrimaryAction,
    this.onSecondaryAction,
    this.onManualInput,
  });

  final ScanResultData data;
  final VoidCallback onPrimaryAction;
  final VoidCallback? onSecondaryAction;
  final VoidCallback? onManualInput;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(AxisRadius.scanSheet),
          topRight: Radius.circular(AxisRadius.scanSheet),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(
        AxisSpacing.md,
        AxisSpacing.lg,
        AxisSpacing.md,
        AxisSpacing.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          switch (data.type) {
            ScanResultType.valid => _buildValid(context),
            ScanResultType.alreadyUsed => _buildAlreadyUsed(context),
            ScanResultType.notFound => _buildNotFound(context),
          },
          if (onManualInput != null) ...[
            const SizedBox(height: AxisSpacing.xs),
            TextButton(
              onPressed: onManualInput,
              style: TextButton.styleFrom(
                minimumSize: const Size.fromHeight(44),
                foregroundColor: theme.colorScheme.primary,
              ),
              child: const Text('Saisir le code à la main'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildValid(BuildContext context) {
    final tokens = context.axis;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: tokens.success,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.check_rounded,
                size: 28,
                color: tokens.onDark,
              ),
            ),
            const SizedBox(width: AxisSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Billet valide',
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: tokens.success,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    'N° ${data.ticketNumber ?? "AXS-XXXXXX"} · payé',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: tokens.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AxisSpacing.md),
        // Bloc récapitulatif
        Container(
          padding: const EdgeInsets.all(AxisSpacing.sm),
          decoration: BoxDecoration(
            color: tokens.surfaceSoft,
            borderRadius: BorderRadius.circular(AxisRadius.sm),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: _metaField(
                      'Passager',
                      data.passengerName ?? '—',
                      context,
                    ),
                  ),
                  Expanded(
                    flex: 1,
                    child: _metaField(
                      'Siège',
                      data.seatNumber ?? '—',
                      context,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AxisSpacing.xs),
              _metaField(
                'Trajet',
                data.tripRoute ?? '—',
                context,
              ),
            ],
          ),
        ),
        const SizedBox(height: AxisSpacing.md),
        AxisButton(
          label: 'Valider l’embarquement',
          onPressed: onPrimaryAction,
          variant: AxisButtonVariant.secondary,
        ),
      ],
    );
  }

  Widget _buildAlreadyUsed(BuildContext context) {
    final tokens = context.axis;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: tokens.accent,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.priority_high_rounded,
                size: 26,
                color: tokens.onDark,
              ),
            ),
            const SizedBox(width: AxisSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Billet déjà utilisé',
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: tokens.onAccentSoft,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    'Scanné le ${data.usedTimestamp ?? "—"}${data.scannedBy != null ? " par ${data.scannedBy}" : ""}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: tokens.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AxisSpacing.sm),
        Text(
          'Ne pas laisser monter. Vérifiez la pièce d’identité si le passager conteste.',
          style: theme.textTheme.labelMedium?.copyWith(
            color: tokens.textSecondary,
            fontWeight: FontWeight.w600,
            height: 1.4,
          ),
        ),
        const SizedBox(height: AxisSpacing.md),
        AxisButton(
          label: 'Scanner un autre billet',
          onPressed: onPrimaryAction,
          variant: AxisButtonVariant.outline,
        ),
      ],
    );
  }

  Widget _buildNotFound(BuildContext context) {
    final tokens = context.axis;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: tokens.danger,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.close_rounded,
                size: 26,
                color: tokens.onDark,
              ),
            ),
            const SizedBox(width: AxisSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Billet introuvable',
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: tokens.danger,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    'Ce code n’existe pas ou n’est pas payé',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: tokens.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AxisSpacing.md),
        AxisButton(
          label: 'Vendre un billet à ce passager',
          onPressed: onPrimaryAction,
          variant: AxisButtonVariant.primary,
        ),
      ],
    );
  }

  Widget _metaField(String label, String value, BuildContext context) {
    final tokens = context.axis;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: tokens.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w800,
            color: tokens.ink,
          ),
        ),
      ],
    );
  }
}

