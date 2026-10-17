from datetime import datetime, time, timedelta
from decimal import Decimal

from django.conf import settings
from django.core.management.base import BaseCommand, CommandError
from django.utils import timezone

from apps.core.models import (
    FareRule,
    LineStop,
    Location,
    PaymentMethod,
    Route,
    Seat,
    SegmentFare,
    SystemSetting,
    Trip,
    User,
    Vehicle,
)
from apps.core.payments import settle_booking_payment
from apps.core.services import generate_trip_seats, reserve_booking

DEMO_ACCOUNTS = [
    ("demo_client", User.Role.CLIENT, "Client"),
    ("demo_guichet", User.Role.COUNTER, "Guichet"),
    ("demo_controleur", User.Role.CONTROLLER, "Contrôleur"),
    ("demo_admin", User.Role.ADMIN, "Admin"),
]


class Command(BaseCommand):
    help = "Crée des données de DÉMONSTRATION (comptes, véhicule, voyage, tarif). Refuse de tourner hors DEBUG ou hors environnement local."

    def add_arguments(self, parser):
        parser.add_argument("--password", default="demo-axis-2026", help="Mot de passe des comptes de démonstration.")
        parser.add_argument(
            "--with-ticket",
            action="store_true",
            help="Crée aussi un billet DÉMO émis sur un départ d'aujourd'hui, pour tester le scan.",
        )

    def handle(self, *args, **options):
        if not settings.DEBUG:
            raise CommandError("seed_demo est réservé au développement : DJANGO_DEBUG doit valoir true.")
        if settings.AXIS_ENVIRONMENT != "local":
            raise CommandError(
                "seed_demo est réservé au poste de développement : AXIS_ENVIRONMENT doit valoir « local » "
                "(défini seulement dans compose.yaml). Jamais sur le serveur."
            )

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
        # Le prix du billet vient de la grille par tronçon : arrêts DÉMO rangés loin après ceux de la vraie ligne.
        demo_start, _ = LineStop.objects.get_or_create(location=origin, defaults={"position": 901})
        demo_end, _ = LineStop.objects.get_or_create(location=destination, defaults={"position": 902})
        SegmentFare.objects.get_or_create(start=demo_start, end=demo_end, defaults={"amount": 1000})
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

        if options["with_ticket"]:
            self._issue_demo_ticket(route, vehicle)

        self.stdout.write(self.style.SUCCESS("Données de DÉMONSTRATION prêtes."))
        self.stdout.write(f"Comptes : {', '.join(name for name, _, _ in DEMO_ACCOUNTS)} / mot de passe : {options['password']}")
        self.stdout.write(f"Parcours : {route} · véhicule : {vehicle.name} ({len(seat_plan)} sièges) · voyages créés : {created_trips}")
        self.stdout.write(
            "Paiement simulé : "
            + ("ACTIF" if settings.AXIS_PAYMENT_SIMULATION else "inactif (AXIS_PAYMENT_SIMULATION=true pour l'activer)")
        )

    def _issue_demo_ticket(self, route, vehicle):
        """
        Billet DÉMO émis par le chemin normal (réservation puis encaissement guichet).
        Sans voyage sélectionné, le contrôle n'accepte un billet que le jour de son départ :
        le départ est donc placé aujourd'hui, dans les deux heures si la journée le permet.
        """
        now = timezone.now()
        end_of_day = timezone.make_aware(datetime.combine(timezone.localdate(), time(23, 59)))
        trip = (
            Trip.objects.filter(
                route=route,
                note="Voyage DÉMO",
                status=Trip.Status.SCHEDULED,
                departure_at__gt=now,
                departure_at__lte=end_of_day,
                seats__status=Seat.Status.AVAILABLE,
            )
            .order_by("departure_at")
            .first()
        )
        if trip is None:
            trip = Trip.objects.create(
                route=route,
                vehicle=vehicle,
                departure_at=min(now + timedelta(hours=2), end_of_day),
                note="Voyage DÉMO",
            )
            generate_trip_seats(trip)
        seat = trip.seats.filter(status=Seat.Status.AVAILABLE).order_by("row", "column", "number").first()
        if seat is None:
            raise CommandError("Aucun siège libre sur le voyage DÉMO d'aujourd'hui.")

        booking, _ = reserve_booking(
            trip=trip, passengers=[{"full_name": "Passager DÉMO", "seat": seat}], channel="COUNTER"
        )
        settlement = settle_booking_payment(
            booking,
            payment_method=PaymentMethod.objects.get(code="especes-demo"),
            actor=User.objects.get(username="demo_guichet"),
        )
        ticket = settlement.tickets[0]
        departure = timezone.localtime(trip.departure_at)
        self.stdout.write(self.style.SUCCESS(f"Billet DÉMO émis : {ticket.reference}"))
        self.stdout.write(f"  Départ : {departure:%d/%m/%Y %H:%M} · siège {seat.number} · QR : {ticket.qr_token}")
        self.stdout.write(f"  À afficher en grand sur le PC : /t/{ticket.reference} (site web)")
        self.stdout.write(f"  Scannable aujourd'hui seulement ({departure:%d/%m/%Y}) ; relancer la commande un autre jour.")
