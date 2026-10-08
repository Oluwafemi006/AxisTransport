from datetime import datetime, time, timedelta
from decimal import Decimal

from django.conf import settings
from django.core.management.base import BaseCommand, CommandError
from django.utils import timezone

from apps.core.models import FareRule, Location, PaymentMethod, Route, SystemSetting, Trip, User, Vehicle
from apps.core.services import generate_trip_seats

DEMO_ACCOUNTS = [
    ("demo_client", User.Role.CLIENT, "Client"),
    ("demo_guichet", User.Role.COUNTER, "Guichet"),
    ("demo_controleur", User.Role.CONTROLLER, "Contrôleur"),
    ("demo_admin", User.Role.ADMIN, "Admin"),
]


class Command(BaseCommand):
    help = "Crée des données de DÉMONSTRATION (comptes, véhicule, voyage, tarif). Refuse de tourner hors DEBUG."

    def add_arguments(self, parser):
        parser.add_argument("--password", default="demo-axis-2026", help="Mot de passe des comptes de démonstration.")

    def handle(self, *args, **options):
        if not settings.DEBUG:
            raise CommandError("seed_demo est réservé au développement : DJANGO_DEBUG doit valoir true.")

        for username, role, label in DEMO_ACCOUNTS:
            user, _ = User.objects.get_or_create(
                username=username, defaults={"role": role, "first_name": label, "last_name": "DÉMO"}
            )
            user.role = role
            user.is_staff = user.is_superuser = role == User.Role.ADMIN
            user.set_password(options["password"])
            user.save()

        origin, _ = Location.objects.get_or_create(name="Cotonou DÉMO")
        destination, _ = Location.objects.get_or_create(name="Parakou DÉMO")
        route, _ = Route.objects.get_or_create(origin=origin, destination=destination)

        seat_plan = [
            {"label": f"{row}{letter}", "row": row, "column": column}
            for row in range(1, 4)
            for column, letter in enumerate("ABCD", start=1)
        ]
        vehicle, _ = Vehicle.objects.get_or_create(
            category=Vehicle.Category.BUS,
            name="Bus DÉMO",
            defaults={"capacity": len(seat_plan), "seat_configuration": seat_plan, "state": Vehicle.State.ACTIVE},
        )
        FareRule.objects.get_or_create(
            route=route,
            name="Tarif DÉMO",
            defaults={"rule_type": FareRule.RuleType.STANDARD, "amount": Decimal("1000.00")},
        )
        SystemSetting.objects.get_or_create(
            key="ticket_hold_minutes", defaults={"value": 15, "description": "Valeur de DÉMO"}
        )
        PaymentMethod.objects.get_or_create(
            code="especes-demo", defaults={"label": "Espèces DÉMO (guichet)", "active": True}
        )
        PaymentMethod.objects.update_or_create(
            code="SIMULATION",
            defaults={"label": "Paiement simulé DÉMO", "active": settings.AXIS_PAYMENT_SIMULATION},
        )

        # Un départ aujourd'hui (contrôlable le jour même) et un départ demain.
        today = timezone.localdate()
        departures = [
            timezone.make_aware(datetime.combine(today, time(23, 30))),
            timezone.make_aware(datetime.combine(today + timedelta(days=1), time(8, 0))),
        ]
        created_trips = 0
        for departure in departures:
            if departure <= timezone.now():
                continue
            trip, created = Trip.objects.get_or_create(
                route=route, vehicle=vehicle, departure_at=departure, defaults={"note": "Voyage DÉMO"}
            )
            generate_trip_seats(trip)
            created_trips += int(created)

        self.stdout.write(self.style.SUCCESS("Données de DÉMONSTRATION prêtes."))
        self.stdout.write(f"Comptes : {', '.join(name for name, _, _ in DEMO_ACCOUNTS)} / mot de passe : {options['password']}")
        self.stdout.write(f"Parcours : {route} · véhicule : {vehicle.name} ({len(seat_plan)} sièges) · voyages créés : {created_trips}")
        self.stdout.write(
            "Paiement simulé : "
            + ("ACTIF" if settings.AXIS_PAYMENT_SIMULATION else "inactif (AXIS_PAYMENT_SIMULATION=true pour l'activer)")
        )
