import 'package:axis_transport_flutter/core/benin_time.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('aujourd’hui au Bénin (UTC+1), pas l’heure du téléphone', () {
    test('minuit au Bénin = 23 h 00 UTC la veille', () {
      expect(
        beninToday(DateTime.utc(2026, 10, 17, 22, 59)),
        DateTime(2026, 10, 17),
      );
      expect(
        beninToday(DateTime.utc(2026, 10, 17, 23, 0)),
        DateTime(2026, 10, 18),
      );
      expect(
        beninToday(DateTime.utc(2026, 12, 31, 23, 30)),
        DateTime(2027, 1, 1),
      );
    });

    test('un instant non UTC est d’abord ramené en UTC', () {
      final parisLike = DateTime.parse(
        '2026-10-18T00:30:00+02:00',
      ); // 22 h 30 UTC le 17
      expect(beninToday(parisLike), DateTime(2026, 10, 17));
    });
  });

  group('date de départ de la recherche', () {
    final now = DateTime.utc(2026, 10, 17, 23, 30); // 00 h 30 le 18 au Bénin
    test('champ vide : message', () {
      expect(tripDateError(null, now: now), 'Choisissez une date de départ.');
    });
    test(
      'date passée au Bénin (même si c’est encore le 17 en UTC) : message',
      () {
        expect(
          tripDateError(DateTime(2026, 10, 17), now: now),
          'Choisissez une date à partir d’aujourd’hui.',
        );
      },
    );
    test('aujourd’hui et après : acceptés', () {
      expect(tripDateError(DateTime(2026, 10, 18), now: now), isNull);
      expect(tripDateError(DateTime(2026, 10, 18, 23, 59), now: now), isNull);
      expect(tripDateError(DateTime(2026, 11, 1), now: now), isNull);
    });
  });

  group('période de location', () {
    final now = DateTime.utc(2026, 10, 18, 9);
    test('champs vides : message', () {
      expect(
        rentalPeriodError(null, null, now: now),
        'Choisissez la date et l’heure de début.',
      );
      expect(
        rentalPeriodError(DateTime.utc(2026, 10, 19), null, now: now),
        'Choisissez la date et l’heure de fin.',
      );
    });
    test('début passé (même aujourd’hui, heure dépassée) : message', () {
      expect(
        rentalPeriodError(
          DateTime.utc(2026, 10, 18, 8, 59),
          DateTime.utc(2026, 10, 20),
          now: now,
        ),
        'Le début de la location doit être dans le futur.',
      );
      expect(
        rentalPeriodError(
          DateTime.utc(2026, 10, 18, 9),
          DateTime.utc(2026, 10, 20),
          now: now,
        ),
        'Le début de la location doit être dans le futur.',
      );
    });
    test('fin avant ou égale au début : message', () {
      final start = DateTime.utc(2026, 10, 19, 8);
      expect(
        rentalPeriodError(start, start, now: now),
        'La fin de la location doit être après le début.',
      );
    });
    test('période valide : aucun message', () {
      expect(
        rentalPeriodError(
          DateTime.utc(2026, 10, 18, 10),
          DateTime.utc(2026, 10, 20),
          now: now,
        ),
        isNull,
      );
    });
  });
}
