from datetime import timedelta
from decimal import Decimal

from django.utils import timezone
from rest_framework.test import APITestCase

from apps.core.models import Booking, PaymentMethod, RentalBooking, Ticket, Trip, User, Vehicle
from apps.core.services import DEPARTED_MESSAGE

from .factories import build_operational_context


class DepartedTripTests(APITestCase):
    """Un départ déjà parti n'est plus réservable, sauf pour la vente du contrôleur à l'arrêt."""

    def setUp(self):
        self.context = build_operational_context()
        self.trip = self.context["trip"]
        # Parti il y a une minute (aujourd'hui).
        Trip.objects.filter(pk=self.trip.pk).update(departure_at=timezone.now() - timedelta(minutes=1))
        self.trip.refresh_from_db()
        self.seats = list(self.trip.seats.order_by("number"))
        self.counter = User.objects.create_user(username="guichet", password="secret", role=User.Role.COUNTER)
        self.cash = PaymentMethod.objects.create(code="especes", label="Espèces", active=True)

    def message_of(self, response):
        return str(response.data)

    def test_client_booking_is_refused(self):
        self.client.force_authenticate(self.context["client"])
        response = self.client.post(
            "/api/v1/client/bookings/",
            {"trip": self.trip.pk, "passengers": [{"full_name": "Awa", "seat": self.seats[0].pk}]},
            format="json",
        )
        self.assertEqual(response.status_code, 400, response.data)
        self.assertIn(DEPARTED_MESSAGE, self.message_of(response))
        self.assertFalse(Booking.objects.exists())

    def test_counter_sale_on_the_web_portal_is_refused(self):
        self.client.force_authenticate(self.counter)
        response = self.client.post(
            "/api/v1/tickets/", {"trip": self.trip.pk, "seat": self.seats[0].pk, "passenger_name": "Awa"}, format="json"
        )
        self.assertEqual(response.status_code, 400, response.data)
        self.assertIn(DEPARTED_MESSAGE, self.message_of(response))
        self.assertFalse(Ticket.objects.exists())

    def sell_from_staff_app(self, user, key):
        self.client.force_authenticate(user)
        return self.client.post(
            "/api/v1/staff/sales/sell/",
            {
                "idempotency_key": key,
                "trip": self.trip.pk,
                "seat": self.seats[0].pk,
                "passenger_name": "Awa",
                "payment_method": self.cash.pk,
            },
            format="json",
        )

    def test_counter_cannot_sell_a_departed_trip_from_the_staff_app(self):
        response = self.sell_from_staff_app(self.counter, "vente-partie-01")
        self.assertEqual(response.status_code, 400, response.data)
        self.assertFalse(Booking.objects.exists())

    def test_controller_still_sells_at_the_stop_after_departure(self):
        response = self.sell_from_staff_app(self.context["controller"], "vente-arret-01")
        self.assertIn(response.status_code, (200, 201), response.data)
        self.assertEqual(Booking.objects.count(), 1)

    def test_future_departure_is_still_bookable(self):
        Trip.objects.filter(pk=self.trip.pk).update(departure_at=timezone.now() + timedelta(hours=1))
        self.client.force_authenticate(self.context["client"])
        response = self.client.post(
            "/api/v1/client/bookings/",
            {"trip": self.trip.pk, "passengers": [{"full_name": "Awa", "seat": self.seats[0].pk}]},
            format="json",
        )
        self.assertEqual(response.status_code, 201, response.data)


class PastRentalStartTests(APITestCase):
    """Une demande de location ne peut pas commencer dans le passé."""

    def setUp(self):
        self.context = build_operational_context()
        self.vehicle = Vehicle.objects.create(
            category=Vehicle.Category.RENTAL,
            name="TEST voiture",
            capacity=4,
            rental_daily_rate=Decimal("20000"),
            state=Vehicle.State.ACTIVE,
        )
        self.client.force_authenticate(self.context["client"])

    def ask(self, starts_at):
        return self.client.post(
            "/api/v1/client/rentals/",
            {"vehicle": self.vehicle.pk, "starts_at": starts_at.isoformat(), "ends_at": (starts_at + timedelta(days=2)).isoformat()},
            format="json",
        )

    def test_past_start_is_refused(self):
        response = self.ask(timezone.now() - timedelta(hours=1))
        self.assertEqual(response.status_code, 400, response.data)
        self.assertIn("Le début de la location doit être dans le futur.", str(response.data))
        self.assertFalse(RentalBooking.objects.exists())

    def test_future_start_is_accepted(self):
        response = self.ask(timezone.now() + timedelta(days=1))
        self.assertEqual(response.status_code, 201, response.data)
