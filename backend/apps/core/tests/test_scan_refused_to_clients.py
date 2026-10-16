from rest_framework.test import APITestCase

from apps.core.models import Ticket, TicketControl

from .factories import build_operational_context


class ScanRefusedToClientsTests(APITestCase):
    """Un compte client (même connecté dans l'app unique) ne peut jamais contrôler un billet."""

    def setUp(self):
        self.context = build_operational_context()
        trip = self.context["trip"]
        self.ticket = Ticket.objects.create(
            trip=trip, seat=trip.seats.order_by("number").first(), passenger_name="Awa Test",
            amount=1000, currency="XOF", status=Ticket.Status.ISSUED,
        )

    def test_client_gets_403_on_every_scan_address_and_ticket_stays_unchecked(self):
        self.client.force_authenticate(self.context["client"])
        token = str(self.ticket.qr_token)
        self.assertEqual(self.client.post("/api/v1/staff/tickets/validate/", {"qr_token": token}, format="json").status_code, 403)
        # Ancienne adresse /api/v1/tickets/validate-qr/ : NON couverte ici, elle accepte aujourd'hui tout compte
        # connecté (faille signalée dans le rapport du lot 3, correction en attente d'accord).
        self.assertEqual(self.client.post("/api/v1/staff/sales/sell/", {}, format="json").status_code, 403)
        self.ticket.refresh_from_db()
        self.assertEqual(self.ticket.status, Ticket.Status.ISSUED)
        self.assertFalse(TicketControl.objects.exists())

    def test_controller_still_scans(self):
        self.client.force_authenticate(self.context["controller"])
        response = self.client.post("/api/v1/staff/tickets/validate/", {"qr_token": str(self.ticket.qr_token)}, format="json")
        self.assertEqual(response.status_code, 200, response.data)
