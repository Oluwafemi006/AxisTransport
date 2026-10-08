class TripSearch {
  const TripSearch({
    required this.originId,
    required this.destinationId,
    required this.date,
    this.passengers = 1,
  });

  final int originId;
  final int destinationId;
  final DateTime date;
  final int passengers;

  String get dateKey =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  Map<String, String> get queryParameters => {
    'origin': '$originId',
    'destination': '$destinationId',
    'date': dateKey,
  };

  String get resultsLocation => Uri(
    path: '/billets/resultats',
    queryParameters: {...queryParameters, 'passagers': '$passengers'},
  ).toString();

  String get searchLocation => Uri(
    path: '/billets/recherche',
    queryParameters: {...queryParameters, 'passagers': '$passengers'},
  ).toString();

  TripSearch withDate(DateTime value) => TripSearch(
    originId: originId,
    destinationId: destinationId,
    date: value,
    passengers: passengers,
  );

  static TripSearch? fromQueryParameters(Map<String, String> values) {
    final origin = int.tryParse(values['origin'] ?? '');
    final destination = int.tryParse(values['destination'] ?? '');
    final passengers = int.tryParse(values['passagers'] ?? '1');
    final dateText = values['date'];
    final date = dateText == null ? null : DateTime.tryParse(dateText);
    if (origin == null ||
        origin <= 0 ||
        destination == null ||
        destination <= 0 ||
        origin == destination ||
        passengers == null ||
        passengers < 1 ||
        passengers > 8 ||
        date == null ||
        dateText !=
            '${date.year.toString().padLeft(4, '0')}-'
                '${date.month.toString().padLeft(2, '0')}-'
                '${date.day.toString().padLeft(2, '0')}') {
      return null;
    }
    return TripSearch(
      originId: origin,
      destinationId: destination,
      date: date,
      passengers: passengers,
    );
  }
}
