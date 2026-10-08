import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_client.dart';
import '../../../core/session.dart'; // Pour apiClientProvider
import '../../../core/models.dart';
import '../../passengers/domain/passenger.dart'; // Pour PassengerTypeLabel
import 'booking_draft.dart';

/// Où en est le paiement, tel que le serveur le rapporte.
enum PaymentPhase {
  /// Aucun paiement lancé.
  idle,

  /// Transaction créée, paiement pas encore confirmé par le prestataire.
  awaiting,

  /// Paiement refusé ou annulé : aucun billet, le voyageur peut relancer un paiement.
  failed,

  /// Délai de blocage des sièges dépassé sans paiement confirmé.
  expired,

  /// Paiement reçu après expiration : aucun billet, remboursement à traiter par Axis.
  refundDue,
}

class BookingCheckoutState {
  const BookingCheckoutState({
    required this.methods,
    this.reservation,
    this.checkout,
    this.phase = PaymentPhase.idle,
    this.busy = false,
    this.error,
  });

  final List<PaymentMethod> methods;
  final BookingReservation? reservation;

  /// Transaction de paiement créée par le serveur, en attente de confirmation.
  final PaymentCheckout? checkout;
  final PaymentPhase phase;
  final bool busy;
  final String? error;

  BookingCheckoutState copyWith({
    BookingReservation? reservation,
    PaymentCheckout? checkout,
    bool clearCheckout = false,
    PaymentPhase? phase,
    bool? busy,
    String? error,
  }) {
    return BookingCheckoutState(
      methods: methods,
      reservation: reservation ?? this.reservation,
      checkout: clearCheckout ? null : (checkout ?? this.checkout),
      phase: phase ?? this.phase,
      busy: busy ?? false,
      error: error,
    );
  }
}

/// Traduit le refus du serveur en état de paiement. Aucune règle n'est décidée ici :
/// l'application ne fait que lire ce que le serveur a répondu.
PaymentPhase phaseFromRefusal(ApiException error, {required bool reservationExpired}) {
  if (error.refundDue) return PaymentPhase.refundDue;
  final status = error.paymentStatus;
  if (status == 'pending') {
    return reservationExpired ? PaymentPhase.expired : PaymentPhase.awaiting;
  }
  if (status != null) return PaymentPhase.failed;
  return reservationExpired ? PaymentPhase.expired : PaymentPhase.awaiting;
}

class BookingCheckoutNotifier
    extends AsyncNotifier<BookingCheckoutState> {
  @override
  Future<BookingCheckoutState> build() async {
    final client = ref.watch(apiClientProvider);
    final allMethods = await client.paymentMethods();
    // Seuls les moyens payables en ligne sont proposés dans l'application.
    final methods = allMethods.where((m) => m.active && m.online).toList();
    return BookingCheckoutState(methods: methods);
  }

  Future<void> reserve(BookingDraft draft) async {
    if (!draft.hasAllSeats || draft.trip == null) return;

    final currentState = state;
    state = const AsyncLoading<BookingCheckoutState>();

    try {
      final client = ref.read(apiClientProvider);

      final contactPhone = draft.passengers
          .map((item) => item.phone.trim())
          .firstWhere((phone) => phone.isNotEmpty, orElse: () => '');

      final reservation = await client.reserveBooking(
        trip: draft.trip!.id,
        contactPhone: contactPhone,
        passengers: draft.passengers.map((passenger) {
          final seat = draft.seatsByPassenger[passenger.id]!;
          return {
            'full_name': passenger.fullName,
            'phone': passenger.phone,
            'passenger_type': passenger.type.apiValue,
            'seat': seat.id,
          };
        }).toList(),
      );

      final methods = currentState.value?.methods ?? [];
      state = AsyncData(
        BookingCheckoutState(methods: methods, reservation: reservation),
      );
    } catch (e, st) {
      state = AsyncError<BookingCheckoutState>(e, st);
    }
  }

  /// Crée la transaction chez le prestataire. Le montant vient du serveur.
  Future<PaymentCheckout?> startPayment(PaymentMethod method) async {
    final current = state.value;
    final reservation = current?.reservation;
    if (current == null || reservation == null) return null;
    if (reservation.isExpired) {
      state = AsyncData(current.copyWith(phase: PaymentPhase.expired, clearCheckout: true));
      return null;
    }

    state = AsyncData(current.copyWith(busy: true));
    try {
      final checkout = await ref.read(apiClientProvider).checkoutBooking(
            bookingId: reservation.id,
            paymentMethod: method.id,
            guestAccessToken: reservation.guestAccessToken,
          );
      state = AsyncData(current.copyWith(checkout: checkout, phase: PaymentPhase.awaiting));
      return checkout;
    } on ApiException catch (e) {
      state = AsyncData(
        current.copyWith(
          error: e.toString(),
          phase: !e.isNetwork && reservation.isExpired ? PaymentPhase.expired : current.phase,
        ),
      );
      return null;
    } catch (e) {
      state = AsyncData(current.copyWith(error: e.toString()));
      return null;
    }
  }

  /// Demande au serveur de vérifier le paiement et d'émettre les billets.
  /// Le billet n'existe que si le serveur a confirmé le paiement.
  Future<Ticket?> pay() async {
    final current = state.value;
    final reservation = current?.reservation;
    final checkout = current?.checkout;
    if (current == null || reservation == null || checkout == null) return null;

    state = AsyncData(current.copyWith(busy: true));
    try {
      final client = ref.read(apiClientProvider);
      final paidReservation = await client.payBooking(
        bookingId: reservation.id,
        paymentMethod: checkout.quote.paymentMethod,
        guestAccessToken: reservation.guestAccessToken,
        externalReference: checkout.transactionId,
      );

      final confirmedTickets =
          paidReservation.tickets.where((item) => item.isConfirmed).toList();

      // Copie locale : le billet reste consultable hors connexion, y compris sans compte.
      for (final ticket in confirmedTickets) {
        await client.store.upsertTicket(ticket);
      }

      ref.read(bookingDraftProvider.notifier).clear();
      // Achat terminé : on repart d'un état vierge pour la prochaine réservation.
      state = AsyncData(BookingCheckoutState(methods: current.methods));

      return confirmedTickets.isEmpty ? null : confirmedTickets.first;
    } on ApiException catch (e) {
      if (e.isNetwork) {
        // Pas de réponse du serveur : on ne conclut rien sur le paiement.
        state = AsyncData(current.copyWith(error: e.toString()));
        return null;
      }
      final phase = phaseFromRefusal(e, reservationExpired: reservation.isExpired);
      state = AsyncData(
        current.copyWith(
          phase: phase,
          // Après un échec ou une expiration, la transaction en cours n'est plus utilisable.
          clearCheckout: phase != PaymentPhase.awaiting,
          error: phase == PaymentPhase.awaiting ? null : e.toString(),
        ),
      );
      return null;
    } catch (e) {
      state = AsyncData(current.copyWith(error: e.toString()));
      return null;
    }
  }

  /// Abandonne la réservation en cours (expirée ou à rembourser) pour en démarrer une nouvelle.
  void reset() {
    final methods = state.value?.methods ?? const <PaymentMethod>[];
    state = AsyncData(BookingCheckoutState(methods: methods));
  }
}

final bookingCheckoutProvider = AsyncNotifierProvider<
    BookingCheckoutNotifier, BookingCheckoutState>(
  BookingCheckoutNotifier.new,
);
