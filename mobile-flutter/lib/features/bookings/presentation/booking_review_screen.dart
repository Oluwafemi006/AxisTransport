import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/formatters.dart';
import '../../../core/theme.dart';
import '../../../core/models.dart';
import '../../../shared/widgets.dart';
import '../../passengers/domain/passenger.dart';
import '../application/booking_draft.dart';
import '../application/booking_checkout.dart';

class BookingReviewScreen extends ConsumerStatefulWidget {
  const BookingReviewScreen({super.key, required this.tripId});

  final int tripId;

  @override
  ConsumerState<BookingReviewScreen> createState() => _BookingReviewScreenState();
}

class _BookingReviewScreenState extends ConsumerState<BookingReviewScreen>
    with WidgetsBindingObserver {
  PaymentMethod? _selectedMethod;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Au retour de la page de paiement, on demande au serveur de vérifier.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final current = ref.read(bookingCheckoutProvider).value;
    if (current?.checkout != null && !current!.busy) _verifyPayment();
  }

  Future<void> _openPaymentPage(String url) async {
    final opened = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossible d\'ouvrir la page de paiement.')),
      );
    }
  }

  Future<void> _startPayment() async {
    final method = _selectedMethod;
    if (method == null) return;
    final checkout = await ref.read(bookingCheckoutProvider.notifier).startPayment(method);
    if (checkout == null) return;
    if (checkout.paymentUrl == null) {
      await _verifyPayment();
    } else {
      await _openPaymentPage(checkout.paymentUrl!);
    }
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
    final checkoutNotifier = ref.read(bookingCheckoutProvider.notifier);

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
    final errorMessage =
        checkoutState.hasError ? checkoutState.error.toString() : stateData?.error;
    final methods = stateData?.methods ?? [];
    final pending = stateData?.reservation;
    final checkout = stateData?.checkout;

    final successMessage = (pending != null && !checkoutState.hasError) 
        ? 'Sièges réservés temporairement. Finalisez le paiement.'
        : null;

    // Sélectionner la première méthode par défaut si aucune n'est sélectionnée
    if (_selectedMethod == null && methods.isNotEmpty) {
      _selectedMethod = methods.first;
    }

    // Frais et total viennent du serveur (jamais calculés dans l'application).
    final quote = checkout?.quote ??
        (_selectedMethod == null ? null : pending?.quoteFor(_selectedMethod!.id));
    final currency = trip!.currentFare?.currency ?? 'XOF';
    final baseAmount = pending?.amount ?? draft.totalAmount;
    final feePercent = _selectedMethod?.feePercentage ?? 0.0;
    final feeAmount = quote?.feeAmount ?? 0;
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
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                    ),
                  ],
                ),
                if (quote != null && feeAmount > 0) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Frais de paiement (${feePercent.toStringAsFixed(1)}%)',
                          style: const TextStyle(fontSize: 14, color: AxisColors.muted),
                        ),
                      ),
                      Text(
                        '+ ${formatMoney(feeAmount, currency)}',
                        style: const TextStyle(color: AxisColors.navy, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ],
                const Divider(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        quote == null ? 'Total hors frais de paiement' : 'Total à payer',
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                      ),
                    ),
                    Text(
                      formatMoney(totalToPay, currency),
                      style: const TextStyle(
                        color: AxisColors.navyDark,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          if (pending == null)
            FilledButton(
              onPressed: isBusy ? null : () => checkoutNotifier.reserve(draft),
              child: Text(isBusy ? 'Patientez…' : 'Valider et Bloquer les sièges'),
            )
          else ...[
            if (successMessage != null) Notice(successMessage),
            const SizedBox(height: 24),
            const Text(
              'Moyen de paiement',
              style: TextStyle(
                color: AxisColors.navyDark,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 12),
            if (checkoutState.isLoading && methods.isEmpty)
              const Center(child: CircularProgressIndicator())
            else if (methods.isEmpty)
              const Notice('Aucun moyen de paiement actif.', error: true)
            else ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: methods.map((method) {
                  final isSelected = _selectedMethod?.id == method.id;
                  return ChoiceChip(
                    label: Text(
                      method.feePercentage > 0
                          ? '${method.label} (+${method.feePercentage.toStringAsFixed(1)}%)'
                          : method.label,
                    ),
                    selected: isSelected,
                    onSelected: (selected) {
                      if (selected && checkout == null) {
                        setState(() {
                          _selectedMethod = method;
                        });
                      }
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              if (checkout != null) ...[
                const Notice(
                  'Terminez le paiement sur la page FedaPay, puis revenez ici : '
                  'vos billets sont émis dès que le paiement est confirmé.',
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: isBusy ? null : _verifyPayment,
                  child: Text(isBusy ? 'Vérification…' : 'J\'ai payé · Vérifier le paiement'),
                ),
                if (checkout.paymentUrl != null) ...[
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: isBusy ? null : () => _openPaymentPage(checkout.paymentUrl!),
                    child: const Text('Rouvrir la page de paiement'),
                  ),
                ],
              ] else if (_selectedMethod != null)
                FilledButton(
                  onPressed: isBusy ? null : _startPayment,
                  child: Text(
                    isBusy ? 'Traitement...' : 'Payer ${formatMoney(totalToPay, currency)}',
                  ),
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

