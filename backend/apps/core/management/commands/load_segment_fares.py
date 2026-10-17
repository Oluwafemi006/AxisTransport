from django.core.management.base import BaseCommand, CommandError
from django.db import transaction

from apps.core.models import LineStop, Location, SegmentFare, SegmentFareChange

# Ligne Parakou ↔ Cotonou, dans l'ordre de parcours du trajet aller.
STOPS = ["Parakou", "Savè", "Kétou", "Porto-Novo", "Cotonou"]

# Prix en francs CFA, identiques dans les deux sens. Grille validée par la direction (transmise par Eddy).
FARES = {
    ("Parakou", "Cotonou"): 7500,
    ("Parakou", "Porto-Novo"): 7500,
    ("Parakou", "Kétou"): 6500,
    ("Parakou", "Savè"): 4500,
    ("Savè", "Cotonou"): 6500,
    ("Savè", "Porto-Novo"): 6500,
    ("Savè", "Kétou"): 2500,
    ("Kétou", "Porto-Novo"): 4000,
    ("Kétou", "Cotonou"): 4000,
    ("Porto-Novo", "Cotonou"): 1500,
}


class Command(BaseCommand):
    help = (
        "Charge les arrêts de la ligne et la grille des prix par tronçon. Sans effet sur ce qui existe déjà : "
        "un lieu, un arrêt ou un prix déjà présent n'est jamais modifié. Ne crée aucun compte."
    )

    @transaction.atomic
    def handle(self, *args, **options):
        stops, created_places = {}, []
        for position, name in enumerate(STOPS, start=1):
            # Un lieu nouveau est créé inactif : il n'apparaît pas dans la recherche des clients
            # tant que la vente par tronçon n'est pas ouverte.
            location, created = Location.objects.get_or_create(name=name, defaults={"active": False})
            if created:
                created_places.append(name)
            stop = LineStop.objects.filter(location=location).first()
            if stop is None:
                if LineStop.objects.filter(position=position).exists():
                    raise CommandError(f"Le rang {position} est déjà occupé par un autre arrêt : rien n'a été chargé.")
                stop = LineStop.objects.create(location=location, position=position)
            elif stop.position != position:
                raise CommandError(f"{name} est déjà enregistré au rang {stop.position} (attendu {position}) : rien n'a été chargé.")
            stops[name] = stop

        created_fares, kept = 0, 0
        for (first, second), amount in FARES.items():
            a, b = sorted((stops[first], stops[second]), key=lambda item: item.position)
            fare, created = SegmentFare.objects.get_or_create(start=a, end=b, defaults={"amount": amount})
            if created:
                SegmentFareChange.objects.create(fare=fare, old_amount=None, new_amount=amount)
                created_fares += 1
            else:
                kept += 1

        self.stdout.write(
            f"Lieux créés (inactifs) : {', '.join(created_places) or 'aucun'}. "
            f"Tarifs créés : {created_fares}. Tarifs déjà présents, laissés tels quels : {kept}."
        )
