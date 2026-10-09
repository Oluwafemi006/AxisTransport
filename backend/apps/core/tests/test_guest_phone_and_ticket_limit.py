from django.core.cache import cache
from django.test import override_settings
from rest_framework.test import APITestCase

from apps.core.models import Booking, Ticket
from apps.core.services import is_plausible_phone

from .factories import build_operational_context

BOOKINGS = "/api/v1/client/bookings/"


class GuestPhoneTests(APITestCase):
    """Sans compte, un téléphone valide est obligatoire ; avec un compte, il reste facultatif."""

    def setUp(self):
        self.context = build_operational_context()
        self.seat = self.context["trip"].seats.order_by("number").first()

    def payload(self, **extra):
        return {
            "trip": self.context["trip"].pk,
            "passengers": [{"full_name": "Awa Test", "seat": self.seat.pk}],
            **extra,
        }

    def test_guest_without_phone_is_refused_and_nothing_is_held(self):
        for body in (self.payload(), self.payload(contact_phone=""), self.payload(contact_phone="   ")):
            response = self.client.post(BOOKINGS, body, format="json")
            self.assertEqual(response.status_code, 400, response.data)
            self.assertIn("contact_phone", response.data)
        self.assertEqual(Booking.objects.count(), 0)
        self.seat.refresh_from_db()
        self.assertEqual(self.seat.status, "AVAILABLE")

    def test_guest_with_implausible_phone_is_refused(self):
        for phone in ("abc", "12345", "+", "90 00 00 00 x", "1" * 16):
            response = self.client.post(BOOKINGS, self.payload(contact_phone=phone), format="json")
            self.assertEqual(response.status_code, 400, phone)

    def test_guest_with_phone_can_book(self):
        response = self.client.post(BOOKINGS, self.payload(contact_phone="+229 01 90 00 00 00"), format="json")
        self.assertEqual(response.status_code, 201, response.data)
        self.assertIn("guest_access_token", response.data)

    def test_logged_in_client_can_book_without_phone(self):
        self.client.force_authenticate(self.context["client"])
        response = self.client.post(BOOKINGS, self.payload(), format="json")
        self.assertEqual(response.status_code, 201, response.data)

    def test_phone_format_has_no_country_rule(self):
        for phone in ("90000000", "+33 6 12 34 56 78", "(0)1-90.00.00", "+2290190000000"):
            self.assertTrue(is_plausible_phone(phone), phone)


class PublicTicketRateLimitTests(APITestCase):
    def setUp(self):
        cache.clear()
        context = build_operational_context()
        trip = context["trip"]
        self.ticket = Ticket.objects.create(
            trip=trip,
            seat=trip.seats.order_by("number").first(),
            passenger_name="Awa Test",
            amount=1000,
            currency="XOF",
            status=Ticket.Status.ISSUED,
        )
        self.url = f"/api/v1/client/tickets/public/{self.ticket.reference}/"

    def test_default_limit_is_sixty_per_minute_per_address(self):
        statuses = [self.client.get(f"/api/v1/client/tickets/public/AX-ESSAI-{index:04d}/").status_code for index in range(60)]
        self.assertEqual(set(statuses), {404})
        # 61e lecture de la même adresse dans la minute : refusée, même avec une référence valide.
        blocked = self.client.get(self.url)
        self.assertEqual(blocked.status_code, 429)
        self.assertNotIn("qr_token", blocked.json())
        # Une autre adresse n'est pas pénalisée.
        self.assertEqual(self.client.get(self.url, REMOTE_ADDR="10.9.9.9").status_code, 200)

    def test_address_is_read_behind_one_trusted_proxy(self):
        from rest_framework.settings import api_settings

        with override_settings(REST_FRAMEWORK={**api_settings.user_settings, "NUM_PROXIES": 1}):
            # Derrière un proxy, tous les appels arrivent de la même machine : c'est X-Forwarded-For qui distingue les visiteurs.
            for _ in range(60):
                self.client.get(self.url, HTTP_X_FORWARDED_FOR="203.0.113.7")
            self.assertEqual(self.client.get(self.url, HTTP_X_FORWARDED_FOR="203.0.113.7").status_code, 429)
            self.assertEqual(self.client.get(self.url, HTTP_X_FORWARDED_FOR="203.0.113.8").status_code, 200)
