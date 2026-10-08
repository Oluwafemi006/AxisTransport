import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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

class _BookingReviewScreenState extends ConsumerState<BookingReviewScreen> {
  PaymentMethod? _selectedMethod;
  final _phoneController = TextEditingController();

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
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

    final isBusy = checkoutState.isLoading;
    final errorMessage = checkoutState.hasError ? checkoutState.error.toString() : null;
    final stateData = checkoutState.value;
    final methods = stateData?.methods ?? [];
    final pending = stateData?.reservation;

    final successMessage = (pending != null && !checkoutState.hasError) 
        ? 'Sièges réservés temporairement. Finalisez le paiement.'
        : null;

    // Sélectionner la première méthode par défaut si aucune n'est sélectionnée
    if (_selectedMethod == null && methods.isNotEmpty) {
      _selectedMethod = methods.first;
    }

    // Pré-remplir le numéro de téléphone avec celui du premier passager adulte si vide
    if (_phoneController.text.isEmpty && draft.passengers.isNotEmpty) {
      final contact = draft.passengers.firstWhere(
        (p) => p.phone.isNotEmpty, 
        orElse: () => draft.passengers.first,
      );
      _phoneController.text = contact.phone;
    }

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
            trip!.route.label,
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
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Total',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                  ),
                ),
                Text(
                  formatMoney(
                    draft.totalAmount,
                    trip.currentFare?.currency ?? 'XOF',
                  ),
                  style: const TextStyle(
                    color: AxisColors.navyDark,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
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
                    label: Text(method.label),
                    selected: isSelected,
                    onSelected: (selected) {
                      if (selected) {
                        setState(() {
                          _selectedMethod = method;
                        });
                      }
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              if (_selectedMethod != null) ...[
                TextField(
                  controller: _phoneController,
                  decoration: const InputDecoration(
                    labelText: 'Numéro de compte (Mobile Money)',
                    hintText: 'Ex: 0102030405',
                    prefixIcon: Icon(Icons.phone_android),
                  ),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: isBusy 
                      ? null 
                      : () async {
                          if (_phoneController.text.trim().isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Veuillez entrer un numéro de paiement')),
                            );
                            return;
                          }
                          final ticket = await checkoutNotifier.pay(_selectedMethod!);
                          if (ticket != null && context.mounted) {
                            context.go('/billets/ticket/${ticket.id}', extra: ticket);
                          } else if (ticket == null && !checkoutState.hasError && context.mounted) {
                            context.go('/billets');
                          }
                        },
                  child: Text(
                    isBusy ? 'Traitement...' : 'Payer ${formatMoney(draft.totalAmount, trip.currentFare?.currency ?? "XOF")}',
                  ),
                ),
              ],
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

