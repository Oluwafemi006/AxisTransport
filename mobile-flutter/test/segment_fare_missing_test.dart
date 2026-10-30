import 'dart:convert';
import 'dart:typed_data';

import 'package:axis_transport_flutter/core/api_client.dart';
import 'package:axis_transport_flutter/core/models.dart';
import 'package:axis_transport_flutter/core/session.dart';
import 'package:axis_transport_flutter/core/session_store.dart';
import 'package:axis_transport_flutter/core/theme/axis_theme.dart';
import 'package:axis_transport_flutter/features/passengers/presentation/passengers_screen.dart';
import 'package:axis_transport_flutter/features/trips/domain/trip_search.dart';
import 'package:axis_transport_flutter/features/trips/presentation/trip_results_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

ApiException _refused() => ApiException(
  segmentFareMissingMessage,
  statusCode: 400,
  data: const {'code': segmentFareMissingCode, 'detail': 'détail serveur'},
);

class _Store extends SessionStore {
  @override
  Future<void> setActiveClient(int userId) async {}
}

class _Api extends ApiClient {
  _Api() : super(store: _Store());

  @override
  Future<List<Place>> locations() async => const [];

  @override
  Future<({List<Trip> trips, NextAvailable? nextAvailable})> searchTripsDetailed(
    TripSearch search,
  ) async => throw _refused();

  @override
  Future<Trip> trip(int tripId, {int? originId, int? destinationId}) async =>
      throw _refused();
}

/// Faux serveur qui refuse toute demande avec le code du tarif manquant.
class _RefusingAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    jsonEncode({'code': segmentFareMissingCode, 'detail': 'détail serveur'}),
    400,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );

  @override
  void close({bool force = false}) {}
}

Future<void> _open(WidgetTester tester, Widget screen) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [apiClientProvider.overrideWithValue(_Api())],
      child: MaterialApp(theme: AxisTheme.light(), home: screen),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));

  test('un refus 400 du serveur devient le message clair, reconnu par son code', () async {
    final api = ApiClient(
      store: SessionStore(),
      dio: Dio(BaseOptions(baseUrl: 'https://api.test'))
        ..httpClientAdapter = _RefusingAdapter(),
    );

    await expectLater(
      api.tripsForSegment(2, 3),
      throwsA(
        isA<ApiException>()
            .having((e) => e.isSegmentFareMissing, 'code reconnu', isTrue)
            .having((e) => e.message, 'message', segmentFareMissingMessage),
      ),
    );
  });

  testWidgets('recherche : message clair et bouton Réessayer, pas d\'écran cassé', (tester) async {
    await _open(
      tester,
      TripResultsScreen(
        search: TripSearch(originId: 2, destinationId: 3, date: DateTime(2026, 11, 2)),
      ),
    );

    expect(find.text(segmentFareMissingMessage), findsOneWidget);
    expect(find.text('Réessayer'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('passagers : message clair à la place d\'une erreur technique', (tester) async {
    await _open(
      tester,
      const PassengersScreen(tripId: 10, originId: 2, destinationId: 3),
    );

    expect(find.text(segmentFareMissingMessage), findsOneWidget);
    expect(find.textContaining('Connexion nécessaire'), findsNothing);
  });
}
