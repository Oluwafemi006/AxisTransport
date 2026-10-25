from datetime import time
from django.core.management.base import BaseCommand
from apps.core.models import Location, Route, RouteStop, Vehicle, WeeklySchedule
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
        parser.add_argument(
            "--activate-stops",
            action="store_true",
            default=False,
            help="Active immédiatement toutes les villes de la ligne pour la recherche client",
        )

    def handle(self, *args, **options):
        # Villes de la ligne : créées ou récupérées
        stop_names = ["Parakou", "Savè", "Kétou", "Porto-Novo", "Cotonou"]
        activate_stops = options.get("activate_stops", False)
        locations = {}
        for name in stop_names:
            loc, _ = Location.objects.get_or_create(name=name)
            if activate_stops and not loc.active:
                loc.active = True
                loc.save(update_fields=["active"])
            locations[name] = loc

        cotonou = locations["Cotonou"]
        parakou = locations["Parakou"]

        route_cotonou_parakou, _ = Route.objects.get_or_create(origin=cotonou, destination=parakou)
        route_parakou_cotonou, _ = Route.objects.get_or_create(origin=parakou, destination=cotonou)

        # Séquence ordonnée des étapes pour chaque itinéraire (RouteStop)
        # Parakou → Cotonou (descente : 1=Parakou, 2=Savè, 3=Kétou, 4=Porto-Novo, 5=Cotonou)
        descending_order = ["Parakou", "Savè", "Kétou", "Porto-Novo", "Cotonou"]
        for pos, name in enumerate(descending_order, start=1):
            RouteStop.objects.update_or_create(
                route=route_parakou_cotonou,
                position=pos,
                defaults={"location": locations[name]},
            )

        # Cotonou → Parakou (montée : 1=Cotonou, 2=Porto-Novo, 3=Kétou, 4=Savè, 5=Parakou)
        ascending_order = ["Cotonou", "Porto-Novo", "Kétou", "Savè", "Parakou"]
        for pos, name in enumerate(ascending_order, start=1):
            RouteStop.objects.update_or_create(
                route=route_cotonou_parakou,
                position=pos,
                defaults={"location": locations[name]},
            )

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
