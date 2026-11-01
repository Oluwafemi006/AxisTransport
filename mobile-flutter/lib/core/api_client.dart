import 'package:flutter/foundation.dart';

import 'dart:async';

import 'package:dio/dio.dart';

import 'config.dart';
import 'models.dart';
import 'session_store.dart';
import '../features/trips/domain/segment_offer.dart';
import '../features/trips/domain/trip_search.dart';

const segmentFareMissingCode = 'segment_fare_missing';
const segmentFareMissingMessage =
    "Tarif non disponible pour ce trajet. Choisissez un autre trajet ou contactez l'agence.";

class ApiException implements Exception {
  ApiException(this.message, {this.statusCode, this.data});
  final String message;
  final int? statusCode;
  final Object? data;

  Object? _field(String key) {
    final payload = data;
    if (payload is! Map) return null;
    final value = payload[key];
    return value is List && value.isNotEmpty ? value.first : value;
  }

  /// Aucune réponse du serveur : réseau coupé, délai dépassé.
  bool get isNetwork => statusCode == null;

  /// Paiement reçu après expiration de la réservation : aucun billet, remboursement à traiter.
  bool get refundDue => statusCode == 409 && _field('refund_due') == true;

  /// Statut renvoyé par le prestataire quand le paiement n'est pas approuvé (pending, declined…).
  String? get paymentStatus => _field('payment_status')?.toString();

  /// Tronçon sans tarif : le serveur refuse, aucun prix de repli.
  bool get isSegmentFareMissing => _field('code') == segmentFareMissingCode;

  @override
  String toString() => message;
}

/// Client HTTP de l'application AXIS (clients et personnel).
///
/// Les clients utilisent /api/v1/client/ ; le personnel (COUNTER, CONTROLLER, ADMIN) /api/v1/staff/.
/// Le serveur décide des droits : un appel du personnel fait par un client est refusé (403).
class ApiClient {
  ApiClient({SessionStore? store, Dio? dio})
    : _store = store ?? SessionStore() {
    _dio =
        dio ??
        Dio(
          BaseOptions(
            baseUrl: AppConfig.apiUrl,
            connectTimeout: const Duration(seconds: 12),
            receiveTimeout: const Duration(seconds: 20),
            headers: {'Content-Type': 'application/json'},
          ),
        );
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          if (options.extra['auth'] == true) {
            final token = await _store.readAccess();
            if (token != null) {
              options.headers['Authorization'] = 'Bearer $token';
            }
          }
          handler.next(options);
        },
        onError: (error, handler) async {
          final request = error.requestOptions;
          final alreadyRetried = request.extra['retried'] == true;
          if (error.response?.statusCode != 401 ||
              request.extra['auth'] != true ||
              alreadyRetried) {
            handler.next(error);
            return;
          }
          final refreshed = await _refreshSession();
          if (!refreshed) {
            handler.next(error);
            return;
          }
          request.extra['retried'] = true;
          final token = await _store.readAccess();
          if (token != null) {
            request.headers['Authorization'] = 'Bearer $token';
          }
          try {
            handler.resolve(await _dio.fetch(request));
          } catch (retryError) {
            handler.next(retryError is DioException ? retryError : error);
          }
        },
      ),
    );
  }

  late final Dio _dio;
  final SessionStore _store;
  Completer<bool>? _refreshLock;

  SessionStore get store => _store;

  // ─── Auth (/api/v1/auth/) ────────────────────────────────────────────────

  Future<void> login(String username, String password) async {
    final payload = await _request<Map<String, dynamic>>(
      '/auth/token/',
      data: {'username': username, 'password': password},
    );
    await _store.clearTokens();
    await _store.saveTokens(
      access: payload['access'] as String,
      refresh: payload['refresh'] as String?,
    );
  }

  Future<void> register({
    required String username,
    required String password,
    required String firstName,
    required String phone,
    String? lastName,
    String? email,
  }) async {
    final payload = <String, dynamic>{
      'username': username,
      'password': password,
      'first_name': firstName,
      'phone': phone,
    };
    if (lastName != null && lastName.isNotEmpty) {
      payload['last_name'] = lastName;
    }
    if (email != null && email.isNotEmpty) {
      payload['email'] = email;
    }
    await _request<dynamic>(
      '/auth/register/',
      data: payload,
    );
    await login(username, password);
  }

  Future<Map<String, dynamic>> checkStaffInvitation(String token) async {
    return _request<Map<String, dynamic>>(
      '/auth/invite/accept/',
      queryParameters: {'token': token},
    );
  }

  Future<Map<String, dynamic>> acceptStaffInvitation({
    required String token,
    required String password,
  }) async {
    return _request<Map<String, dynamic>>(
      '/auth/invite/accept/',
      data: {
        'token': token,
        'password': password,
      },
    );
  }

  Future<void> logout() => _store.clearTokens();

  Future<User> me() async {
    final payload = await _request<Map<String, dynamic>>(
      '/auth/me/',
      auth: true,
    );
    return User.fromJson(payload);
  }

  // ─── Surface Client (/api/v1/client/) ────────────────────────────────────

  Future<List<Trip>> trips() async {
    return _list('/client/trips/', (json) => Trip.fromJson(json));
  }

  Future<TripBanner> tripBanner() async {
    final payload = await _request<Map<String, dynamic>>(
      '/client/trips/banner/',
    );
    return TripBanner.fromJson(payload);
  }

  Future<Trip> trip(
    int tripId, {
    int? originId,
    int? destinationId,
  }) async {
    final query = <String, dynamic>{};
    if (originId != null) query['origin'] = '$originId';
    if (destinationId != null) query['destination'] = '$destinationId';
    final payload = await _request<Map<String, dynamic>>(
      '/client/trips/$tripId/',
      queryParameters: query.isEmpty ? null : query,
    );
    return Trip.fromJson(payload);
  }

  /// Tronçons d'un sens, calculés par le serveur. `missing_fares` ne concerne que l'admin : ignoré ici.
  Future<List<SegmentOffer>> segments(SegmentDirection direction) async {
    final payload = await _request<Map<String, dynamic>>(
      '/client/segments/',
      queryParameters: {'direction': direction.apiValue},
    );
    return (payload['segments'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => SegmentOffer.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  Future<List<Trip>> searchTrips(TripSearch search) => _list(
    '/client/trips/',
    (json) => Trip.fromJson(json),
    queryParameters: search.queryParameters,
  );

  Future<({List<Trip> trips, NextAvailable? nextAvailable})> searchTripsDetailed(
    TripSearch search,
  ) async {
    try {
      final payload = await _request<dynamic>(
        '/client/trips/',
        queryParameters: search.queryParameters,
      );
      if (payload is Map<String, dynamic>) {
        final items = payload['results'];
        final trips = items is List
            ? items
                .whereType<Map>()
                .map((item) => Trip.fromJson(Map<String, dynamic>.from(item)))
                .toList()
            : <Trip>[];
        final nextJson = payload['next_available'] as Map<String, dynamic>?;
        final nextAvailable =
            nextJson != null ? NextAvailable.fromJson(nextJson) : null;
        return (trips: trips, nextAvailable: nextAvailable);
      }
      if (payload is List) {
        final trips = payload
            .whereType<Map>()
            .map((item) => Trip.fromJson(Map<String, dynamic>.from(item)))
            .toList();
        return (trips: trips, nextAvailable: null);
      }
    } catch (_) {
      // Repli sur searchTrips (ex: tests ou mocks personnalisés)
      final fallback = await searchTrips(search);
      return (trips: fallback, nextAvailable: null);
    }
    final fallback = await searchTrips(search);
    return (trips: fallback, nextAvailable: null);
  }

  Future<List<Place>> locations() {
    return _list('/client/locations/', (json) => Place.fromJson(json));
  }

  Future<List<Vehicle>> rentalVehicles() {
    return _list('/client/vehicles/', (json) => Vehicle.fromJson(json));
  }

  Future<List<Seat>> seats(int tripId) {
    return _list('/client/seats/?trip=$tripId', (json) => Seat.fromJson(json));
  }

  /// Coordonnées publiques d'Axis (réglages admin). Chaînes vides si non renseignées.
  Future<Map<String, String>> contact() async {
    final payload = await _request<Map<String, dynamic>>('/client/contact/');
    return {
      'phone': payload['contact_phone'] as String? ?? '',
      'whatsapp': payload['contact_whatsapp'] as String? ?? '',
    };
  }

  Future<List<PaymentMethod>> paymentMethods() {
    return _list(
      '/client/payment-methods/',
      (json) => PaymentMethod.fromJson(json),
    );
  }

  Future<List<Ticket>> tickets() {
    return _list(
      '/client/tickets/',
      (json) => Ticket.fromJson(json),
      auth: true,
    );
  }

  /// « Mes réservations » du client connecté.
  Future<List<BookingReservation>> myBookings() {
    return _list(
      '/client/bookings/mine/',
      (json) => BookingReservation.fromJson(json),
      auth: true,
    );
  }

  Future<List<Parcel>> parcels() {
    return _list(
      '/client/parcels/',
      (json) => Parcel.fromJson(json),
      auth: true,
    );
  }

  /// Suivi d'un colis par son code. Le client ne crée jamais de colis : l'agence l'enregistre.
  Future<ParcelTracking> trackParcel(String code) async {
    final payload = await _request<Map<String, dynamic>>(
      '/client/parcels/track/',
      queryParameters: {'code': code},
    );
    return ParcelTracking.fromJson(payload);
  }

  Future<List<RentalBooking>> rentals() {
    return _list(
      '/client/rentals/',
      (json) => RentalBooking.fromJson(json),
      auth: true,
    );
  }

  Future<RentalBooking> createRental({
    required int vehicle,
    required DateTime startsAt,
    required DateTime endsAt,
    required bool withDriver,
  }) async {
    final payload = await _request<Map<String, dynamic>>(
      '/client/rentals/',
      data: {
        'vehicle': vehicle,
        'starts_at': startsAt.toUtc().toIso8601String(),
        'ends_at': endsAt.toUtc().toIso8601String(),
        'with_driver': withDriver,
      },
      auth: true,
    );
    return RentalBooking.fromJson(payload);
  }

  Future<Ticket> reserve({
    required int trip,
    required int seat,
    required String passengerName,
    required String passengerPhone,
  }) async {
    final payload = await _request<Map<String, dynamic>>(
      '/client/tickets/',
      data: {
        'trip': trip,
        'seat': seat,
        'passenger_name': passengerName,
        'passenger_phone': passengerPhone,
      },
      auth: true,
    );
    return Ticket.fromJson(payload);
  }

  Future<BookingReservation> reserveBooking({
    required int trip,
    required String contactPhone,
    String contactEmail = '',
    String buyerIfu = '',
    String? origin,
    String? destination,
    int? boardingPointId,
    int? alightingPointId,
    required List<Map<String, dynamic>> passengers,
  }) async {
    final payload = await _request<Map<String, dynamic>>(
      '/client/bookings/',
      data: {
        'trip': trip,
        'contact_phone': contactPhone,
        'contact_email': contactEmail,
        'buyer_ifu': buyerIfu.trim(),
        if (origin != null && origin.isNotEmpty) 'origin': origin,
        if (destination != null && destination.isNotEmpty) 'destination': destination,
        // ignore: use_null_aware_elements
        if (boardingPointId != null) 'boarding_point_id': boardingPointId,
        // ignore: use_null_aware_elements
        if (alightingPointId != null) 'alighting_point_id': alightingPointId,
        'passengers': passengers,
      },
      auth: true,
    );
    return BookingReservation.fromJson(payload);
  }

  /// Total à payer AVANT toute réservation, par moyen de paiement en ligne (tarif + frais), calculé par le serveur.
  Future<List<PaymentQuote>> tripPaymentQuotes({
    required int tripId,
    int passengers = 1,
    int? originId,
    int? destinationId,
  }) async {
    final params = {'passengers': '$passengers'};
    if (originId != null) params['origin'] = '$originId';
    if (destinationId != null) params['destination'] = '$destinationId';
    final payload = await _request<List<dynamic>>(
      '/client/trips/$tripId/payment-quotes/',
      queryParameters: params,
    );
    return payload
        .map((item) => PaymentQuote.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  /// Annule une réservation non payée : le serveur libère les sièges tout de suite.
  Future<void> cancelBooking({
    required int bookingId,
    String? guestAccessToken,
  }) async {
    await _request<dynamic>(
      '/client/bookings/$bookingId/cancel/',
      data: const <String, dynamic>{},
      auth: true,
      headers: guestAccessToken == null
          ? null
          : {'X-Booking-Token': guestAccessToken},
    );
  }

  /// « Vérifier mon paiement » : le serveur relit chez le prestataire Mobile Money les transactions en cours de la réservation.
  Future<BookingReservation> refreshBookingPayment({
    required int bookingId,
    String? guestAccessToken,
  }) async {
    final payload = await _request<Map<String, dynamic>>(
      '/client/bookings/$bookingId/refresh-payment/',
      data: const <String, dynamic>{},
      auth: true,
      headers: guestAccessToken == null
          ? null
          : {'X-Booking-Token': guestAccessToken},
    );
    return BookingReservation.fromJson(payload);
  }

  /// Demande au serveur de créer la transaction de paiement (montant fixé côté serveur).
  Future<PaymentCheckout> checkoutBooking({
    required int bookingId,
    required int paymentMethod,
    String? guestAccessToken,
  }) async {
    final payload = await _request<Map<String, dynamic>>(
      '/client/bookings/$bookingId/checkout/',
      data: {'payment_method': paymentMethod},
      auth: true,
      headers: guestAccessToken == null
          ? null
          : {'X-Booking-Token': guestAccessToken},
    );
    return PaymentCheckout.fromJson(payload);
  }

  Future<BookingReservation> payBooking({
    required int bookingId,
    required int paymentMethod,
    String? guestAccessToken,
    String externalReference = '',
  }) async {
    final payload = await _request<Map<String, dynamic>>(
      '/client/bookings/$bookingId/pay/',
      data: {
        'payment_method': paymentMethod,
        'external_reference': externalReference,
      },
      auth: true,
      headers: guestAccessToken == null
          ? null
          : {'X-Booking-Token': guestAccessToken},
    );
    return BookingReservation.fromJson(
      payload['booking'] as Map<String, dynamic>,
    );
  }

  Future<Ticket> pay(
    int ticketId,
    int paymentMethod, {
    String externalReference = '',
  }) async {
    final payload = await _request<Map<String, dynamic>>(
      '/client/tickets/$ticketId/pay/',
      data: {
        'payment_method': paymentMethod,
        'external_reference': externalReference,
      },
      auth: true,
    );
    return Ticket.fromJson(payload['ticket'] as Map<String, dynamic>);
  }

  // ─── Surface du personnel (/api/v1/staff/) ───────────────────────────────
  // Réservée aux rôles COUNTER, CONTROLLER et ADMIN : le serveur refuse tout autre compte (403).

  /// Contrôle d'un billet par son QR code.
  Future<Map<String, dynamic>> validateTicket(
    String qrToken, {
    int? expectedTripId,
  }) {
    return _request<Map<String, dynamic>>(
      '/staff/tickets/validate/',
      data: {
        'qr_token': qrToken,
        // ignore: use_null_aware_elements
        if (expectedTripId != null) 'expected_trip_id': expectedTripId,
      },
      auth: true,
    );
  }

  /// Départs vendables par cet agent, avec places restantes et montants calculés par le serveur.
  Future<Map<String, dynamic>> confirmArrival(int trip, int stop) {
    return _request<Map<String, dynamic>>(
      '/staff/sales/arrival/',
      data: {'trip': trip, 'stop': stop},
      auth: true,
    );
  }

  /// Colis du personnel : le serveur stocke les photos, l'application ne connaît aucune clé.
  Future<Map<String, dynamic>> createParcel(
    Map<String, dynamic> fields,
    List<List<int>> photos,
  ) {
    return _request<Map<String, dynamic>>(
      '/staff/sales/parcel/',
      data: FormData.fromMap({
        ...fields,
        'photos': [
          for (var index = 0; index < photos.length; index++)
            MultipartFile.fromBytes(photos[index], filename: 'colis-$index.jpg'),
        ],
      }),
      auth: true,
    );
  }

  Future<List<dynamic>> myParcels() {
    return _request<List<dynamic>>('/staff/sales/parcels/', auth: true);
  }

  Future<Map<String, dynamic>> saleSummary() {
    return _request<Map<String, dynamic>>('/staff/sales/summary/', auth: true);
  }

  Future<Map<String, dynamic>> saleOptions() {
    return _request<Map<String, dynamic>>('/staff/sales/options/', auth: true);
  }

  /// Vend un billet. La même clé rejouée reprend la vente en cours : jamais de double vente.
  Future<Map<String, dynamic>> sellTicket({
    required String idempotencyKey,
    required int trip,
    required int seat,
    required String passengerName,
    required String passengerPhone,
    required int paymentMethod,
    String? origin,
    String? destination,
    int? boardingPointId,
    int? alightingPointId,
  }) {
    return _request<Map<String, dynamic>>(
      '/staff/sales/sell/',
      data: {
        'idempotency_key': idempotencyKey,
        'trip': trip,
        'seat': seat,
        'passenger_name': passengerName,
        'passenger_phone': passengerPhone,
        'payment_method': paymentMethod,
        if (origin != null && origin.isNotEmpty) 'origin': origin,
        if (destination != null && destination.isNotEmpty) 'destination': destination,
        // ignore: use_null_aware_elements
        if (boardingPointId != null) 'boarding_point_id': boardingPointId,
        // ignore: use_null_aware_elements
        if (alightingPointId != null) 'alighting_point_id': alightingPointId,
      },
      auth: true,
    );
  }

  /// Mobile Money : demande au serveur de vérifier le paiement et d'émettre le billet.
  Future<Map<String, dynamic>> verifySale({
    required int bookingId,
    required int paymentMethod,
    required String externalReference,
  }) {
    return _request<Map<String, dynamic>>(
      '/staff/sales/$bookingId/verify/',
      data: {
        'payment_method': paymentMethod,
        'external_reference': externalReference,
      },
      auth: true,
    );
  }

  /// Annule une vente non payée : le serveur libère la place.
  Future<Map<String, dynamic>> cancelSale(int bookingId) {
    return _request<Map<String, dynamic>>(
      '/staff/sales/$bookingId/cancel/',
      data: const <String, dynamic>{},
      auth: true,
    );
  }

  // ─── Internals ────────────────────────────────────────────────────────────

  Future<bool> _refreshSession() async {
    if (_refreshLock != null) return _refreshLock!.future;
    final lock = Completer<bool>();
    _refreshLock = lock;
    try {
      final refresh = await _store.readRefresh();
      if (refresh == null) {
        await logout();
        lock.complete(false);
        return false;
      }
      final payload = await _request<Map<String, dynamic>>(
        '/auth/token/refresh/',
        data: {'refresh': refresh},
      );
      await _store.saveTokens(
        access: payload['access'] as String,
        refresh: payload['refresh'] as String?,
      );
      lock.complete(true);
      return true;
    } catch (_) {
      await logout();
      lock.complete(false);
      return false;
    } finally {
      _refreshLock = null;
    }
  }

  Future<List<T>> _list<T>(
    String path,
    T Function(Map<String, dynamic>) parse, {
    bool auth = false,
    Map<String, dynamic>? queryParameters,
  }) async {
    final rows = <T>[];
    var query = queryParameters;
    while (true) {
      final payload = await _request<dynamic>(
        path,
        auth: auth,
        queryParameters: query,
      );
      final items = payload is Map<String, dynamic>
          ? payload['results']
          : payload;
      if (items is! List) return rows;
      rows.addAll(
        items.whereType<Map>().map(
          (item) => parse(Map<String, dynamic>.from(item)),
        ),
      );
      // Liste paginée par le serveur : on reprend seulement le numéro de page.
      final next = payload is Map<String, dynamic> ? payload['next'] : null;
      final page = next is String
          ? Uri.tryParse(next)?.queryParameters['page']
          : null;
      if (page == null) return rows;
      query = {...?queryParameters, 'page': page};
    }
  }

  Future<T> _request<T>(
    String path, {
    Object? data,
    bool auth = false,
    Map<String, dynamic>? queryParameters,
    Map<String, String>? headers,
  }) async {
    try {
      final response = await _dio.request<dynamic>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: Options(
          method: data == null ? 'GET' : 'POST',
          extra: {'auth': auth},
          headers: headers,
        ),
      );
      return response.data as T;
    } on DioException catch (error) {
      throw ApiException(
        _messageFrom(error),
        statusCode: error.response?.statusCode,
        data: error.response?.data,
      );
    }
  }

  String _messageFrom(DioException error) {
    final payload = error.response?.data;
    if (payload is Map && payload['code'] == segmentFareMissingCode) {
      return segmentFareMissingMessage;
    }
    final message = _userMessageFrom(error);
    if (!kDebugMode) return message;
    // En debug uniquement : la cause technique, pour diagnostiquer sans deviner.
    final status = error.response?.statusCode;
    return '$message\n[debug] ${error.type.name}'
        '${status == null ? '' : ' · HTTP $status'}'
        ' · ${error.requestOptions.method} ${error.requestOptions.uri}'
        '${error.error == null ? '' : ' · ${error.error}'}';
  }

  String _userMessageFrom(DioException error) {
    final payload = error.response?.data;
    // Une page HTML d'erreur du serveur n'est pas un message pour l'utilisateur.
    if (payload is String &&
        payload.isNotEmpty &&
        !payload.trimLeft().startsWith('<')) {
      return payload;
    }
    if (payload is Map) {
      final detail = payload['detail'];
      if (detail is String) return detail;
      for (final value in payload.values) {
        if (value is String) return value;
        if (value is List && value.isNotEmpty && value.first is String) {
          return value.first as String;
        }
      }
    }
    if (error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout) {
      return "Réseau indisponible. Vérifiez l'API et réessayez.";
    }
    if (error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.sendTimeout) {
      return 'Le serveur met trop de temps à répondre. Réessayez.';
    }
    return 'Une erreur est survenue.';
  }
}
