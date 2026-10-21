from datetime import time
from django.core.management.base import BaseCommand
from apps.core.models import Location, Route, Vehicle, WeeklySchedule
from apps.core.services import generate_trips_from_schedule


class Command(BaseCommand):
    help = "Initialise le planning hebdomadaire par défaut d'Axis Transport et génère les trajets réels."

    def add_arguments(self, parser):
        parser.add_argument(
            "--weeks",
            type=int,
            default=4,
            help="Nombre de semaines de trajets à générer (défaut : 4)",
        )

    def handle(self, *args, **options):
        cotonou, _ = Location.objects.get_or_create(name="Cotonou")
        parakou, _ = Location.objects.get_or_create(name="Parakou", defaults={"address": "Okédama"})

        route_cotonou_parakou, _ = Route.objects.get_or_create(origin=cotonou, destination=parakou)
        route_parakou_cotonou, _ = Route.objects.get_or_create(origin=parakou, destination=cotonou)

        # Bus Yutong par défaut
        yutong, _ = Vehicle.objects.get_or_create(
            category=Vehicle.Category.BUS,
            name="Yutong",
            defaults={"state": Vehicle.State.ACTIVE},
        )

        # Spécification exacte du planning hebdomadaire :
        # Dimanche : 13h00 (Cotonou → Parakou)
        # Lundi : 13h00 (Parakou → Cotonou)
        # Mardi : 08h00 (Cotonou → Parakou)
        # Mercredi : Aucun trajet (Repos/Visite technique)
        # Jeudi : 08h00 (Parakou → Cotonou)
        # Vendredi : 08h00 (Cotonou → Parakou)
        # Samedi : 08h00 (Parakou → Cotonou)
        specs = [
            (WeeklySchedule.DayOfWeek.MONDAY, time(13, 0), route_parakou_cotonou, True, ""),
            (WeeklySchedule.DayOfWeek.TUESDAY, time(8, 0), route_cotonou_parakou, True, ""),
            (WeeklySchedule.DayOfWeek.WEDNESDAY, None, None, False, "Repos/Visite technique"),
            (WeeklySchedule.DayOfWeek.THURSDAY, time(8, 0), route_parakou_cotonou, True, ""),
            (WeeklySchedule.DayOfWeek.FRIDAY, time(8, 0), route_cotonou_parakou, True, ""),
            (WeeklySchedule.DayOfWeek.SATURDAY, time(8, 0), route_parakou_cotonou, True, ""),
            (WeeklySchedule.DayOfWeek.SUNDAY, time(13, 0), route_cotonou_parakou, True, ""),
        ]

        for day_of_week, dep_time, route, is_active, notes in specs:
            WeeklySchedule.objects.update_or_create(
                day_of_week=day_of_week,
                defaults={
                    "departure_time": dep_time,
                    "route": route,
                    "vehicle": yutong if is_active else None,
                    "is_active": is_active,
                    "notes": notes,
                },
            )

        self.stdout.write(self.style.SUCCESS("Planning hebdomadaire par défaut initialisé (7 jours configurés)."))

        weeks = options["weeks"]
        created = generate_trips_from_schedule(weeks=weeks)
        self.stdout.write(
            self.style.SUCCESS(
                f"{len(created)} trajet(s) réel(s) généré(s) pour les {weeks} prochaines semaines."
            )
        )
