import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/formatters.dart';
import '../../../core/theme.dart';
import '../../../core/models.dart';
import '../../../shared/payment_link.dart';
import '../../../shared/widgets.dart';
import '../../passengers/domain/passenger.dart';
import '../application/booking_draft.dart';
import '../application/booking_checkout.dart';

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
    // Le total à payer (tarif + frais) est demandé au serveur dès l'ouverture, avant tout appui.
    Future.microtask(() {
      final draft = ref.read(bookingDraftProvider);
      if (draft.trip?.id != widget.tripId || draft.passengers.isEmpty) return;
      ref
          .read(bookingCheckoutProvider.notifier)
          .loadQuotes(
            tripId: widget.tripId,
            passengers: draft.passengers.length,
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
    if (checkout == null) return;
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

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(bookingDraftProvider);
    final trip = draft.trip;
    final checkoutState = ref.watch(bookingCheckoutProvider);

    if (trip?.id != widget.tripId || !draft.hasAllSeats) {
      return Scaffold(
        appBar: AppBar(title: const Text('Récapitulatif')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: AxisCard(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'La réservation est incomplète.',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 14),
                  FilledButton(
                    onPressed: () => context.go(
                      '/billets/booking/${widget.tripId}/passagers',
                    ),
                    child: const Text('Recommencer'),
                  ),
                ],
              ),
            ),
          ),
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
    final currency = trip!.currentFare?.currency ?? 'XOF';
    final baseAmount = pending?.amount ?? draft.totalAmount;
    final totalToPay = quote?.total ?? baseAmount;

    return Scaffold(
      appBar: AppBar(title: const Text('Récapitulatif')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          Row(
            children: List.generate(3, (index) {
              return Expanded(
                child: Container(
                  height: 4,
                  margin: EdgeInsets.only(right: index == 2 ? 0 : 6),
                  decoration: BoxDecoration(
                    color: AxisColors.navy,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 20),
          Text(
            trip.route.label,
            style: const TextStyle(
              color: AxisColors.navyDark,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            formatFullDateTime(trip.departureAt),
            style: const TextStyle(color: AxisColors.muted),
          ),
          const SizedBox(height: 18),
          ...draft.passengers.map((passenger) {
            final seat = draft.seatsByPassenger[passenger.id]!;
            return AxisCard(
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: AxisColors.surfaceLow,
                    foregroundColor: AxisColors.navy,
                    child: Text('${draft.passengers.indexOf(passenger) + 1}'),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          passenger.fullName,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          passenger.type.label,
                          style: const TextStyle(color: AxisColors.muted),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    'Siège ${seat.number}',
                    style: const TextStyle(
                      color: AxisColors.navy,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            );
          }),
          AxisCard(
            child: Column(
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Prix des billets',
                        style: TextStyle(fontSize: 15, color: AxisColors.muted),
                      ),
                    ),
                    Text(
                      formatMoney(baseAmount, currency),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Choix du moyen de paiement, seulement s'il y en a plusieurs : il précède l'action unique.
          if (methods.length > 1 &&
              checkout == null &&
              phase != PaymentPhase.expired &&
              phase != PaymentPhase.refundDue) ...[
            const SizedBox(height: 8),
            const Text(
              'Moyen de paiement',
              style: TextStyle(
                color: AxisColors.navyDark,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: methods.map((method) {
                return ChoiceChip(
                  label: Text(method.label),
                  selected: _selectedMethod?.id == method.id,
                  onSelected: (selected) {
                    if (selected) setState(() => _selectedMethod = method);
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
          ],

          if (methods.isEmpty)
            const Notice(
              'Aucun paiement en ligne n\'est disponible pour le moment.',
              error: true,
            )
          else if (pending == null)
            // Une seule action : réserver les sièges et payer.
            FilledButton(
              onPressed: isBusy || quote == null ? null : _payNow,
              child: Text(
                isBusy
                    ? 'Patientez…'
                    : quote == null
                    ? 'Montant en cours de calcul…'
                    : 'Payer ${formatMoney(quote.total, quote.currency)}',
              ),
            )
          else ...[
            AxisCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Réservation en cours · ${pending.reference}',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 6),
                  if (pending.reservationExpiresAt != null &&
                      phase != PaymentPhase.expired &&
                      phase != PaymentPhase.refundDue)
                    HoldCountdown(expiresAt: pending.reservationExpiresAt!),
                ],
              ),
            ),
            switch (phase) {
              PaymentPhase.idle => Notice(
                paymentFailed
                    ? 'Le paiement n\'a pas pu démarrer. Vos sièges restent bloqués'
                          '${heldUntil == null ? '.' : ' jusqu\'à $heldUntil.'}'
                    : heldUntil == null
                    ? 'Sièges réservés temporairement. Finalisez le paiement.'
                    : 'Sièges bloqués jusqu\'à $heldUntil. Finalisez le paiement avant cette heure.',
                error: paymentFailed,
              ),
              PaymentPhase.awaiting => Notice(
                _confirming
                    ? 'Paiement en cours de confirmation… Restez sur cet écran : '
                          'vos billets s\'affichent dès que FedaPay confirme le paiement.'
                    : 'Paiement en attente. Terminez-le sur la page de paiement, puis revenez ici : '
                          'vos billets sont émis dès que le paiement est confirmé. '
                          'Vous pouvez aussi le vérifier plus tard depuis l\'onglet Billets.'
                          '${heldUntil == null ? '' : ' Sièges bloqués jusqu\'à $heldUntil.'}',
              ),
              PaymentPhase.failed => Notice(
                'Paiement refusé ou annulé : aucun billet n\'a été émis. '
                'Vous pouvez relancer le paiement'
                '${heldUntil == null ? '.' : ' tant que vos sièges sont bloqués (jusqu\'à $heldUntil).'}',
                error: true,
              ),
              PaymentPhase.expired => const Notice(
                'Le délai de blocage des sièges est dépassé et aucun paiement n\'a été confirmé. '
                'Aucun billet n\'a été émis.',
                error: true,
              ),
              PaymentPhase.refundDue => Notice(
                'Remboursement à traiter. Votre paiement est arrivé après l\'expiration de la réservation : '
                'aucun billet n\'a été émis. Référence à communiquer à Axis : ${pending.reference}.',
                error: true,
              ),
            },
            const SizedBox(height: 16),
            if (phase == PaymentPhase.expired ||
                phase == PaymentPhase.refundDue)
              FilledButton(
                onPressed: _restart,
                child: const Text('Recommencer une réservation'),
              )
            else ...[
              if (checkout != null) ...[
                FilledButton(
                  onPressed: isBusy ? null : _verifyPayment,
                  child: Text(
                    isBusy ? 'Vérification…' : 'J\'ai payé · vérifier',
                  ),
                ),
                if (checkout.paymentUrl != null) ...[
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: isBusy
                        ? null
                        : () => _openPaymentPage(checkout.paymentUrl!),
                    child: const Text('Reprendre le paiement'),
                  ),
                ],
              ] else
                // Même réservation, même siège, même délai : seul le paiement est relancé.
                FilledButton(
                  onPressed: isBusy || _selectedMethod == null ? null : _payNow,
                  child: Text(
                    isBusy
                        ? 'Patientez…'
                        : paymentFailed || phase == PaymentPhase.failed
                        ? 'Réessayer le paiement'
                        : 'Payer ${formatMoney(totalToPay, currency)}',
                  ),
                ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: isBusy ? null : _cancelBooking,
                child: const Text('Annuler la réservation'),
              ),
            ],
          ],
          if (errorMessage != null) ...[
            const SizedBox(height: 14),
            Notice(errorMessage, error: true),
          ],
        ],
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
    final remaining = widget.expiresAt.difference(DateTime.now());
    final seconds = remaining.isNegative ? 0 : remaining.inSeconds;
    return Text(
      seconds == 0
          ? 'Délai de réservation écoulé.'
          : 'Temps restant : ${seconds ~/ 60} min ${(seconds % 60).toString().padLeft(2, '0')} s',
      style: const TextStyle(color: AxisColors.muted),
    );
  }
}
