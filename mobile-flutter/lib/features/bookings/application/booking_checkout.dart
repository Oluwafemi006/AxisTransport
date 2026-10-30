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
    this.tripQuotes = const [],
    this.reservation,
    this.checkout,
    this.phase = PaymentPhase.idle,
    this.busy = false,
    this.paymentFailed = false,
    this.error,
  });

  final List<PaymentMethod> methods;

  /// Total à payer par moyen de paiement, donné par le serveur AVANT la réservation.
  final List<PaymentQuote> tripQuotes;

  /// La réservation existe mais le paiement n'a pas pu démarrer : on réessaie sur la même réservation.
  final bool paymentFailed;
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
    bool? paymentFailed,
    List<PaymentQuote>? tripQuotes,
    String? error,
  }) {
    return BookingCheckoutState(
      methods: methods,
      tripQuotes: tripQuotes ?? this.tripQuotes,
      paymentFailed: paymentFailed ?? false,
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
PaymentPhase phaseFromRefusal(
  ApiException error, {
  required bool reservationExpired,
}) {
  if (error.refundDue) return PaymentPhase.refundDue;
  final status = error.paymentStatus;
  if (status == 'pending') {
    return reservationExpired ? PaymentPhase.expired : PaymentPhase.awaiting;
  }
  if (status != null) return PaymentPhase.failed;
  return reservationExpired ? PaymentPhase.expired : PaymentPhase.awaiting;
}

/// Au retour de la page de paiement, le prestataire Mobile Money peut valider le paiement une minute plus tard :
/// on relance la vérification (`stillPending`, vrai tant que la réponse est « en attente »)
/// toutes les [delay], au plus [attempts] fois, tant que l'écran est ouvert (`active`).
/// Renvoie vrai si l'attente a pris fin (billet émis, paiement refusé, réservation expirée).
Future<bool> retryWhilePending({
  required Future<bool> Function() stillPending,
  required bool Function() active,
  int attempts = 12,
  Duration delay = const Duration(seconds: 5),
}) async {
  for (var attempt = 0; attempt < attempts; attempt++) {
    if (attempt > 0) await Future<void>.delayed(delay);
    if (!active()) return false;
    if (!await stillPending()) return true;
  }
  return false;
}

class BookingCheckoutNotifier extends AsyncNotifier<BookingCheckoutState> {
  @override
  Future<BookingCheckoutState> build() async {
    final client = ref.watch(apiClientProvider);
    final allMethods = await client.paymentMethods();
    // Seuls les moyens payables en ligne sont proposés dans l'application.
    final methods = allMethods.where((m) => m.active && m.online).toList();
    return BookingCheckoutState(methods: methods);
  }

  // Verrou immédiat contre le double appui : une seule action de paiement à la fois.
  bool _running = false;

  /// Demande au serveur le total à payer pour ce trajet, avant toute réservation.
  Future<void> loadQuotes({
    required int tripId,
    required int passengers,
    int? originId,
    int? destinationId,
  }) async {
    try {
      final quotes = await ref
          .read(apiClientProvider)
          .tripPaymentQuotes(
            tripId: tripId,
            passengers: passengers,
            originId: originId,
            destinationId: destinationId,
          );
      final current = state.value;
      if (current != null) {
        state = AsyncData(
          current.copyWith(
            tripQuotes: quotes,
            busy: current.busy,
            paymentFailed: current.paymentFailed,
            error: current.error,
          ),
        );
      }
    } on ApiException catch (error) {
      // Sans réponse du serveur, aucun total n'est affiché : rien n'est calculé ici.
      final current = state.value;
      if (error.isSegmentFareMissing && current != null) {
        state = AsyncData(current.copyWith(error: error.message));
      }
    } catch (_) {
      // Même cas : aucun total n'est calculé dans l'application.
    }
  }

  /// Action unique : bloque les sièges puis crée le paiement, dans un seul enchaînement.
  /// Si une réservation est déjà en cours (échec précédent, reprise), elle est réutilisée :
  /// jamais de seconde réservation.
  Future<PaymentCheckout?> payNow(
    BookingDraft draft,
    PaymentMethod method,
  ) async {
    if (_running) return null;
    _running = true;
    try {
      final current = state.value;
      if (current == null) return null;
      if (current.reservation == null) {
        if (!draft.hasAllPassengers || draft.trip == null) return null;
        state = AsyncData(current.copyWith(busy: true));
        try {
          final reservation = await _createReservation(draft);
          state = AsyncData(
            BookingCheckoutState(
              methods: current.methods,
              tripQuotes: current.tripQuotes,
              reservation: reservation,
            ),
          );
        } catch (e) {
          state = AsyncData(current.copyWith(error: e.toString()));
          return null;
        }
      }
      return await startPayment(method);
    } finally {
      _running = false;
    }
  }

  /// Annule la réservation non payée en cours ; le serveur libère les sièges.
  Future<bool> cancel() async {
    final current = state.value;
    final reservation = current?.reservation;
    if (current == null || reservation == null || _running) return false;
    _running = true;
    state = AsyncData(current.copyWith(busy: true));
    try {
      await ref
          .read(apiClientProvider)
          .cancelBooking(
            bookingId: reservation.id,
            guestAccessToken: reservation.guestAccessToken,
          );
      state = AsyncData(
        BookingCheckoutState(
          methods: current.methods,
          tripQuotes: current.tripQuotes,
        ),
      );
      return true;
    } catch (e) {
      state = AsyncData(current.copyWith(error: e.toString()));
      return false;
    } finally {
      _running = false;
    }
  }

  Future<BookingReservation> _createReservation(BookingDraft draft) {
    final contactPhone = draft.passengers
        .map((item) => item.phone.trim())
        .firstWhere((phone) => phone.isNotEmpty, orElse: () => '');
    return ref
        .read(apiClientProvider)
        .reserveBooking(
          trip: draft.trip!.id,
          contactPhone: contactPhone,
          buyerIfu: draft.buyerIfu,
          origin: draft.originId != null ? '${draft.originId}' : null,
          destination: draft.destinationId != null ? '${draft.destinationId}' : null,
          boardingPointId: draft.boardingPointId,
          alightingPointId: draft.alightingPointId,
          passengers: draft.passengers.map((passenger) {
            final seat = draft.seatsByPassenger[passenger.id];
            return {
              'full_name': passenger.fullName,
              'phone': passenger.phone,
              'passenger_type': passenger.type.apiValue,
              if (seat != null) 'seat': seat.id,
            };
          }).toList(),
        );
  }

  Future<void> reserve(BookingDraft draft) async {
    if (!draft.hasAllPassengers || draft.trip == null) return;

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
        buyerIfu: draft.buyerIfu,
        origin: draft.originId != null ? '${draft.originId}' : null,
        destination: draft.destinationId != null ? '${draft.destinationId}' : null,
        boardingPointId: draft.boardingPointId,
        alightingPointId: draft.alightingPointId,
        passengers: draft.passengers.map((passenger) {
          final seat = draft.seatsByPassenger[passenger.id];
          return {
            'full_name': passenger.fullName,
            'phone': passenger.phone,
            'passenger_type': passenger.type.apiValue,
            if (seat != null) 'seat': seat.id,
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
      state = AsyncData(
        current.copyWith(phase: PaymentPhase.expired, clearCheckout: true),
      );
      return null;
    }

    state = AsyncData(current.copyWith(busy: true));
    try {
      final checkout = await ref
          .read(apiClientProvider)
          .checkoutBooking(
            bookingId: reservation.id,
            paymentMethod: method.id,
            guestAccessToken: reservation.guestAccessToken,
          );
      state = AsyncData(
        current.copyWith(checkout: checkout, phase: PaymentPhase.awaiting),
      );
      return checkout;
    } on ApiException catch (e) {
      state = AsyncData(
        current.copyWith(
          error: e.toString(),
          paymentFailed: true,
          phase: !e.isNetwork && reservation.isExpired
              ? PaymentPhase.expired
              : current.phase,
        ),
      );
      return null;
    } catch (e) {
      state = AsyncData(
        current.copyWith(error: e.toString(), paymentFailed: true),
      );
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

      final confirmedTickets = paidReservation.tickets
          .where((item) => item.isConfirmed)
          .toList();

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
      final phase = phaseFromRefusal(
        e,
        reservationExpired: reservation.isExpired,
      );
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

  /// Reprend une réservation en attente depuis « Mes réservations ».
  void loadExistingReservation(BookingReservation reservation) {
    final current = state.value;
    final methods = current?.methods ?? const <PaymentMethod>[];
    state = AsyncData(
      BookingCheckoutState(
        methods: methods,
        tripQuotes: reservation.paymentQuotes,
        reservation: reservation,
      ),
    );
  }

  /// Abandonne la réservation en cours (expirée ou à rembourser) pour en démarrer une nouvelle.
  void reset() {
    final methods = state.value?.methods ?? const <PaymentMethod>[];
    state = AsyncData(
      BookingCheckoutState(
        methods: methods,
        tripQuotes: state.value?.tripQuotes ?? const [],
      ),
    );
  }
}

final bookingCheckoutProvider =
    AsyncNotifierProvider<BookingCheckoutNotifier, BookingCheckoutState>(
      BookingCheckoutNotifier.new,
    );
