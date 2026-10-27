import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../core/api_client.dart';
import '../../core/models.dart';
import 'sale_models.dart';

/// Logique de la vente par un agent. Elle ne décide de rien : chaque étape est une demande au serveur.
class SaleController extends ChangeNotifier {
  SaleController(this._api);

  final ApiClient _api;

  List<SaleTrip> trips = const [];
  List<Seat> seats = const [];
  SaleTrip? trip;
  Seat? seat;
  SaleQuote? quote;
  int? boardingPointId;
  int? alightingPointId;

  Sale? sale;
  SaleCheckout? checkout;

  bool loading = false;
  bool busy = false;
  String? error;

  /// Le paiement Mobile Money n'a pas pu démarrer ; la place reste tenue et la vente se reprend.
  bool paymentFailed = false;

  /// Paiement arrivé après l'expiration : aucun billet, remboursement à traiter par Axis.
  bool refundDue = false;

  // Verrou immédiat contre le double appui.
  bool _running = false;

  // Clé de la vente en cours. Gardée tant que la vente n'est pas terminée : un nouvel essai
  // après une coupure réseau reprend la même vente côté serveur au lieu d'en créer une autre.
  String? _key;

  @visibleForTesting
  String? get saleKey => _key;

  bool get canSell =>
      !busy &&
      sale == null &&
      trip != null &&
      trip!.hasFare &&
      (trip!.originBoardingPoints.length <= 1 || boardingPointId != null) &&
      (trip!.destinationBoardingPoints.length <= 1 || alightingPointId != null) &&
      seat != null &&
      quote != null;

  static String _newKey() {
    final random = Random.secure();
    return List.generate(
      32,
      (_) => random.nextInt(16).toRadixString(16),
    ).join();
  }

  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final payload = await _api.saleOptions();
      trips = (payload['trips'] as List? ?? const [])
          .map(
            (item) => SaleTrip.fromJson((item as Map).cast<String, dynamic>()),
          )
          .toList();
      if (trip != null) {
        final current = trips.where((item) => item.id == trip!.id);
        trip = current.isEmpty ? null : current.first;
      }
    } on ApiException catch (e) {
      error = e.message;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> selectTrip(SaleTrip? selected) async {
    trip = selected;
    seat = null;
    seats = const [];
    boardingPointId = selected != null && selected.originBoardingPoints.length == 1
        ? selected.originBoardingPoints.first.id
        : null;
    alightingPointId = selected != null && selected.destinationBoardingPoints.length == 1
        ? selected.destinationBoardingPoints.first.id
        : null;
    quote = selected != null && selected.quotes.length == 1
        ? selected.quotes.first
        : null;
    error = null;
    notifyListeners();
    if (selected == null) return;
    try {
      seats = await _api.seats(selected.id);
    } on ApiException catch (e) {
      error = e.message;
    }
    notifyListeners();
  }

  void selectBoardingPoint(int? id) {
    boardingPointId = id;
    notifyListeners();
  }

  void selectAlightingPoint(int? id) {
    alightingPointId = id;
    notifyListeners();
  }

  void selectSeat(Seat selected) {
    seat = selected;
    notifyListeners();
  }

  void selectQuote(SaleQuote selected) {
    quote = selected;
    notifyListeners();
  }

  /// Vend le billet (espèces) ou tient la place et crée le paiement (Mobile Money).
  /// Rappelée après un échec, elle reprend la même vente : jamais de double vente.
  Future<void> sell({
    required String passengerName,
    required String passengerPhone,
  }) async {
    if (_running) return;
    final currentTrip = trip, currentSeat = seat, currentQuote = quote;
    if (currentTrip == null || currentSeat == null || currentQuote == null) {
      return;
    }
    _running = true;
    busy = true;
    error = null;
    notifyListeners();
    _key ??= _newKey();
    try {
      final payload = await _api.sellTicket(
        idempotencyKey: _key!,
        trip: currentTrip.id,
        seat: currentSeat.id,
        passengerName: passengerName.trim(),
        passengerPhone: passengerPhone.trim(),
        paymentMethod: currentQuote.paymentMethod,
        boardingPointId: boardingPointId,
        alightingPointId: alightingPointId,
      );
      _apply(payload);
      final paymentError = payload['payment_error'];
      paymentFailed = paymentError is String && paymentError.isNotEmpty;
      if (paymentFailed) {
        error = 'Le paiement n\'a pas pu démarrer : $paymentError';
      }
    } on ApiException catch (e) {
      // Sans réponse du serveur, on ne sait pas si la vente est passée : la clé est gardée
      // et le prochain essai reprendra la même vente.
      error = e.isNetwork
          ? 'Pas de réponse du serveur. Aucun billet n\'est confirmé. Réessayez : la vente ne sera pas faite deux fois.'
          : e.message;
      // Refus du serveur avant toute réservation : rien n'existe, la prochaine vente repart à neuf.
      if (!e.isNetwork && sale == null) _key = null;
    } finally {
      _running = false;
      busy = false;
      notifyListeners();
    }
  }

  /// Mobile Money : demande au serveur si le paiement est arrivé.
  Future<void> verify() async {
    final current = sale, pending = checkout;
    if (_running || current == null || pending == null) return;
    _running = true;
    busy = true;
    error = null;
    notifyListeners();
    try {
      _apply(
        await _api.verifySale(
          bookingId: current.id,
          paymentMethod: pending.paymentMethod,
          externalReference: pending.transactionId,
        ),
      );
    } on ApiException catch (e) {
      final data = e.data;
      if (data is Map && data['refund_due'] == true) {
        refundDue = true;
        error = e.message;
      } else if (data is Map && '${data['payment_status']}' == 'pending') {
        error = 'Paiement pas encore reçu. Aucun billet n\'est émis tant qu\'il n\'est pas confirmé.';
      } else {
        error = e.isNetwork
            ? 'Pas de réponse du serveur. Réessayez la vérification.'
            : e.message;
      }
    } finally {
      _running = false;
      busy = false;
      notifyListeners();
    }
  }

  /// Annule une vente non payée ; le serveur libère la place.
  Future<void> cancel() async {
    final current = sale;
    if (_running || current == null) return;
    _running = true;
    busy = true;
    error = null;
    notifyListeners();
    try {
      await _api.cancelSale(current.id);
      _clearSale();
      await _reloadSeats();
    } on ApiException catch (e) {
      error = e.isNetwork
          ? 'Pas de réponse du serveur. La vente n\'est pas annulée.'
          : e.message;
    } finally {
      _running = false;
      busy = false;
      notifyListeners();
    }
  }

  /// Repart d'une vente vierge (après un billet émis, une expiration ou un remboursement à traiter).
  Future<void> reset() async {
    _clearSale();
    notifyListeners();
    await load();
    await _reloadSeats();
  }

  /// Relit les places du départ choisi, en gardant le moyen de paiement déjà sélectionné.
  Future<void> _reloadSeats() async {
    final current = trip;
    seat = null;
    if (current == null) return;
    try {
      seats = await _api.seats(current.id);
    } on ApiException catch (e) {
      error = e.message;
    }
    notifyListeners();
  }

  void _apply(Map<String, dynamic> payload) {
    sale = Sale.fromJson((payload['booking'] as Map).cast<String, dynamic>());
    final rawCheckout = payload['checkout'];
    if (rawCheckout is Map) {
      checkout = SaleCheckout.fromJson(rawCheckout.cast<String, dynamic>());
    } else if (!(sale?.isHeld ?? false)) {
      checkout = null;
    }
    if (sale?.isIssued ?? false) {
      checkout = null;
      paymentFailed = false;
    }
  }

  void _clearSale() {
    sale = null;
    checkout = null;
    seat = null;
    error = null;
    paymentFailed = false;
    refundDue = false;
    _key = null;
  }
}
