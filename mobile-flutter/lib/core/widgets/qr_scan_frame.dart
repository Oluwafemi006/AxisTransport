import 'package:flutter/material.dart';

import '../theme/axis_spacing.dart';
import '../theme/axis_tokens.dart';

/// Cadre de visée pour le scan de billets QR code.
///
/// Affiche un carré central (230 × 230 px) avec 4 coins ambrés ([AxisTokens.accent]),
/// une ligne de visée centrale et un libellé d'aide sous le viseur.
class QrScanFrame extends StatefulWidget {
  const QrScanFrame({
    super.key,
    this.boxSize = 230.0,
    this.instruction = 'Placez le QR code dans le cadre',
    this.animateLaser = true,
  });

  final double boxSize;
  final String instruction;
  final bool animateLaser;

  @override
  State<QrScanFrame> createState() => _QrScanFrameState();
}

class _QrScanFrameState extends State<QrScanFrame>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    if (widget.animateLaser) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant QrScanFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animateLaser != oldWidget.animateLaser) {
      if (widget.animateLaser) {
        _controller.repeat(reverse: true);
      } else {
        _controller.stop();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.axis;
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: widget.boxSize,
          height: widget.boxSize,
          child: Stack(
            children: [
              // Les 4 coins ambrés
              // Haut-gauche
              Positioned(
                top: 0,
                left: 0,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(color: tokens.accent, width: 4),
                      left: BorderSide(color: tokens.accent, width: 4),
                    ),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(AxisRadius.md),
                    ),
                  ),
                ),
              ),
              // Haut-droite
              Positioned(
                top: 0,
                right: 0,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(color: tokens.accent, width: 4),
                      right: BorderSide(color: tokens.accent, width: 4),
                    ),
                    borderRadius: const BorderRadius.only(
                      topRight: Radius.circular(AxisRadius.md),
                    ),
                  ),
                ),
              ),
              // Bas-gauche
              Positioned(
                bottom: 0,
                left: 0,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: tokens.accent, width: 4),
                      left: BorderSide(color: tokens.accent, width: 4),
                    ),
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(AxisRadius.md),
                    ),
                  ),
                ),
              ),
              // Bas-droite
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: tokens.accent, width: 4),
                      right: BorderSide(color: tokens.accent, width: 4),
                    ),
                    borderRadius: const BorderRadius.only(
                      bottomRight: Radius.circular(AxisRadius.md),
                    ),
                  ),
                ),
              ),
              // Ligne de scan / laser
              AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  final offset = widget.animateLaser
                      ? 16 + _controller.value * (widget.boxSize - 32)
                      : widget.boxSize / 2;
                  return Positioned(
                    top: offset,
                    left: 16,
                    right: 16,
                    child: Container(
                      height: 2,
                      decoration: BoxDecoration(
                        color: tokens.accent,
                        boxShadow: tokens.scanLaserShadow,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: AxisSpacing.md),
        Text(
          widget.instruction,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: tokens.borderStrong,
            fontWeight: FontWeight.w600,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

