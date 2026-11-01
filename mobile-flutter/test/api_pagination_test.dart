import 'dart:convert';
import 'dart:typed_data';

import 'package:axis_transport_flutter/core/api_client.dart';
import 'package:axis_transport_flutter/core/session_store.dart';
import 'package:axis_transport_flutter/features/trips/domain/trip_search.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _trip(int id) => {
  'id': id,
  'route_detail': {'id': 1, 'label': 'TEST'},
  'departure_at': '2026-11-02T08:00:00+01:00',
  'status': 'SCHEDULED',
  'status_display': 'Programmé',
  'note': '',
  'available_seats': 5,
};

/// Faux serveur : 55 départs par pages de 50.
class _PagedAdapter implements HttpClientAdapter {
  final pages = <String?>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final page = options.queryParameters['page'] as String?;
    pages.add(page);
    final body = page == null
        ? {
            'next': 'https://api.test/api/v1/client/trips/?page=2',
            'results': [for (var id = 1; id <= 50; id++) _trip(id)],
          }
        : {
            'next': null,
            'results': [for (var id = 51; id <= 55; id++) _trip(id)],
          };
    return ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('une recherche de plus de 50 départs lit toutes les pages', () async {
    final adapter = _PagedAdapter();
    final api = ApiClient(
      store: SessionStore(),
      dio: Dio(BaseOptions(baseUrl: 'https://api.test'))
        ..httpClientAdapter = adapter,
    );

    final trips = await api.searchTrips(
      TripSearch(originId: 2, destinationId: 3, date: DateTime(2026, 11, 2)),
    );

    expect(trips.length, 55);
    expect(adapter.pages, [null, '2']);
  });
}
