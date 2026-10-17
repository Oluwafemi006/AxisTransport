from datetime import timedelta

from django.utils import timezone
from rest_framework.test import APITestCase

from apps.core.models import Booking, PaymentMethod, SystemSetting, Ticket, User
from apps.core.services import ReservationsClosed

from .factories import build_operational_context


class ReservationsClosedTests(APITestCase):
    """
    Durée de blocage d'un siège (« ticket_hold_minutes ») non saisie : aucune réservation, et un message
    compréhensible, sans texte technique, adapté au client ou au personnel.
    """

    def setUp(self):
        self.context = build_operational_context(trip_date=timezone.localdate() + timedelta(days=1))
        self.trip = self.context["trip"]
        self.seats = list(self.trip.seats.order_by("number"))
        self.counter = User.objects.create_user(username="guichet", password="secret", role=User.Role.COUNTER)
        self.cash = PaymentMethod.objects.create(code="especes", label="Espèces", active=True)
        SystemSetting.objects.filter(key="ticket_hold_minutes").delete()

    def assert_no_reservation(self):
        self.assertFalse(Booking.objects.exists())
        self.assertFalse(Ticket.objects.exists())

    def assert_plain_message(self, response, expected):
        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data["detail"], expected)
        self.assertNotIn("ticket_hold_minutes", str(response.data))

    def test_client_sees_that_bookings_are_not_open(self):
        self.client.force_authenticate(self.context["client"])
        response = self.client.post(
            "/api/v1/client/bookings/",
            {"trip": self.trip.pk, "passengers": [{"full_name": "Awa", "seat": self.seats[0].pk}]},
            format="json",
        )
        self.assert_plain_message(response, ReservationsClosed.CLIENT_MESSAGE)
        self.assert_no_reservation()

    def test_counter_is_told_what_the_admin_must_do(self):
        self.client.force_authenticate(self.counter)
        response = self.client.post(
            "/api/v1/tickets/", {"trip": self.trip.pk, "seat": self.seats[0].pk, "passenger_name": "Awa"}, format="json"
        )
        self.assert_plain_message(response, ReservationsClosed.STAFF_MESSAGE)
        self.assertIn("Tarifs & règles", response.data["detail"])
        self.assert_no_reservation()

    def test_staff_app_sale_gets_the_staff_message(self):
        self.client.force_authenticate(self.counter)
        response = self.client.post(
            "/api/v1/staff/sales/sell/",
            {
                "idempotency_key": "vente-fermee-01",
                "trip": self.trip.pk,
                "seat": self.seats[0].pk,
                "passenger_name": "Awa",
                "payment_method": self.cash.pk,
            },
            format="json",
        )
        self.assert_plain_message(response, ReservationsClosed.STAFF_MESSAGE)
        self.assert_no_reservation()

    def test_zero_or_invalid_duration_is_also_closed(self):
        self.client.force_authenticate(self.context["client"])
        for value in (0, -3, "abc"):
            SystemSetting.objects.update_or_create(key="ticket_hold_minutes", defaults={"value": value})
            response = self.client.post(
                "/api/v1/client/bookings/",
                {"trip": self.trip.pk, "passengers": [{"full_name": "Awa", "seat": self.seats[0].pk}]},
                format="json",
            )
            self.assert_plain_message(response, ReservationsClosed.CLIENT_MESSAGE)
        self.assert_no_reservation()

    def test_with_a_duration_booking_works_again(self):
        SystemSetting.objects.create(key="ticket_hold_minutes", value=10)
        self.client.force_authenticate(self.context["client"])
        response = self.client.post(
            "/api/v1/client/bookings/",
            {"trip": self.trip.pk, "passengers": [{"full_name": "Awa", "seat": self.seats[0].pk}]},
            format="json",
        )
        self.assertEqual(response.status_code, 201, response.data)
