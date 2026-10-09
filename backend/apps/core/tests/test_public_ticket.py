from django.core.cache import cache
from django.test import override_settings
from rest_framework.test import APITestCase

from apps.core.models import Ticket

from .factories import build_operational_context


class PublicTicketAPITest(APITestCase):
    def setUp(self):
        cache.clear()  # compteur de la limite de requêtes
        self.context = build_operational_context()
        trip = self.context["trip"]
        self.seat = trip.seats.order_by("number").first()
        self.ticket = Ticket.objects.create(
            trip=trip,
            seat=self.seat,
            passenger_name="Jean Dupont",
            passenger_phone="+22901020304",
            amount=1000,
            currency="XOF",
            status=Ticket.Status.ISSUED,
        )

    def test_get_public_ticket_success(self):
        response = self.client.get(f"/api/v1/client/tickets/public/{self.ticket.reference}/")
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertEqual(data["reference"], self.ticket.reference)
        self.assertEqual(data["passenger_name"], "Jean Dupont")
        self.assertEqual(data["seat_label"], self.seat.number)
        self.assertEqual(data["origin"], "Ville départ")
        self.assertEqual(data["destination"], "Ville arrivée")
        self.assertEqual(data["status"], Ticket.Status.ISSUED)
        self.assertIn("AXIS Transport", data["company_name"])
        # Le téléphone du passager ne doit jamais sortir sur une page publique.
        self.assertNotIn("passenger_phone", data)
        self.assertNotIn("+22901020304", response.content.decode())

    def test_get_public_ticket_not_found(self):
        response = self.client.get("/api/v1/client/tickets/public/INVALID-REF/")
        self.assertEqual(response.status_code, 404)

    @override_settings(PUBLIC_WEB_URL="")
    def test_no_link_is_invented_when_site_address_is_not_configured(self):
        data = self.client.get(f"/api/v1/client/tickets/public/{self.ticket.reference}/").json()
        self.assertEqual(data["public_url"], "")
        self.client.force_authenticate(self.context["client"])
        self.ticket.customer = self.context["client"]
        self.ticket.save(update_fields=["customer"])
        ticket = self.client.get(f"/api/v1/client/tickets/{self.ticket.pk}/").json()
        self.assertEqual(ticket["public_url"], "")

    @override_settings(PUBLIC_WEB_URL="https://exemple.test")
    def test_link_uses_configured_site_address(self):
        data = self.client.get(f"/api/v1/client/tickets/public/{self.ticket.reference}/").json()
        self.assertEqual(data["public_url"], f"https://exemple.test/t/{self.ticket.reference}")
