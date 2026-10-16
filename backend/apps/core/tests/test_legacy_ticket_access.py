from rest_framework.test import APITestCase

from apps.core.models import Ticket, TicketControl, User

from .factories import build_operational_context


class LegacyTicketActionAccessTests(APITestCase):
    """
    Anciennes actions de /api/v1/tickets/ : leurs règles d'accès propres s'appliquent
    (avant correction, celles de la vue les remplaçaient par « tout compte connecté »).
    """

    def setUp(self):
        self.context = build_operational_context()
        self.trip = self.context["trip"]
        self.counter = User.objects.create_user(username="guichet", password="secret", role=User.Role.COUNTER)
        seats = list(self.trip.seats.order_by("number"))
        self.issued = Ticket.objects.create(
            trip=self.trip, seat=seats[0], passenger_name="Awa", amount=1000, currency="XOF",
            status=Ticket.Status.ISSUED, customer=self.context["client"],
        )
        self.held = Ticket.objects.create(
            trip=self.trip, seat=seats[1], passenger_name="Awa", amount=1000, currency="XOF",
            status=Ticket.Status.HELD, customer=self.context["client"],
        )

    def scan(self, user, **body):
        self.client.force_authenticate(user)
        payload = body or {"qr_token": str(self.issued.qr_token)}
        return self.client.post("/api/v1/tickets/validate-qr/", payload, format="json")

    # ── Scan (validate-qr)
    def test_client_and_counter_cannot_scan(self):
        for user in (self.context["client"], self.counter):
            self.assertEqual(self.scan(user).status_code, 403, user.role)
        self.issued.refresh_from_db()
        self.assertEqual(self.issued.status, Ticket.Status.ISSUED)
        self.assertFalse(TicketControl.objects.exists())

    def test_controller_portal_call_still_works(self):
        # Même demande que le portail /controleur du site : référence, voyage choisi, validation manuelle.
        response = self.scan(
            self.context["controller"], reference=self.issued.reference, trip=self.trip.pk, method="MANUAL"
        )
        self.assertEqual(response.status_code, 200, response.data)
        self.issued.refresh_from_db()
        self.assertEqual(self.issued.status, Ticket.Status.CHECKED)

    def test_admin_can_scan(self):
        self.assertEqual(self.scan(self.context["admin"]).status_code, 200)

    def test_anonymous_cannot_scan(self):
        self.client.force_authenticate(None)
        self.assertEqual(self.client.post("/api/v1/tickets/validate-qr/", {"qr_token": str(self.issued.qr_token)}, format="json").status_code, 401)

    # ── Changement d'état (transition)
    def test_client_cannot_mark_own_ticket_paid_or_issued(self):
        self.client.force_authenticate(self.context["client"])
        for status in (Ticket.Status.PAID, Ticket.Status.ISSUED, Ticket.Status.CANCELLED):
            response = self.client.post(f"/api/v1/tickets/{self.held.pk}/transition/", {"status": status}, format="json")
            self.assertEqual(response.status_code, 403, status)
        self.held.refresh_from_db()
        self.assertEqual(self.held.status, Ticket.Status.HELD)

    def test_staff_keep_their_transition_rights(self):
        self.client.force_authenticate(self.counter)
        self.assertEqual(
            self.client.post(f"/api/v1/tickets/{self.issued.pk}/transition/", {"status": Ticket.Status.CHECKED}, format="json").status_code,
            200,
        )
        self.client.force_authenticate(self.context["controller"])
        response = self.client.post(
            f"/api/v1/tickets/{self.issued.pk}/transition/?trip={self.trip.pk}", {"status": Ticket.Status.COMPLETED}, format="json"
        )
        self.assertEqual(response.status_code, 200, response.data)
