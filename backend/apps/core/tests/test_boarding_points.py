from datetime import timedelta
from decimal import Decimal
from io import StringIO

from django.core.management import call_command
from django.utils import timezone
from rest_framework.test import APITestCase

from apps.core.models import (
    BoardingPoint,
    Booking,
    Location,
    PaymentMethod,
    Route,
    RouteStop,
    SystemSetting,
    Ticket,
    Trip,
    User,
    Vehicle,
)
from apps.core.services import generate_trip_seats


class BoardingPointsTests(APITestCase):
    def setUp(self):
        call_command("load_segment_fares", stdout=StringIO())
        call_command("load_boarding_points", stdout=StringIO())
        SystemSetting.objects.update_or_create(key="ticket_hold_minutes", defaults={"value": 10})
        self.parakou = Location.objects.get(name="Parakou")
        self.save = Location.objects.get(name="Savè")
        self.save.active = True
        self.save.save(update_fields=["active"])
        self.porto = Location.objects.get(name="Porto-Novo")
        self.cotonou = Location.objects.get(name="Cotonou")

        self.route = Route.objects.create(
            origin=self.parakou,
            destination=self.cotonou,
            active=True,
        )
        RouteStop.objects.create(route=self.route, location=self.parakou, position=1, offset_minutes=0)
        RouteStop.objects.create(route=self.route, location=self.save, position=2, offset_minutes=120)
        RouteStop.objects.create(route=self.route, location=self.cotonou, position=3, offset_minutes=360)

        self.vehicle = Vehicle.objects.create(
            category=Vehicle.Category.BUS,
            name="Car TEST",
            registration_number="TEST-0001-BJ",
            capacity=8,
            state=Vehicle.State.ACTIVE,
        )
        self.trip = Trip.objects.create(
            route=self.route,
            vehicle=self.vehicle,
            departure_at=timezone.now() + timedelta(days=2),
            status=Trip.Status.SCHEDULED,
        )
        generate_trip_seats(self.trip)
        self.cash = PaymentMethod.objects.create(
            code="CASH",
            label="Espèces TEST",
            active=True,
        )
        self.admin = User.objects.create_user(
            username="admin_bp_test",
            password="secret",
            role=User.Role.ADMIN,
            first_name="Admin TEST",
        )
        self.counter = User.objects.create_user(
            username="counter_bp_test",
            password="secret",
            role=User.Role.COUNTER,
            first_name="Guichet TEST",
        )
        self.controller = User.objects.create_user(
            username="controller_bp_test",
            password="secret",
            role=User.Role.CONTROLLER,
            first_name="Controleur TEST",
        )
        self.client_user = User.objects.create_user(
            username="client_bp_test",
            password="secret",
            role=User.Role.CLIENT,
            first_name="Client TEST",
        )

    def test_load_boarding_points_creates_only_parc_albarika_in_parakou_idempotently(self):
        call_command("load_boarding_points", stdout=StringIO())
        points = list(BoardingPoint.objects.select_related("location"))
        self.assertEqual(len(points), 1)
        self.assertEqual(points[0].location, self.parakou)
        self.assertEqual(points[0].name, "Parc ALBARIKA")
        self.assertTrue(points[0].active)
        self.assertEqual(BoardingPoint.objects.filter(location=self.porto).count(), 0)
        self.assertEqual(BoardingPoint.objects.filter(location=self.cotonou).count(), 0)

    def test_load_boarding_points_does_not_recreate_after_rename_or_deactivation(self):
        point = BoardingPoint.objects.get(location=self.parakou, name="Parc ALBARIKA")
        # Cas 1 : renommage et désactivation par l'admin
        point.name = "TEST Parc Renommé"
        point.active = False
        point.save(update_fields=["name", "active"])

        call_command("load_boarding_points", stdout=StringIO())
        points = list(BoardingPoint.objects.filter(location=self.parakou))
        self.assertEqual(len(points), 1)
        self.assertEqual(points[0].name, "TEST Parc Renommé")
        self.assertFalse(points[0].active)
        self.assertFalse(BoardingPoint.objects.filter(location=self.parakou, name="Parc ALBARIKA").exists())

    def test_single_point_preselected_zero_point_city_alone_and_full_fare_7500(self):
        seat = self.trip.seats.first()
        response = self.client.post(
            "/api/v1/client/bookings/",
            {
                "trip": self.trip.pk,
                "contact_phone": "90000001",
                "passengers": [{"full_name": "Passager TEST", "phone": "90000001", "seat": seat.pk}],
            },
            format="json",
        )
        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(Decimal(str(response.data["amount"])), Decimal("7500"))
        self.assertEqual(response.data["boarding_point_name"], "Parc ALBARIKA")
        self.assertEqual(response.data["alighting_point_name"], "")
        self.assertEqual(response.data["boarding_display"], "Parakou – Parc ALBARIKA")
        self.assertEqual(response.data["alighting_display"], "Cotonou")
        ticket_data = response.data["tickets"][0]
        self.assertEqual(ticket_data["boarding_display"], "Parakou – Parc ALBARIKA")
        self.assertEqual(ticket_data["alighting_display"], "Cotonou")
        self.assertEqual(ticket_data["print_info"]["boarding_display"], "Parakou – Parc ALBARIKA")
        self.assertEqual(ticket_data["print_info"]["alighting_display"], "Cotonou")

    def test_segment_parakou_save_keeps_4500_fare_and_boarding_point_snapshot_on_rename(self):
        albarika = BoardingPoint.objects.get(location=self.parakou, name="Parc ALBARIKA")
        seat = self.trip.seats.first()
        response = self.client.post(
            "/api/v1/client/bookings/",
            {
                "trip": self.trip.pk,
                "origin": self.parakou.pk,
                "destination": self.save.pk,
                "boarding_point_id": albarika.pk,
                "contact_phone": "90000002",
                "passengers": [{"full_name": "Segment TEST", "phone": "90000002", "seat": seat.pk}],
            },
            format="json",
        )
        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(Decimal(str(response.data["amount"])), Decimal("4500"))
        booking = Booking.objects.get(pk=response.data["id"])
        ticket = booking.tickets.get()
        self.assertEqual(ticket.boarding_point_name, "Parc ALBARIKA")
        self.assertEqual(ticket.boarding_display, "Parakou – Parc ALBARIKA")
        self.assertEqual(ticket.alighting_display, "Savè")

        # Renommage du point : le billet déjà créé conserve la copie du nom d'origine.
        albarika.name = "TEST Parc Renommé"
        albarika.save(update_fields=["name"])
        ticket.refresh_from_db()
        booking.refresh_from_db()
        self.assertEqual(ticket.boarding_point_name, "Parc ALBARIKA")
        self.assertEqual(ticket.boarding_display, "Parakou – Parc ALBARIKA")
        self.assertEqual(booking.boarding_display, "Parakou – Parc ALBARIKA")

    def test_validation_rejects_wrong_city_inactive_point_and_requires_choice_when_multiple(self):
        seat = self.trip.seats.first()
        cotonou_point = BoardingPoint.objects.create(location=self.cotonou, name="TEST Gare Cotonou 1", active=True)
        # Point d'une autre ville rejeté pour l'embarquement à Parakou
        bad_city = self.client.post(
            "/api/v1/client/bookings/",
            {
                "trip": self.trip.pk,
                "boarding_point_id": cotonou_point.pk,
                "contact_phone": "90000003",
                "passengers": [{"full_name": "TEST", "phone": "90000003", "seat": seat.pk}],
            },
            format="json",
        )
        self.assertEqual(bad_city.status_code, 400)
        self.assertIn("Parakou", str(bad_city.data))

        # Point inactif rejeté
        inactive_point = BoardingPoint.objects.create(location=self.parakou, name="TEST Point Inactif", active=False)
        bad_active = self.client.post(
            "/api/v1/client/bookings/",
            {
                "trip": self.trip.pk,
                "boarding_point_id": inactive_point.pk,
                "contact_phone": "90000003",
                "passengers": [{"full_name": "TEST", "phone": "90000003", "seat": seat.pk}],
            },
            format="json",
        )
        self.assertEqual(bad_active.status_code, 400)
        self.assertIn("est désactivé", str(bad_active.data))

        # Plusieurs points actifs à Cotonou : choix obligatoire
        cotonou_point_2 = BoardingPoint.objects.create(location=self.cotonou, name="TEST Gare Cotonou 2", active=True)
        missing_choice = self.client.post(
            "/api/v1/client/bookings/",
            {
                "trip": self.trip.pk,
                "contact_phone": "90000003",
                "passengers": [{"full_name": "TEST", "phone": "90000003", "seat": seat.pk}],
            },
            format="json",
        )
        self.assertEqual(missing_choice.status_code, 400)
        self.assertIn("Veuillez choisir un point de débarquement pour la ville de Cotonou", str(missing_choice.data))

        # Choix explicite d'un des points actifs à Cotonou : accepté
        ok = self.client.post(
            "/api/v1/client/bookings/",
            {
                "trip": self.trip.pk,
                "alighting_point_id": cotonou_point_2.pk,
                "contact_phone": "90000003",
                "passengers": [{"full_name": "TEST", "phone": "90000003", "seat": seat.pk}],
            },
            format="json",
        )
        self.assertEqual(ok.status_code, 201, ok.data)
        self.assertEqual(ok.data["alighting_display"], "Cotonou – TEST Gare Cotonou 2")

    def test_admin_permissions_and_deletion_blocked_when_point_already_used(self):
        albarika = BoardingPoint.objects.get(location=self.parakou, name="Parc ALBARIKA")
        for non_admin in (self.client_user, self.counter, self.controller):
            self.client.force_authenticate(non_admin)
            self.assertEqual(
                self.client.post(
                    "/api/v1/boarding-points/",
                    {"location": self.cotonou.pk, "name": "TEST Interdit"},
                    format="json",
                ).status_code,
                403,
            )
            self.assertEqual(
                self.client.patch(
                    f"/api/v1/boarding-points/{albarika.pk}/",
                    {"active": False},
                    format="json",
                ).status_code,
                403,
            )
            self.assertEqual(self.client.get("/api/v1/boarding-points/?all=true").status_code, 403)

        self.client.force_authenticate(self.admin)
        created = self.client.post(
            "/api/v1/boarding-points/",
            {"location": self.porto.pk, "name": "TEST Point Porto-Novo", "active": True, "order": 1},
            format="json",
        )
        self.assertEqual(created.status_code, 201, created.data)
        porto_point_id = created.data["id"]

        # Point non utilisé : suppression autorisée
        self.assertEqual(self.client.delete(f"/api/v1/boarding-points/{porto_point_id}/").status_code, 204)

        # Vente au guichet utilisant Parc ALBARIKA
        self.client.force_authenticate(self.counter)
        seat = self.trip.seats.first()
        sold = self.client.post(
            "/api/v1/staff/tickets/sell_counter/",
            {
                "trip_id": self.trip.pk,
                "seat_id": seat.pk,
                "passenger_name": "Client Guichet TEST",
                "passenger_phone": "90000004",
                "payment_method": self.cash.pk,
                "boarding_point_id": albarika.pk,
            },
            format="json",
        )
        self.assertEqual(sold.status_code, 201, sold.data)
        sold_ticket = Ticket.objects.get(reference=sold.data["ticket_reference"])
        self.assertEqual(sold_ticket.boarding_display, "Parakou – Parc ALBARIKA")

        # Point ayant déjà servi : suppression refusée même pour l'admin, mais désactivation permise
        self.client.force_authenticate(self.admin)
        delete_used = self.client.delete(f"/api/v1/boarding-points/{albarika.pk}/")
        self.assertEqual(delete_used.status_code, 400)
        self.assertIn("déjà servi", str(delete_used.data))

        deactivate = self.client.patch(
            f"/api/v1/boarding-points/{albarika.pk}/",
            {"active": False},
            format="json",
        )
        self.assertEqual(deactivate.status_code, 200)
        self.assertFalse(deactivate.data["active"])
        self.assertTrue(deactivate.data["is_used"])

