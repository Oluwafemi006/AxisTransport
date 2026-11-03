from django.core.management.base import BaseCommand
from django.db import transaction

from apps.core.axis import AXIS_BOARDING_POINTS
from apps.core.models import BoardingPoint, Location


class Command(BaseCommand):
    help = (
        "Crée les points d'embarquement de l'axe (Parakou : Parc ALBARIKA ; Bohicon : Bohicon ; "
        "Cotonou : Calavi et Agontikon), uniquement pour une ville qui n'a encore AUCUN point (actif ou non). "
        "Une ville modifiée dans l'admin n'est jamais complétée ni recréée. Ne crée aucune ville."
    )

    @transaction.atomic
    def handle(self, *args, **options):
        for city, names in AXIS_BOARDING_POINTS.items():
            place = Location.objects.filter(name=city).first()
            if place is None:
                self.stdout.write(f"{city} : ville absente, aucun point créé.")
                continue
            if BoardingPoint.objects.filter(location=place).exists():
                self.stdout.write(f"{city} : possède déjà au moins un point (inchangé).")
                continue
            for order, name in enumerate(names, start=1):
                BoardingPoint.objects.create(location=place, name=name, active=True, order=order)
            self.stdout.write(f"{city} : {', '.join(names)} (créés).")
