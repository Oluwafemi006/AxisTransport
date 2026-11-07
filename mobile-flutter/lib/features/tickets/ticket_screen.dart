import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/api_client.dart';
import '../../core/downloads.dart';
import '../../core/formatters.dart';
import '../../core/models.dart';
import '../../core/session.dart';
import '../../core/theme/axis_theme.dart';
import '../../core/widgets/widgets.dart';
import 'ticket_document.dart';

class TicketScreen extends ConsumerStatefulWidget {
  const TicketScreen({super.key, required this.ticketId, this.initialTicket});

  final int ticketId;
  final Ticket? initialTicket;

  @override
  ConsumerState<TicketScreen> createState() => _TicketScreenState();
}

class _TicketScreenState extends ConsumerState<TicketScreen> {
  Ticket? _ticket;
  bool _loading = true;
  bool _downloading = false;
  bool _checkingPayment = false;

  /// « Vérifier mon paiement » : le serveur relit la transaction ; rien n'est décidé ici.
  Future<void> _checkPayment(Ticket ticket) async {
    setState(() => _checkingPayment = true);
    String message;
    try {
      await ref
          .read(apiClientProvider)
          .refreshBookingPayment(bookingId: ticket.bookingId!);
      await _load();
      message = _ticket?.isConfirmed == true
          ? 'Paiement confirmé : votre billet est prêt.'
          : 'Paiement Mobile Money pas encore confirmé. Réessayez dans un instant.';
    } on ApiException catch (error) {
      message = error.isNetwork
          ? 'Serveur injoignable : vérifiez votre connexion et réessayez.'
          : error.message;
    }
    if (!mounted) return;
    setState(() => _checkingPayment = false);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  // Enregistre le billet en PDF dans Téléchargements ; à défaut, propose de l'envoyer par partage.
  Future<void> _downloadTicket(Ticket ticket) async {
    setState(() => _downloading = true);
    String message;
    try {
      final bytes = await buildTicketPdf(ticket);
      try {
        final location = await saveToDownloads(
          name: ticketFileName(ticket),
          bytes: bytes,
        );
        message = 'Billet enregistré : $location';
      } catch (_) {
        await SharePlus.instance.share(
          ShareParams(
            files: [
              XFile.fromData(
                bytes,
                name: ticketFileName(ticket),
                mimeType: 'application/pdf',
              ),
            ],
            subject: 'Billet AXIS Transport ${ticket.reference}',
          ),
        );
        message =
            'Enregistrement direct indisponible sur cet appareil : billet proposé au partage.';
      }
    } catch (error) {
      message = 'Téléchargement impossible : $error';
    }
    if (!mounted) return;
    setState(() => _downloading = false);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void initState() {
    super.initState();
    _ticket = widget.initialTicket;
    _load();
  }

  Future<void> _load() async {
    final api = ref.read(apiClientProvider);
    try {
      final cached = await api.store.findCachedTicket(widget.ticketId);
      if (mounted && cached != null) {
        setState(() {
          _ticket = cached;
          _loading = false;
        });
      } else if (mounted && _ticket != null) {
        setState(() => _loading = false);
      }
    } catch (_) {
      if (mounted && _ticket != null) setState(() => _loading = false);
    }

    try {
      final user = await api.me();
      if (user.isClient) {
        await api.store.setActiveClient(user.id);
        final tickets = await api.tickets();
        await api.store.cacheTickets(tickets);
        final current = tickets
            .where((item) => item.id == widget.ticketId)
            .firstOrNull;
        if (mounted && current != null) setState(() => _ticket = current);
      }
    } catch (_) {
      // Le billet émis localement reste lisible sans connexion réseau.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _shareTicket(Ticket ticket) async {
    final bytes = await buildTicketPdf(ticket);
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(
            bytes,
            name: ticketFileName(ticket),
            mimeType: 'application/pdf',
          ),
        ],
        fileNameOverrides: [ticketFileName(ticket)],
        subject: 'Billet AXIS Transport ${ticket.reference}',
      ),
    );
  }

  (String, String) _resolveCities(Ticket item) {
    final info = item.printInfo;
    final origin = (info != null && info.origin.trim().isNotEmpty)
        ? info.origin.trim()
        : item.originName ??
              item.trip.route.origin?.name ??
              (item.trip.route.label.contains('→')
                  ? item.trip.route.label.split('→').first.trim()
                  : item.trip.route.label);
    final destination = (info != null && info.destination.trim().isNotEmpty)
        ? info.destination.trim()
        : item.destinationName ??
              item.trip.route.destination?.name ??
              (item.trip.route.label.contains('→')
                  ? item.trip.route.label.split('→').last.trim()
                  : missingValue);
    return (origin, destination);
  }

  @override
  Widget build(BuildContext context) {
    final item = _ticket;
    final theme = Theme.of(context);
    final canShowQr = item?.isConfirmed == true && item!.qrToken.isNotEmpty;

    return Scaffold(
      backgroundColor: theme.colorScheme.primary,
      body: SafeArea(
        child: Column(
          children: [
            // Barre supérieure sur fond bleu marine (Billet.html)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AxisSpacing.screen,
                AxisSpacing.s8,
                AxisSpacing.screen,
                AxisSpacing.s10,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Tooltip(
                    message: 'Fermer',
                    child: Semantics(
                      button: true,
                      label: 'Fermer',
                      child: Material(
                        color: theme.colorScheme.onPrimary.withValues(
                          alpha: 0.14,
                        ),
                        borderRadius: BorderRadius.circular(AxisRadius.small),
                        child: InkWell(
                          onTap: () => context.canPop()
                              ? context.pop()
                              : context.go('/billets'),
                          borderRadius: BorderRadius.circular(AxisRadius.small),
                          child: SizedBox(
                            width: AxisSizes.minTarget,
                            height: AxisSizes.minTarget,
                            child: Icon(
                              Icons.close_rounded,
                              color: theme.colorScheme.onPrimary,
                              size: AxisSizes.icon,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Text(
                    'Votre billet',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onPrimary,
                    ),
                  ),
                  const SizedBox(
                    width: AxisSizes.minTarget,
                    height: AxisSizes.minTarget,
                  ),
                ],
              ),
            ),

            // Corps principal
            Expanded(
              child: _loading && item == null
                  ? const Padding(
                      padding: EdgeInsets.all(AxisSpacing.screen),
                      child: SkeletonBox(
                        height: 460,
                        borderRadius: AxisRadius.sheet,
                      ),
                    )
                  : item == null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(AxisSpacing.screen),
                        child: AxisCard(
                          child: EmptyState(
                            icon: Icons.confirmation_number_outlined,
                            title: 'Billet introuvable.',
                            description:
                                'Impossible de charger les informations de ce billet.',
                            actionLabel: 'Réessayer',
                            onAction: _load,
                          ),
                        ),
                      ),
                    )
                  : _buildTicketBody(context, item, canShowQr),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTicketBody(BuildContext context, Ticket item, bool canShowQr) {
    final theme = Theme.of(context);
    final axis = context.axis;
    final info = item.printInfo;
    final (origin, destination) = _resolveCities(item);
    final depTime =
        info?.departureAt ?? item.effectiveDepartureAt ?? item.trip.departureAt;
    // Heure d'embarquement = champ boardingAt du serveur ou départ − 30 min à l'affichage.
    final boardingAt =
        item.trip.boardingAt ?? depTime.subtract(const Duration(minutes: 30));

    final dateText = DateFormat('EEE d MMM', 'fr_FR').format(depTime);
    final depClock = DateFormat.Hm('fr_FR').format(depTime);
    final boardingClock = DateFormat.Hm('fr_FR').format(boardingAt);
    final paid = info?.paid ?? item.isConfirmed;
    final paymentMode = (info != null && info.paymentMode.trim().isNotEmpty)
        ? info.paymentMode.trim()
        : 'Mobile Money';
    final passengerName = item.passengerName.trim().isEmpty
        ? missingValue
        : item.passengerName.trim();
    final seatNumber = item.seat.number.trim().isEmpty
        ? missingValue
        : item.seat.number.trim();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AxisSpacing.screen,
        AxisSpacing.s4,
        AxisSpacing.screen,
        AxisSpacing.s24,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
        // Carte d'embarquement blanche (Billet.html)
        Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(AxisRadius.sheet),
            boxShadow: axis.floatingShadow,
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Partie haute : marque, statut, villes, grille d'horaires et passager
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AxisSpacing.s20,
                  AxisSpacing.s16,
                  AxisSpacing.s20,
                  AxisSpacing.s16,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 26,
                              height: 26,
                              decoration: BoxDecoration(
                                color: axis.accent,
                                borderRadius: BorderRadius.circular(
                                  AxisRadius.chip,
                                ),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                'A',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                            ),
                            const SizedBox(width: AxisSpacing.s8),
                            Text(
                              'AXIS',
                              style: theme.textTheme.titleSmall?.copyWith(
                                color: theme.colorScheme.primary,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ],
                        ),
                        StatusChip(
                          label: paid ? 'Payé · Valide' : item.statusDisplay,
                          variant: paid
                              ? StatusChipVariant.success
                              : StatusChipVariant.warning,
                          icon: paid
                              ? Icons.check_circle_outline_rounded
                              : Icons.schedule_rounded,
                        ),
                      ],
                    ),
                    const SizedBox(height: AxisSpacing.s14),

                    // Villes de départ et d'arrivée
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'DÉPART',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: axis.textMuted,
                                  letterSpacing: 0.6,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                origin.toUpperCase(),
                                style: theme.textTheme.titleLarge?.copyWith(
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: axis.accentSoft,
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: Icon(
                            Icons.arrow_forward_rounded,
                            color: axis.onAccentSoft,
                            size: 16,
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                'ARRIVÉE',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: axis.textMuted,
                                  letterSpacing: 0.6,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                destination.toUpperCase(),
                                textAlign: TextAlign.end,
                                style: theme.textTheme.titleLarge?.copyWith(
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: AxisSpacing.s14),
                    const Divider(height: 1),
                    const SizedBox(height: AxisSpacing.s12),

                    // Ligne 1 de la grille : Date · Départ · Embarquement (mis en évidence)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _TicketCell(label: 'Date', value: dateText),
                        ),
                        const SizedBox(width: AxisSpacing.s8),
                        Expanded(
                          child: _TicketCell(label: 'Départ', value: depClock),
                        ),
                        const SizedBox(width: AxisSpacing.s8),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AxisSpacing.s8,
                              vertical: AxisSpacing.s6,
                            ),
                            decoration: BoxDecoration(
                              color: axis.accentSoft,
                              borderRadius: BorderRadius.circular(
                                AxisRadius.small,
                              ),
                              border: Border.all(color: axis.accent),
                            ),
                            child: _TicketCell(
                              label: 'Embarquement',
                              value: boardingClock,
                              labelColor: axis.onAccentSoft,
                              valueColor: axis.onAccentSoft,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: AxisSpacing.s10),

                    // Ligne 2 de la grille : Siège · Passager
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 1,
                          child: _TicketCell(
                            label: 'Siège',
                            value: 'Siège : $seatNumber',
                          ),
                        ),
                        const SizedBox(width: AxisSpacing.s8),
                        Expanded(
                          flex: 2,
                          child: _TicketCell(
                            label: 'Passager',
                            value: 'Passager : $passengerName',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Ligne de découpe perforée (Billet.html)
              SizedBox(
                height: 24,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AxisSpacing.s20,
                      ),
                      child: CustomPaint(
                        size: const Size(double.infinity, 2),
                        painter: _DashedLinePainter(color: axis.borderStrong),
                      ),
                    ),
                    Positioned(
                      left: -11,
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    Positioned(
                      right: -11,
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Partie basse : QR code, référence et mentions légales (depuis l'API)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AxisSpacing.s20,
                  AxisSpacing.s8,
                  AxisSpacing.s20,
                  AxisSpacing.s16,
                ),
                child: Column(
                  children: [
                    if (canShowQr)
                      Container(
                        width: 190,
                        height: 190,
                        padding: const EdgeInsets.all(AxisSpacing.s14),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface,
                          borderRadius: BorderRadius.circular(AxisRadius.card),
                          border: Border.all(color: axis.border, width: 1.5),
                        ),
                        child: PrettyQrView.data(data: item.qrToken),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.all(AxisSpacing.s16),
                        decoration: BoxDecoration(
                          color: axis.inputFill,
                          borderRadius: BorderRadius.circular(AxisRadius.card),
                          border: Border.all(color: axis.border),
                        ),
                        child: Text(
                          'Le QR sera disponible après confirmation du billet.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: axis.textSecondary,
                          ),
                        ),
                      ),
                    const SizedBox(height: AxisSpacing.s10),
                    Text(
                      'N° ${item.reference}',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: axis.ink,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: AxisSpacing.s4),
                    Text(
                      'Présentez ce code au contrôleur. Valable uniquement pour ce départ — un seul scan autorisé.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: axis.textMuted,
                      ),
                    ),
                    if (canShowQr) ...[
                      const SizedBox(height: AxisSpacing.s4),
                      Text(
                        'Billet enregistré sur ce téléphone et consultable hors connexion.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: axis.textMuted,
                        ),
                      ),
                    ],
                    const SizedBox(height: AxisSpacing.s12),
                    const Divider(height: 1),
                    const SizedBox(height: AxisSpacing.s10),
                    Text(
                      'Payé par $paymentMode · ${formatMoney(item.amount, item.currency)}',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: axis.textSecondary,
                      ),
                    ),
                    const SizedBox(height: AxisSpacing.s6),
                    for (final line in ticketFooter(item))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text(
                          line,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: axis.textMuted,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: AxisSpacing.s14),

        // Bouton de vérification si le billet est en attente de paiement
        if (item.awaitsPayment) ...[
          Text(
            'Vous avez payé ? La confirmation peut prendre une minute.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: axis.borderStrong,
            ),
          ),
          const SizedBox(height: AxisSpacing.s10),
          AxisButton(
            onPressed: _checkingPayment ? null : () => _checkPayment(item),
            icon: const Icon(Icons.refresh_rounded),
            label: _checkingPayment
                ? 'Vérification…'
                : 'Vérifier mon paiement',
          ),
          const SizedBox(height: AxisSpacing.s10),
        ],

        // Barre de 2 boutons : PDF (ambre) + Partager (contour sur bleu marine)
        Row(
          children: [
            Expanded(
              child: AxisButton(
                height: AxisSizes.secondaryButton,
                onPressed: canShowQr && !_downloading
                    ? () => _downloadTicket(item)
                    : null,
                icon: const Icon(Icons.download_rounded),
                label: _downloading ? 'Enregistrement…' : 'PDF',
              ),
            ),
            const SizedBox(width: AxisSpacing.s10),
            Expanded(
              child: Material(
                color: theme.colorScheme.onPrimary.withValues(alpha: 0.14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AxisRadius.button),
                  side: BorderSide(
                    color: theme.colorScheme.onPrimary.withValues(alpha: 0.28),
                  ),
                ),
                child: InkWell(
                  onTap: () => _shareTicket(item),
                  borderRadius: BorderRadius.circular(AxisRadius.button),
                  child: Container(
                    height: AxisSizes.secondaryButton,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AxisSpacing.s16,
                    ),
                    alignment: Alignment.center,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.share_outlined,
                          size: AxisSizes.icon,
                          color: theme.colorScheme.onPrimary,
                        ),
                        const SizedBox(width: AxisSpacing.s8),
                        Flexible(
                          child: Text(
                            'Partager',
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: theme.colorScheme.onPrimary,
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
        ),
      ],
      ),
    );
  }
}

class _TicketCell extends StatelessWidget {
  const _TicketCell({
    required this.label,
    required this.value,
    this.labelColor,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? labelColor;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final axis = context.axis;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: theme.textTheme.labelSmall?.copyWith(
            color: labelColor ?? axis.textMuted,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: theme.textTheme.titleSmall?.copyWith(
            color: valueColor ?? axis.ink,
          ),
        ),
      ],
    );
  }
}

class _DashedLinePainter extends CustomPainter {
  const _DashedLinePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    const dashWidth = 6.0;
    const dashSpace = 6.0;
    var startX = 0.0;
    final y = size.height / 2;

    while (startX < size.width) {
      canvas.drawLine(
        Offset(startX, y),
        Offset((startX + dashWidth).clamp(0.0, size.width), y),
        paint,
      );
      startX += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedLinePainter oldDelegate) =>
      oldDelegate.color != color;
}
