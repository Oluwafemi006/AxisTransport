import '../../../core/widgets/system_insets.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/formatters.dart';
import '../../../core/models.dart';
import '../../../core/theme/axis_theme.dart';
import '../../../core/widgets/widgets.dart';
import '../../../shared/payment_link.dart';
import '../../passengers/domain/passenger.dart';
import '../application/booking_checkout.dart';
import '../application/booking_draft.dart';

class BookingReviewScreen extends ConsumerStatefulWidget {
  const BookingReviewScreen({super.key, required this.tripId});

  final int tripId;

  @override
  ConsumerState<BookingReviewScreen> createState() =>
      _BookingReviewScreenState();
}

class _BookingReviewScreenState extends ConsumerState<BookingReviewScreen>
    with WidgetsBindingObserver {
  PaymentMethod? _selectedMethod;

  /// Vérification répétée en cours après le retour de la page de paiement.
  bool _confirming = false;
  int _confirmRun = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Le total à payer est demandé au serveur dès l'ouverture, avant tout appui.
    Future.microtask(() {
      final draft = ref.read(bookingDraftProvider);
      if (draft.trip?.id != widget.tripId || draft.passengers.isEmpty) return;
      ref
          .read(bookingCheckoutProvider.notifier)
          .loadQuotes(
            tripId: widget.tripId,
            passengers: draft.passengers.length,
            originId: draft.originId,
            destinationId: draft.destinationId,
          );
    });
  }

  @override
  void dispose() {
    _confirmRun++; // arrête une vérification répétée en cours
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Au retour de la page de paiement, on demande au serveur de vérifier, avec patience.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final current = ref.read(bookingCheckoutProvider).value;
    if (current?.checkout != null && !current!.busy) _confirmPatiently();
  }

  Future<void> _confirmPatiently() async {
    final run = ++_confirmRun;
    bool active() => mounted && run == _confirmRun;
    setState(() => _confirming = true);
    await retryWhilePending(
      active: active,
      stillPending: () async {
        final current = ref.read(bookingCheckoutProvider).value;
        if (current?.checkout == null) return false; // émis, refusé ou expiré
        if (current!.busy) return true;
        await _verifyPayment();
        if (!active()) return false;
        final after = ref.read(bookingCheckoutProvider).value;
        return after?.checkout != null && after?.phase == PaymentPhase.awaiting;
      },
    );
    if (active()) setState(() => _confirming = false);
  }

  Future<void> _openPaymentPage(String url) async {
    final opened = await openPaymentPage(Uri.parse(url));
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Impossible d\'ouvrir la page de paiement.'),
        ),
      );
    }
  }

  /// Action unique : réserve les sièges (si ce n'est pas déjà fait) puis ouvre le paiement.
  Future<void> _payNow() async {
    final method = _selectedMethod;
    if (method == null) return;
    final checkout = await ref
        .read(bookingCheckoutProvider.notifier)
        .payNow(ref.read(bookingDraftProvider), method);
    if (checkout == null) {
      final err = ref.read(bookingCheckoutProvider).value?.error ?? '';
      if (err.contains("Cette place vient d'être prise") && mounted) {
        context.go('/billets/booking/${widget.tripId}/sieges');
      }
      return;
    }
    if (checkout.paymentUrl == null) {
      await _verifyPayment();
    } else {
      await _openPaymentPage(checkout.paymentUrl!);
    }
  }

  Future<void> _cancelBooking() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Annuler la réservation ?'),
        content: const Text('Les sièges seront libérés.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Non'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Oui, annuler'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final cancelled = await ref.read(bookingCheckoutProvider.notifier).cancel();
    if (cancelled && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Réservation annulée. Les sièges sont libérés.'),
        ),
      );
    }
  }

  void _restart() {
    ref.read(bookingCheckoutProvider.notifier).reset();
    context.go('/billets/booking/${widget.tripId}/sieges');
  }

  Future<void> _verifyPayment() async {
    final ticket = await ref.read(bookingCheckoutProvider.notifier).pay();
    if (ticket != null && mounted) {
      context.go('/billets/ticket/${ticket.id}', extra: ticket);
    }
  }

  String _initials(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return 'P';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return '${parts.first.substring(0, 1)}${parts.last.substring(0, 1)}'
        .toUpperCase();
  }

  (String, String) _resolveEndpoints(BookingDraft draft, Trip trip) {
    final seg = draft.segmentLabel;
    if (seg != null && seg.contains('→')) {
      final parts = seg.split('→').map((s) => s.trim()).toList();
      if (parts.length == 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
        return (parts[0], parts[1]);
      }
    }
    final origin =
        draft.originName ??
        trip.route.origin?.name ??
        (trip.route.label.contains('→')
            ? trip.route.label.split('→').first.trim()
            : trip.route.label);
    final destination =
        draft.destinationName ??
        trip.route.destination?.name ??
        (trip.route.label.contains('→')
            ? trip.route.label.split('→').last.trim()
            : 'À renseigner');
    return (origin, destination);
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(bookingDraftProvider);
    final trip = draft.trip;
    final checkoutState = ref.watch(bookingCheckoutProvider);
    final theme = Theme.of(context);
    final axis = context.axis;

    if (trip?.id != widget.tripId || !draft.hasAllPassengers) {
      return Scaffold(
        body: Column(
          children: [
            AxisHeader(
              title: 'Récapitulatif',
              onBack: () => context.canPop()
                  ? context.pop()
                  : context.go('/billets/booking/${widget.tripId}/passagers'),
            ),
            Expanded(
              child: EmptyState(
                icon: Icons.receipt_long_outlined,
                title: 'La réservation est incomplète.',
                description:
                    'Sélectionnez vos passagers et vos sièges avant de continuer.',
                actionLabel: 'Recommencer',
                onAction: () => context.go(
                  '/billets/booking/${widget.tripId}/passagers',
                ),
              ),
            ),
          ],
        ),
      );
    }

    final stateData = checkoutState.value;
    final isBusy = checkoutState.isLoading || (stateData?.busy ?? false);
    final errorMessage = checkoutState.hasError
        ? checkoutState.error.toString()
        : stateData?.error;
    final methods = stateData?.methods ?? [];
    final pending = stateData?.reservation;
    final checkout = stateData?.checkout;
    final phase = stateData?.phase ?? PaymentPhase.idle;
    final heldUntil = pending?.reservationExpiresAt == null
        ? null
        : DateFormat('HH:mm').format(pending!.reservationExpiresAt!);

    // Sélectionner la première méthode par défaut si aucune n'est sélectionnée
    if (_selectedMethod == null && methods.isNotEmpty) {
      _selectedMethod = methods.first;
    }

    // Montant à payer donné par le serveur (jamais calculé dans l'application) ; sans frais client, égal au prix.
    final tripQuotes = stateData?.tripQuotes ?? const <PaymentQuote>[];
    PaymentQuote? tripQuoteFor(int methodId) {
      for (final item in tripQuotes) {
        if (item.paymentMethod == methodId) return item;
      }
      return null;
    }

    final quote =
        checkout?.quote ??
        (_selectedMethod == null
            ? null
            : pending?.quoteFor(_selectedMethod!.id) ??
                  tripQuoteFor(_selectedMethod!.id));
    final paymentFailed = stateData?.paymentFailed ?? false;
    final validTrip = trip!;
    final currency = quote?.currency ??
        pending?.currency ??
        validTrip.currentFare?.currency ??
        'FCFA';
    final totalToPay = quote?.total ?? pending?.amount ?? draft.totalAmount;

    final (originName, destinationName) = _resolveEndpoints(draft, validTrip);
    final dateFormatted = DateFormat(
      'EEE d MMM',
      'fr_FR',
    ).format(validTrip.departureAt);
    final departureTime = DateFormat.Hm('fr_FR').format(validTrip.departureAt);
    // Heure d'embarquement = champ boardingAt du serveur ou départ − 30 min à l'affichage.
    final boardingAt =
        validTrip.boardingAt ??
        validTrip.departureAt.subtract(const Duration(minutes: 30));
    final boardingTime = DateFormat.Hm('fr_FR').format(boardingAt);
    // Pas d'heure de passage aux arrêts intermédiaires : seule l'heure de départ du bus existe.
    final busOrigin = validTrip.route.origin;
    final boardsAtBusOrigin =
        draft.originId == null || draft.originId == busOrigin?.id;

    return Scaffold(
      body: Column(
        children: [
          // En-tête blanc + barre d'avancement en 4 segments (Recap.html)
          Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border(bottom: BorderSide(color: axis.border)),
            ),
            padding: const EdgeInsets.fromLTRB(
              AxisSpacing.screen,
              AxisSpacing.s12,
              AxisSpacing.screen,
              AxisSpacing.s12,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Tooltip(
                      message: 'Retour',
                      child: Semantics(
                        button: true,
                        label: 'Retour',
                        child: Material(
                          color: axis.inputFill,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              AxisRadius.small,
                            ),
                            side: BorderSide(color: axis.border),
                          ),
                          child: InkWell(
                            onTap: () => context.canPop()
                                ? context.pop()
                                : context.go(
                                    '/billets/booking/${widget.tripId}/sieges',
                                  ),
                            borderRadius: BorderRadius.circular(
                              AxisRadius.small,
                            ),
                            child: SizedBox(
                              width: AxisSizes.minTarget,
                              height: AxisSizes.minTarget,
                              child: Icon(
                                Icons.arrow_back_rounded,
                                color: axis.ink,
                                size: AxisSizes.icon,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: AxisSpacing.s10),
                    Expanded(
                      child: Text(
                        'Récapitulatif',
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: axis.ink,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AxisSpacing.s10),
                Row(
                  children: List.generate(4, (index) {
                    return Expanded(
                      child: Container(
                        height: 4,
                        margin: EdgeInsets.only(
                          right: index == 3 ? 0 : AxisSpacing.s6,
                        ),
                        decoration: BoxDecoration(
                          color: index < 3
                              ? theme.colorScheme.primary
                              : axis.disabled,
                          borderRadius: BorderRadius.circular(AxisRadius.pill),
                        ),
                      ),
                    );
                  }),
                ),
              ],
            ),
          ),

          // Contenu défilable
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                AxisSpacing.screen,
                AxisSpacing.s14,
                AxisSpacing.screen,
                AxisSpacing.s24,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                // Carte trajet bleu marine (Recap.html)
                Container(
                  padding: const EdgeInsets.all(AxisSpacing.s16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    borderRadius: BorderRadius.circular(AxisRadius.card),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'DE',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: axis.borderStrong,
                                    letterSpacing: 0.6,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  originName,
                                  style: theme.textTheme.titleLarge?.copyWith(
                                    color: theme.colorScheme.onPrimary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: axis.accent,
                              shape: BoxShape.circle,
                            ),
                            alignment: Alignment.center,
                            child: Icon(
                              Icons.arrow_forward_rounded,
                              color: theme.colorScheme.primary,
                              size: 18,
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  'À',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: axis.borderStrong,
                                    letterSpacing: 0.6,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  destinationName,
                                  textAlign: TextAlign.end,
                                  style: theme.textTheme.titleLarge?.copyWith(
                                    color: theme.colorScheme.onPrimary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AxisSpacing.s14),
                      Divider(
                        height: 1,
                        color: theme.colorScheme.onPrimary.withValues(
                          alpha: 0.16,
                        ),
                      ),
                      const SizedBox(height: AxisSpacing.s12),
                      Row(
                        children: [
                          Expanded(
                            child: _TripMetaItem(
                              label: 'Date',
                              value: dateFormatted,
                              valueColor: theme.colorScheme.onPrimary,
                            ),
                          ),
                          Expanded(
                            child: _TripMetaItem(
                              label: boardsAtBusOrigin || busOrigin == null
                                  ? 'Départ'
                                  : 'Départ de ${busOrigin.name}',
                              value: departureTime,
                              valueColor: theme.colorScheme.onPrimary,
                            ),
                          ),
                          if (boardsAtBusOrigin)
                            Expanded(
                              child: _TripMetaItem(
                                label: 'Embarquement',
                                value: boardingTime,
                                valueColor: axis.accent,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: AxisSpacing.s14),

                // Section Passagers
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'PASSAGER',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: axis.textMuted,
                        letterSpacing: 0.6,
                      ),
                    ),
                    if (pending == null)
                      TextButton(
                        onPressed: () => context.go(
                          '/billets/booking/${widget.tripId}/passagers',
                        ),
                        child: const Text('Modifier'),
                      ),
                  ],
                ),
                const SizedBox(height: AxisSpacing.s6),
                ...draft.passengers.map((passenger) {
                  final seat = draft.seatsByPassenger[passenger.id];
                  final subtitleText = passenger.phone.trim().isNotEmpty
                      ? passenger.phone.trim()
                      : passenger.type.label;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: AxisSpacing.s10),
                    child: AxisCard(
                      padding: const EdgeInsets.all(AxisSpacing.s14),
                      child: Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: axis.primarySoft,
                              shape: BoxShape.circle,
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              _initials(passenger.fullName),
                              style: theme.textTheme.titleSmall?.copyWith(
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ),
                          const SizedBox(width: AxisSpacing.s12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  passenger.fullName,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    color: axis.ink,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  subtitleText,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: axis.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AxisSpacing.s10,
                              vertical: AxisSpacing.s6,
                            ),
                            decoration: BoxDecoration(
                              color: axis.accentSoft,
                              borderRadius: BorderRadius.circular(
                                AxisRadius.small,
                              ),
                            ),
                            child: Text(
                              seat == null
                                  ? 'Places attribuées après paiement'
                                  : 'Siège ${seat.number}',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: axis.onAccentSoft,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),

                const SizedBox(height: AxisSpacing.s6),

                // Section Moyen de paiement ("Mobile Money" uniquement côté client)
                Text(
                  'MOYEN DE PAIEMENT',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: axis.textMuted,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: AxisSpacing.s8),
                if (methods.isEmpty && checkoutState.isLoading)
                  const SkeletonBox(height: 74, borderRadius: AxisRadius.card)
                else if (methods.isEmpty)
                  const _ReviewNotice(
                    message:
                        'Aucun paiement en ligne n\'est disponible pour le moment.',
                    isError: true,
                  )
                else
                  ...methods.map((method) {
                    final selected = _selectedMethod?.id == method.id;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: AxisSpacing.s8),
                      child: Material(
                        color: theme.colorScheme.surface,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AxisRadius.card),
                          side: BorderSide(
                            color: selected
                                ? theme.colorScheme.primary
                                : axis.border,
                            width: selected ? 2 : 1,
                          ),
                        ),
                        child: InkWell(
                          onTap: checkout == null
                              ? () => setState(() => _selectedMethod = method)
                              : null,
                          borderRadius: BorderRadius.circular(AxisRadius.card),
                          child: Padding(
                            padding: const EdgeInsets.all(AxisSpacing.s14),
                            child: Row(
                              children: [
                                Container(
                                  width: AxisSizes.minTarget,
                                  height: AxisSizes.minTarget,
                                  decoration: BoxDecoration(
                                    color: axis.accentSoft,
                                    borderRadius: BorderRadius.circular(
                                      AxisRadius.small,
                                    ),
                                  ),
                                  alignment: Alignment.center,
                                  child: Icon(
                                    Icons.phone_android_rounded,
                                    color: axis.onAccentSoft,
                                    size: AxisSizes.icon,
                                  ),
                                ),
                                const SizedBox(width: AxisSpacing.s12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Mobile Money',
                                        style: theme.textTheme.titleSmall
                                            ?.copyWith(color: axis.ink),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Validation sur votre téléphone',
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(color: axis.textMuted),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  width: 22,
                                  height: 22,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: selected
                                          ? theme.colorScheme.primary
                                          : axis.borderStrong,
                                      width: 2,
                                    ),
                                  ),
                                  alignment: Alignment.center,
                                  child: selected
                                      ? Container(
                                          width: 10,
                                          height: 10,
                                          decoration: BoxDecoration(
                                            color: theme.colorScheme.primary,
                                            shape: BoxShape.circle,
                                          ),
                                        )
                                      : null,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }),

                // IFU de l'acheteur : facultatif, saisi avant la réservation
                if (pending == null) ...[
                  const SizedBox(height: AxisSpacing.s6),
                  TextFormField(
                    key: const Key('buyer-ifu'),
                    initialValue: draft.buyerIfu,
                    maxLength: 30,
                    decoration: const InputDecoration(
                      labelText: 'IFU de l\'acheteur (facultatif)',
                      helperText: 'Imprimé sur le billet s\'il est rempli.',
                    ),
                    onChanged: ref
                        .read(bookingDraftProvider.notifier)
                        .setBuyerIfu,
                  ),
                ],

                const SizedBox(height: AxisSpacing.s8),

                // Carte du prix : montant net uniquement, aucune mention de taxe.
                AxisCard(
                  padding: const EdgeInsets.all(AxisSpacing.s16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Prix des billets',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: axis.textSecondary,
                            ),
                          ),
                          Text(
                            formatMoney(totalToPay, currency),
                            style: AxisTypography.price.copyWith(
                              color: axis.ink,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AxisSpacing.s10),
                      const Divider(height: 1),
                      const SizedBox(height: AxisSpacing.s10),
                      Text(
                        'Le billet est émis dès la confirmation du paiement.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: axis.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),

                // États de réservation temporaire / attente / erreur
                if (pending != null) ...[
                  const SizedBox(height: AxisSpacing.s12),
                  AxisCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Réservation en cours · ${pending.reference}',
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: axis.ink,
                          ),
                        ),
                        const SizedBox(height: AxisSpacing.s6),
                        if (pending.reservationExpiresAt != null &&
                            phase != PaymentPhase.expired &&
                            phase != PaymentPhase.refundDue)
                          HoldCountdown(
                            expiresAt: pending.reservationExpiresAt!,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AxisSpacing.s10),
                  switch (phase) {
                    PaymentPhase.idle => _ReviewNotice(
                      message: paymentFailed
                          ? 'Le paiement n\'a pas pu démarrer. Vos sièges restent bloqués'
                                '${heldUntil == null ? '.' : ' jusqu\'à $heldUntil.'}'
                          : heldUntil == null
                          ? 'Sièges réservés temporairement. Finalisez le paiement.'
                          : 'Sièges bloqués jusqu\'à $heldUntil. Finalisez le paiement avant cette heure.',
                      isError: paymentFailed,
                    ),
                    PaymentPhase.awaiting => _ReviewNotice(
                      message: _confirming
                          ? 'Paiement en cours de confirmation… Restez sur cet écran : '
                                'vos billets s\'affichent dès que Mobile Money confirme le paiement.'
                          : 'Paiement en attente. Terminez-le sur la page de paiement, puis revenez ici : '
                                'vos billets sont émis dès que le paiement est confirmé. '
                                'Vous pouvez aussi le vérifier plus tard depuis l\'onglet Billets.'
                                '${heldUntil == null ? '' : ' Sièges bloqués jusqu\'à $heldUntil.'}',
                      isError: false,
                    ),
                    PaymentPhase.failed => _ReviewNotice(
                      message:
                          'Paiement refusé ou annulé : aucun billet n\'a été émis. '
                          'Vous pouvez relancer le paiement'
                          '${heldUntil == null ? '.' : ' tant que vos sièges sont bloqués (jusqu\'à $heldUntil).'}',
                      isError: true,
                    ),
                    PaymentPhase.expired => const _ReviewNotice(
                      message:
                          'Le délai de blocage des sièges est dépassé et aucun paiement n\'a été confirmé. '
                          'Aucun billet n\'a été émis.',
                      isError: true,
                    ),
                    PaymentPhase.refundDue => _ReviewNotice(
                      message:
                          'Remboursement à traiter. Votre paiement est arrivé après l\'expiration de la réservation : '
                          'aucun billet n\'a été émis. Référence à communiquer à Axis : ${pending.reference}.',
                      isError: true,
                    ),
                  },
                ],

                if (errorMessage != null) ...[
                  const SizedBox(height: AxisSpacing.s12),
                  _ReviewNotice(message: errorMessage, isError: true),
                ],
                ],
              ),
            ),
          ),

          // Barre inférieure d'action (Recap.html)
          if (methods.isNotEmpty)
            Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                border: Border(top: BorderSide(color: axis.border)),
              ),
              padding: withSystemInsets(
                context,
                const EdgeInsets.fromLTRB(AxisSpacing.screen, AxisSpacing.s12, AxisSpacing.screen, AxisSpacing.s16),
                bottom: true,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (pending == null)
                    AxisButton(
                      onPressed: isBusy || quote == null ? null : _payNow,
                      icon: const Icon(Icons.lock_outline_rounded),
                      label: isBusy
                          ? 'Patientez…'
                          : quote == null
                          ? 'Montant en cours de calcul…'
                          : 'Payer ${formatMoney(totalToPay, currency)}',
                    )
                  else if (phase == PaymentPhase.expired ||
                      phase == PaymentPhase.refundDue)
                    AxisButton(
                      onPressed: _restart,
                      label: 'Recommencer une réservation',
                    )
                  else ...[
                    if (checkout != null) ...[
                      AxisButton(
                        onPressed: isBusy ? null : _verifyPayment,
                        label: isBusy
                            ? 'Vérification…'
                            : 'J\'ai payé · vérifier',
                      ),
                      if (checkout.paymentUrl != null) ...[
                        const SizedBox(height: AxisSpacing.s8),
                        AxisButton(
                          variant: AxisButtonVariant.outline,
                          height: AxisSizes.secondaryButton,
                          onPressed: isBusy
                              ? null
                              : () => _openPaymentPage(checkout.paymentUrl!),
                          label: 'Reprendre le paiement',
                        ),
                      ],
                    ] else
                      AxisButton(
                        onPressed: isBusy || _selectedMethod == null
                            ? null
                            : _payNow,
                        icon: const Icon(Icons.lock_outline_rounded),
                        label: isBusy
                            ? 'Patientez…'
                            : paymentFailed || phase == PaymentPhase.failed
                            ? 'Réessayer le paiement'
                            : 'Payer ${formatMoney(totalToPay, currency)}',
                      ),
                    const SizedBox(height: AxisSpacing.s6),
                    TextButton(
                      onPressed: isBusy ? null : _cancelBooking,
                      child: const Text('Annuler la réservation'),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _TripMetaItem extends StatelessWidget {
  const _TripMetaItem({
    required this.label,
    required this.value,
    required this.valueColor,
  });

  final String label;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final axis = context.axis;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            label.toUpperCase(),
            maxLines: 1,
            style: theme.textTheme.labelSmall?.copyWith(
              color: axis.borderStrong,
              letterSpacing: 0.5,
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: theme.textTheme.titleSmall?.copyWith(color: valueColor),
        ),
      ],
    );
  }
}

class _ReviewNotice extends StatelessWidget {
  const _ReviewNotice({required this.message, required this.isError});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final axis = context.axis;
    final bg = isError ? axis.danger.withValues(alpha: 0.1) : axis.primarySoft;
    final fg = isError ? axis.danger : theme.colorScheme.primary;

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

/// Temps restant avant la libération des sièges, à partir de l'échéance donnée par le serveur.
class HoldCountdown extends StatefulWidget {
  const HoldCountdown({super.key, required this.expiresAt});

  final DateTime expiresAt;

  @override
  State<HoldCountdown> createState() => _HoldCountdownState();
}

class _HoldCountdownState extends State<HoldCountdown> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final axis = context.axis;
    final remaining = widget.expiresAt.difference(DateTime.now());
    final seconds = remaining.isNegative ? 0 : remaining.inSeconds;
    return Text(
      seconds == 0
          ? 'Délai de réservation écoulé.'
          : 'Temps restant : ${seconds ~/ 60} min ${(seconds % 60).toString().padLeft(2, '0')} s',
      style: theme.textTheme.bodySmall?.copyWith(color: axis.textMuted),
    );
  }
}
