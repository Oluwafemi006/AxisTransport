import 'package:flutter/material.dart';

import '../theme/axis_spacing.dart';
import '../theme/axis_tokens.dart';

/// Type de cellule dans le plan du car.
enum SeatCellType {
  /// Un siège réel avec numéro.
  seat,

  /// L'allée centrale / couloir vide.
  aisle,

  /// Emplacement d'une porte.
  door,
}

/// État d'un siège.
enum SeatStatus {
  free,
  taken,
  selected,
}

/// Donnée décrivant une cellule du plan de sièges.
class SeatCellData {
  const SeatCellData.seat({
    required this.number,
    this.status = SeatStatus.free,
  }) : type = SeatCellType.seat;

  const SeatCellData.aisle()
      : type = SeatCellType.aisle,
        number = '',
        status = SeatStatus.free;

  const SeatCellData.door()
      : type = SeatCellType.door,
        number = '',
        status = SeatStatus.free;

  final SeatCellType type;
  final String number;
  final SeatStatus status;
}

/// Ligne de cellules dans le car.
class SeatRowData {
  const SeatRowData(this.cells);
  final List<SeatCellData> cells;
}

/// Plan de sièges configurable et interactif selon le design system AXIS.
class SeatMap extends StatelessWidget {
  const SeatMap({
    super.key,
    required this.rows,
    required this.onSeatSelected,
    this.showDriver = true,
    this.showLegend = true,
  });

  final List<SeatRowData> rows;
  final ValueChanged<String> onSeatSelected;
  final bool showDriver;
  final bool showLegend;

  @override
  Widget build(BuildContext context) {
    final tokens = context.axis;
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (showLegend) ...[
          _buildLegend(context),
          const SizedBox(height: AxisSpacing.md),
        ],
        // Silhouette du car : réduite (jamais agrandie) sur un écran plus étroit qu'elle.
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AxisSpacing.lg,
            vertical: AxisSpacing.md,
          ),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(AxisRadius.busFront),
              topRight: Radius.circular(AxisRadius.busFront),
              bottomLeft: Radius.circular(AxisRadius.xl),
              bottomRight: Radius.circular(AxisRadius.xl),
            ),
            border: Border.all(color: tokens.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showDriver) ...[
                // Zone avant / chauffeur
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'AVANT',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: tokens.textSecondary,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                    ),
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: tokens.iconMuted,
                          width: 2,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.airline_seat_recline_extra_rounded,
                        size: 20,
                        color: tokens.iconMuted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AxisSpacing.xs),
                Divider(color: tokens.borderStrong, thickness: 1),
                const SizedBox(height: AxisSpacing.xs),
              ],
              // Grille des rangées
              Column(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(rows.length, (rowIndex) {
                  final row = rows[rowIndex];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: AxisSpacing.xs),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: List.generate(row.cells.length, (cellIndex) {
                        final cell = row.cells[cellIndex];
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: _buildCell(context, cell),
                        );
                      }),
                    ),
                  );
                }),
              ),
            ],
          ),
        ),
        ),
      ],
    );
  }

  Widget _buildLegend(BuildContext context) {
    final tokens = context.axis;
    final theme = Theme.of(context);

    // Légende : passe à la ligne sur un écran étroit ou avec un texte agrandi.
    return Wrap(
      alignment: WrapAlignment.center,
      runSpacing: AxisSpacing.xs,
      children: [
        _legendItem(
          label: 'Libre',
          box: Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(AxisRadius.legendDot),
              border: Border.all(color: tokens.borderStrong, width: 2),
            ),
          ),
          context: context,
        ),
        const SizedBox(width: AxisSpacing.lg),
        _legendItem(
          label: 'Occupé',
          box: Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: tokens.disabled,
              borderRadius: BorderRadius.circular(AxisRadius.legendDot),
            ),
          ),
          context: context,
        ),
        const SizedBox(width: AxisSpacing.lg),
        _legendItem(
          label: 'Votre siège',
          box: Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: tokens.accent,
              borderRadius: BorderRadius.circular(AxisRadius.legendDot),
            ),
          ),
          context: context,
        ),
      ],
    );
  }

  Widget _legendItem({
    required String label,
    required Widget box,
    required BuildContext context,
  }) {
    final tokens = context.axis;
    final theme = Theme.of(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        box,
        const SizedBox(width: 6),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: tokens.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildCell(BuildContext context, SeatCellData cell) {
    final tokens = context.axis;
    final theme = Theme.of(context);

    switch (cell.type) {
      case SeatCellType.aisle:
        return const SizedBox(width: 24, height: 46);
      case SeatCellType.door:
        return Container(
          width: 96,
          height: 46,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AxisRadius.door),
            border: Border.all(
              color: tokens.iconMuted,
              width: 1.5,
              style: BorderStyle.solid,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            'PORTE',
            style: theme.textTheme.labelSmall?.copyWith(
              color: tokens.textSecondary,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
            ),
          ),
        );
      case SeatCellType.seat:
        final isTaken = cell.status == SeatStatus.taken;
        final isSelected = cell.status == SeatStatus.selected;

        final Color bg;
        final Color fg;
        Border? border;
        List<BoxShadow>? shadows;

        if (isTaken) {
          bg = tokens.disabled;
          fg = tokens.textMuted;
        } else if (isSelected) {
          bg = tokens.accent;
          fg = theme.colorScheme.primary;
          shadows = tokens.seatSelectedShadow;
        } else {
          bg = theme.colorScheme.surface;
          fg = tokens.ink;
          border = Border.all(color: tokens.borderStrong, width: 2);
        }

        const seatRadius = BorderRadius.only(
          topLeft: Radius.circular(AxisRadius.sm),
          topRight: Radius.circular(AxisRadius.sm),
          bottomLeft: Radius.circular(AxisRadius.xs),
          bottomRight: Radius.circular(AxisRadius.xs),
        );

        final label = 'Siège ${cell.number}'
            '${isTaken ? ", occupé" : (isSelected ? ", sélectionné" : ", libre")}';

        return Semantics(
          label: label,
          button: !isTaken,
          selected: isSelected,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: isTaken ? null : () => onSeatSelected(cell.number),
              borderRadius: seatRadius,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: seatRadius,
                  border: border,
                  boxShadow: shadows,
                ),
                alignment: Alignment.center,
                child: Text(
                  cell.number,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: fg,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
        );
    }
  }
}

