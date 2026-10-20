// Heure du Bénin : UTC+1 toute l'année (pas d'heure d'été). Le jour « aujourd'hui » des
// calendriers est celui du Bénin, jamais celui du téléphone (qui peut être réglé ailleurs).

const beninOffset = Duration(hours: 1);

/// Aujourd'hui au Bénin, à minuit (date seule), à partir de l'instant donné (par défaut : maintenant).
DateTime beninToday([DateTime? now]) {
  final benin = (now ?? DateTime.now()).toUtc().add(beninOffset);
  return DateTime(benin.year, benin.month, benin.day);
}

/// Date de départ d'une recherche : obligatoire, pas avant aujourd'hui au Bénin. null = recherche possible.
String? tripDateError(DateTime? date, {DateTime? now}) {
  if (date == null) return 'Choisissez une date de départ.';
  final day = DateTime(date.year, date.month, date.day);
  if (day.isBefore(beninToday(now))) {
    return 'Choisissez une date à partir d’aujourd’hui.';
  }
  return null;
}

/// Période de location : début et fin obligatoires, début dans le futur, fin après le début.
/// Les instants sont comparés en UTC : le résultat ne dépend pas du fuseau du téléphone.
String? rentalPeriodError(
  DateTime? startsAt,
  DateTime? endsAt, {
  DateTime? now,
}) {
  if (startsAt == null) return 'Choisissez la date et l’heure de début.';
  if (endsAt == null) return 'Choisissez la date et l’heure de fin.';
  if (!startsAt.toUtc().isAfter((now ?? DateTime.now()).toUtc())) {
    return 'Le début de la location doit être dans le futur.';
  }
  if (!endsAt.isAfter(startsAt)) {
    return 'La fin de la location doit être après le début.';
  }
  return null;
}
