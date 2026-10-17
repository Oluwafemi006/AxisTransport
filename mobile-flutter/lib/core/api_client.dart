import 'package:flutter/foundation.dart';

import 'dart:async';

import 'package:dio/dio.dart';

import 'config.dart';
import 'models.dart';
import 'session_store.dart';
import '../features/trips/domain/trip_search.dart';

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
  }) async {
    await _request<dynamic>(
      '/auth/register/',
      data: {
        'username': username,
        'password': password,
        'first_name': firstName,
        'phone': phone,
      },
    );
    await login(username, password);
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

  Future<Trip> trip(int tripId) async {
    final payload = await _request<Map<String, dynamic>>(
      '/client/trips/$tripId/',
    );
    return Trip.fromJson(payload);
  }

  Future<List<Trip>> searchTrips(TripSearch search) => _list(
    '/client/trips/',
    (json) => Trip.fromJson(json),
    queryParameters: search.queryParameters,
  );

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
    required List<Map<String, dynamic>> passengers,
  }) async {
    final payload = await _request<Map<String, dynamic>>(
      '/client/bookings/',
      data: {
        'trip': trip,
        'contact_phone': contactPhone,
        'contact_email': contactEmail,
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
  }) async {
    final payload = await _request<List<dynamic>>(
      '/client/trips/$tripId/payment-quotes/',
      queryParameters: {'passengers': '$passengers'},
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

  /// « Vérifier mon paiement » : le serveur relit chez FedaPay les transactions en cours de la réservation.
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
        if (expectedTripId != null) 'expected_trip_id': expectedTripId,
      },
      auth: true,
    );
  }

  /// Départs vendables par cet agent, avec places restantes et montants calculés par le serveur.
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
    final payload = await _request<dynamic>(
      path,
      auth: auth,
      queryParameters: queryParameters,
    );
    final items = payload is Map<String, dynamic>
        ? payload['results']
        : payload;
    if (items is! List) return [];
    return items
        .whereType<Map>()
        .map((item) => parse(Map<String, dynamic>.from(item)))
        .toList();
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
