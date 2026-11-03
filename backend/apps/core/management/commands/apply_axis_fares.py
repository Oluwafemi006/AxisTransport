from django.core.management.base import BaseCommand, CommandError
from django.db import transaction

from apps.core.axis import AXIS_FARES
from apps.core.models import LineStop, SegmentFare, SegmentFareChange


class Command(BaseCommand):
    help = (
        "Applique les 8 tarifs de l'axe (validés par le boss, transmis par Eddy) : met à jour ceux qui existent, "
        "crée ceux qui manquent, affiche ancien et nouveau prix. Ne touche à aucun autre tarif. "
        "Chaque changement est inscrit au journal des tarifs. À lancer après apply_axis."
    )

    @transaction.atomic
    def handle(self, *args, **options):
        stops = {stop.location.name: stop for stop in LineStop.objects.select_related("location")}
        missing = sorted({name for pair in AXIS_FARES for name in pair} - set(stops))
        if missing:
            raise CommandError(f"Arrêts absents de la ligne : {', '.join(missing)}. Lancez d'abord apply_axis.")
        for (first, second), amount in AXIS_FARES.items():
            a, b = sorted((stops[first], stops[second]), key=lambda stop: stop.position)
            fare = SegmentFare.objects.filter(start=a, end=b).first() or SegmentFare.objects.filter(start=b, end=a).first()
            if fare is None:
                fare = SegmentFare.objects.create(start=a, end=b, amount=amount)
                SegmentFareChange.objects.create(fare=fare, old_amount=None, new_amount=amount)
                self.stdout.write(f"{first} ↔ {second} : aucun → {amount} FCFA (créé).")
            elif fare.amount != amount:
                old = fare.amount
                fare.amount = amount
                fare.save(update_fields=["amount", "updated_at"])
                SegmentFareChange.objects.create(fare=fare, old_amount=old, new_amount=amount)
                self.stdout.write(f"{first} ↔ {second} : {old} → {amount} FCFA (modifié).")
            else:
                self.stdout.write(f"{first} ↔ {second} : {amount} FCFA (inchangé).")
        self.stdout.write(self.style.SUCCESS("Tarifs de l'axe appliqués."))
