import 'dart:async';

import 'package:dio/dio.dart';

import 'config.dart';
import 'models.dart';
import 'session_store.dart';
import '../features/trips/domain/trip_search.dart';

class ApiException implements Exception {
  ApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Client HTTP de l'application cliente AXIS.
///
/// Toutes les routes pointent vers /api/v1/client/ ou /api/v1/auth/.
/// Cette surface est strictement réservée aux clients finaux.
/// Le personnel interne (COUNTER, CONTROLLER, ADMIN) utilisera des surfaces séparées.
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
    final payload = await _request<Map<String, dynamic>>('/client/trips/$tripId/');
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
    return _list('/client/payment-methods/', (json) => PaymentMethod.fromJson(json));
  }

  Future<List<Ticket>> tickets() {
    return _list('/client/tickets/', (json) => Ticket.fromJson(json), auth: true);
  }

  Future<List<Parcel>> parcels() {
    return _list('/client/parcels/', (json) => Parcel.fromJson(json), auth: true);
  }

  Future<Parcel> createParcel({
    required String senderName,
    required String senderPhone,
    required String recipientName,
    required String recipientPhone,
    required int origin,
    required int destination,
    required String description,
    String? weightKg,
  }) async {
    final payload = await _request<Map<String, dynamic>>(
      '/client/parcels/',
      data: {
        'sender_name': senderName,
        'sender_phone': senderPhone,
        'recipient_name': recipientName,
        'recipient_phone': recipientPhone,
        'origin': origin,
        'destination': destination,
        'description': description,
        'weight_kg': weightKg?.isEmpty == true ? null : weightKg,
      },
      auth: true,
    );
    return Parcel.fromJson(payload);
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

  Future<Ticket> pay(int ticketId, int paymentMethod, {String externalReference = ''}) async {
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
      throw ApiException(_messageFrom(error));
    }
  }

  String _messageFrom(DioException error) {
    final payload = error.response?.data;
    if (payload is String && payload.isNotEmpty) return payload;
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
    return 'Une erreur est survenue.';
  }
}
