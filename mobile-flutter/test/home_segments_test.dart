import 'dart:convert';
import 'dart:typed_data';

import 'package:axis_transport_flutter/core/api_client.dart';
import 'package:axis_transport_flutter/core/benin_time.dart';
import 'package:axis_transport_flutter/core/models.dart';
import 'package:axis_transport_flutter/core/session.dart';
import 'package:axis_transport_flutter/core/session_store.dart';
import 'package:axis_transport_flutter/core/theme/axis_theme.dart';
import 'package:axis_transport_flutter/features/home/home_screen.dart';
import 'package:axis_transport_flutter/features/trips/domain/segment_offer.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';

const _stops = [(2, 'Parakou'), (3, 'Savè'), (4, 'Kétou'), (5, 'Porto-Novo'), (1, 'Cotonou')];

/// Dix tronçons au prix fictif distinct : la carte ne peut afficher que ce que dit le serveur.
List<SegmentOffer> _ten(List<(int, String)> stops, {DateTime? next}) {
  final rows = <SegmentOffer>[];
  for (var from = 0; from < stops.length; from++) {
    for (var to = from + 1; to < stops.length; to++) {
      rows.add(
        SegmentOffer(
          originId: stops[from].$1,
          origin: stops[from].$2,
          destinationId: stops[to].$1,
          destination: stops[to].$2,
          priceFcfa: 1000 + rows.length,
          lineOrigin: stops.first.$2,
          nextDeparture: next,
        ),
      );
    }
  }
  return rows;
}

class _Store extends SessionStore {
  @override
  Future<void> setActiveClient(int userId) async {}

  @override
  Future<List<Ticket>> readCachedTickets() async => [];

  @override
  Future<void> cacheTickets(List<Ticket> tickets) async {}
}

class _Api extends ApiClient {
  _Api({this.rows, this.failures = 0}) : super(store: _Store());

  final List<SegmentOffer>? rows;
  int failures;
  final asked = <SegmentDirection>[];

  @override
  Future<User> me() async => throw ApiException('Hors connexion');

  @override
  Future<List<Place>> locations() async => const [
    Place(id: 2, name: 'Parakou', address: ''),
    Place(id: 1, name: 'Cotonou', address: ''),
  ];

  @override
  Future<TripBanner> tripBanner() async => throw ApiException('Hors connexion');

  @override
  Future<List<SegmentOffer>> segments(SegmentDirection direction) async {
    asked.add(direction);
    if (failures > 0) {
      failures--;
      throw ApiException('Hors connexion');
    }
    return rows ??
        _ten(direction == SegmentDirection.forward ? _stops : _stops.reversed.toList());
  }
}

Future<Uri?> Function() _pump(WidgetTester tester, _Api api) {
  Uri? opened;
  tester.view.physicalSize = const Size(800, 6000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => const Scaffold(body: HomeScreen())),
      GoRoute(
        path: '/billets/recherche',
        builder: (_, state) {
          opened = state.uri;
          return const Scaffold(body: Text('Recherche'));
        },
      ),
    ],
  );
  return () async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiClientProvider.overrideWithValue(api)],
        child: MaterialApp.router(theme: AxisTheme.light(), routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    return opened;
  };
}

List<String> _cardLabels(WidgetTester tester) => [
  for (final text in tester.widgetList<Text>(find.textContaining(' → ')))
    text.data!,
];

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));

  testWidgets('10 cartes dans l\'ordre, prix du serveur ; changer de sens recharge', (tester) async {
    final api = _Api();
    await _pump(tester, api)();

    expect(api.asked, [SegmentDirection.forward]);
    expect(find.textContaining(RegExp(r'^1\s000\sFCFA$')), findsOneWidget);
    expect(find.textContaining(RegExp(r'^1\s009\sFCFA$')), findsOneWidget);
    final forward = _ten(_stops).map((item) => item.label).toList();
    // Le premier libellé est celui du sélecteur de sens.
    expect(_cardLabels(tester).where(forward.contains).skip(1).toList(), forward);

    await tester.tap(find.text('Cotonou → Parakou'));
    await tester.pumpAndSettle();

    expect(api.asked, [SegmentDirection.forward, SegmentDirection.backward]);
    final backward = _ten(_stops.reversed.toList()).map((item) => item.label).toList();
    expect(_cardLabels(tester).where(backward.contains).skip(1).toList(), backward);
  });

  testWidgets('un tronçon absent de la liste du serveur n\'a aucune carte', (tester) async {
    final rows = _ten(_stops)..removeWhere((item) => item.label == 'Savè → Kétou');
    await _pump(tester, _Api(rows: rows))();

    expect(find.text('Savè → Kétou'), findsNothing);
    expect(find.text('Parakou → Savè'), findsOneWidget);
    expect(find.textContaining('À renseigner'), findsNothing);
  });

  test('missing_fares de la réponse ne produit aucun tronçon', () async {
    final api = ApiClient(
      store: SessionStore(),
      dio: Dio(BaseOptions(baseUrl: 'https://api.test'))
        ..httpClientAdapter = _SegmentsAdapter(),
    );

    final offers = await api.segments(SegmentDirection.forward);

    expect(offers.map((item) => item.label), ['Parakou → Savè']);
    expect(offers.single.priceFcfa, 4500);
    expect(offers.single.nextDeparture, isNull);
  });

  testWidgets('sans prochain départ : mention claire et recherche à la date du jour', (tester) async {
    final api = _Api();
    final open = _pump(tester, api);
    await open();

    expect(find.text('Aucun départ programmé'), findsNWidgets(10));

    await tester.tap(find.text('Parakou → Savè'));
    await tester.pumpAndSettle();

    final uri = (await open())!;
    final today = beninToday();
    expect(uri.queryParameters['origin'], '2');
    expect(uri.queryParameters['destination'], '3');
    expect(
      uri.queryParameters['date'],
      '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}',
    );
  });

  testWidgets('avec prochain départ : mention du bus et date pré-remplie', (tester) async {
    final next = DateTime.parse('2026-11-02T08:00:00+01:00');
    final open = _pump(tester, _Api(rows: _ten(_stops, next: next)));
    await open();

    expect(
      find.text('Prochain départ : lun. 2 nov., départ de Parakou à 08:00'),
      findsNWidgets(10),
    );

    await tester.tap(find.text('Savè → Cotonou'));
    await tester.pumpAndSettle();

    final uri = (await open())!;
    expect(uri.queryParameters['origin'], '3');
    expect(uri.queryParameters['destination'], '1');
    expect(uri.queryParameters['date'], '2026-11-02');
  });

  test('un départ tard le soir garde sa date au Bénin', () {
    const offer = SegmentOffer(
      originId: 2,
      origin: 'Parakou',
      destinationId: 3,
      destination: 'Savè',
      priceFcfa: 4500,
      lineOrigin: 'Parakou',
    );
    final late = SegmentOffer.fromJson({
      'origin_id': offer.originId,
      'origin': offer.origin,
      'destination_id': offer.destinationId,
      'destination': offer.destination,
      'price_fcfa': offer.priceFcfa,
      'line_origin': offer.lineOrigin,
      'next_departure': '2026-11-02T23:30:00+01:00',
    });
    expect(late.searchFrom().dateKey, '2026-11-02');
    expect(late.nextDepartureLabel, endsWith('à 23:30'));
  });

  testWidgets('erreur : message clair et Réessayer recharge la liste', (tester) async {
    final api = _Api(failures: 1);
    await _pump(tester, api)();

    expect(find.text('Connexion indisponible'), findsOneWidget);
    expect(find.text('Réessayer'), findsOneWidget);

    await tester.tap(find.text('Réessayer'));
    await tester.pumpAndSettle();

    expect(find.text('Connexion indisponible'), findsNothing);
    expect(find.text('Parakou → Savè'), findsOneWidget);
  });
}

class _SegmentsAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    jsonEncode({
      'direction': options.queryParameters['direction'],
      'segments': [
        {
          'origin_id': 2,
          'origin': 'Parakou',
          'destination_id': 3,
          'destination': 'Savè',
          'price_fcfa': 4500,
          'next_departure': null,
          'line_origin': 'Parakou',
        },
      ],
      'missing_fares': [
        {'origin_id': 3, 'origin': 'Savè', 'destination_id': 4, 'destination': 'Kétou'},
      ],
    }),
    200,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );

  @override
  void close({bool force = false}) {}
}
