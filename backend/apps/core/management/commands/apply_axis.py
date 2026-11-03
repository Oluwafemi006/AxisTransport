from django.core.management.base import BaseCommand
from django.db import transaction

from apps.core.axis import AXIS_STOPS, RETIRED_STOPS, axis_routes, set_line_stops, set_route_stops
from apps.core.models import Location


class Command(BaseCommand):
    help = (
        "Passe la base à l'axe Parakou, Savè, Glazoué, Dassa, Bohicon, Cotonou (retour inverse). "
        "Active ces villes, désactive Kétou et Porto-Novo, retire leurs arrêts de parcours. "
        "Ne supprime aucun lieu, tarif, billet, réservation ni colis. Ne touche pas aux tarifs. "
        "Sans effet si l'axe est déjà en place."
    )

    @transaction.atomic
    def handle(self, *args, **options):
        for name in AXIS_STOPS:
            place, created = Location.objects.get_or_create(name=name)
            if not place.active:
                place.active = True
                place.save(update_fields=["active"])
            self.stdout.write(f"Ville {name} : {'créée' if created else 'active'}.")
        for name in RETIRED_STOPS:
            updated = Location.objects.filter(name=name, active=True).update(active=False)
            self.stdout.write(f"Ville {name} : {'désactivée' if updated else 'déjà inactive ou absente'}.")

        moved = set_line_stops(AXIS_STOPS)
        self.stdout.write(f"Ligne : {', '.join(AXIS_STOPS)}. Arrêts hors ligne : {', '.join(moved) or 'aucun'}.")

        forward, backward = axis_routes()
        for route, names in ((forward, AXIS_STOPS), (backward, list(reversed(AXIS_STOPS)))):
            removed = set_route_stops(route, names)
            self.stdout.write(f"Parcours {route} : {' → '.join(names)}. Arrêts retirés : {', '.join(removed) or 'aucun'}.")
        self.stdout.write(self.style.SUCCESS("Axe appliqué. Appliquez ensuite les tarifs : apply_axis_fares."))
