from django.core.management.base import BaseCommand, CommandError
from django.db import transaction

from apps.core.axis import AXIS_FARES, AXIS_STOPS
from apps.core.models import LineStop, Location, SegmentFare, SegmentFareChange

# Arrêts et tarifs de l'axe : définis dans apps/core/axis.py (une seule source).
STOPS = AXIS_STOPS
FARES = AXIS_FARES


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
                    raise CommandError(
                        f"Le rang {position} est déjà occupé par un autre arrêt : rien n'a été chargé. "
                        "Base sur l'ancien axe : lancez apply_axis puis apply_axis_fares (DEPLOY.md)."
                    )
                stop = LineStop.objects.create(location=location, position=position)
            elif stop.position != position:
                raise CommandError(
                    f"{name} est déjà enregistré au rang {stop.position} (attendu {position}) : rien n'a été chargé. "
                    "Base sur l'ancien axe : lancez apply_axis puis apply_axis_fares (DEPLOY.md)."
                )
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
