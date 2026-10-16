from rest_framework.test import APITestCase

from apps.core.models import Ticket, TicketControl, TicketStatusHistory, User

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

    def test_counter_and_controller_can_no_longer_force_a_status(self):
        # Aucun écran ne se sert de cette action : guichet et contrôleur en sont exclus (vente par paiement, scan par validate-qr).
        cases = [
            (self.counter, self.held, Ticket.Status.PAID),
            (self.counter, self.issued, Ticket.Status.CHECKED),
            (self.context["controller"], self.issued, Ticket.Status.CHECKED),
        ]
        for user, ticket, status in cases:
            self.client.force_authenticate(user)
            response = self.client.post(f"/api/v1/tickets/{ticket.pk}/transition/?trip={self.trip.pk}", {"status": status}, format="json")
            self.assertEqual(response.status_code, 403, (user.role, status))
        self.held.refresh_from_db()
        self.issued.refresh_from_db()
        self.assertEqual((self.held.status, self.issued.status), (Ticket.Status.HELD, Ticket.Status.ISSUED))
        self.assertFalse(TicketStatusHistory.objects.filter(manual=True).exists())

    def test_admin_change_is_logged_and_readable_only_by_admin(self):
        admin = self.context["admin"]
        self.client.force_authenticate(admin)
        response = self.client.post(
            f"/api/v1/tickets/{self.held.pk}/transition/", {"status": Ticket.Status.CANCELLED, "note": "Doublon"}, format="json"
        )
        self.assertEqual(response.status_code, 200, response.data)
        entry = TicketStatusHistory.objects.get(manual=True)
        self.assertEqual(
            (entry.ticket_id, entry.from_status, entry.to_status, entry.changed_by_id, entry.note),
            (self.held.pk, Ticket.Status.HELD, Ticket.Status.CANCELLED, admin.pk, "Doublon"),
        )
        self.assertIsNotNone(entry.changed_at)

        log = self.client.get("/api/v1/ticket-manual-changes/")
        self.assertEqual(log.status_code, 200)
        rows = log.data["results"] if isinstance(log.data, dict) else log.data
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["reference"], self.held.reference)
        self.assertEqual((rows[0]["from_status"], rows[0]["to_status"]), ("HELD", "CANCELLED"))
        self.assertEqual(rows[0]["changed_by_name"], admin.get_full_name() or admin.username)
        # Lecture seule, même pour l'admin.
        self.assertEqual(self.client.post("/api/v1/ticket-manual-changes/", {}, format="json").status_code, 405)
        self.assertEqual(self.client.delete(f"/api/v1/ticket-manual-changes/{entry.pk}/").status_code, 404)
        for user in (self.context["client"], self.counter, self.context["controller"]):
            self.client.force_authenticate(user)
            self.assertEqual(self.client.get("/api/v1/ticket-manual-changes/").status_code, 403, user.role)

    def test_payments_and_scans_are_not_counted_as_manual_changes(self):
        self.scan(self.context["controller"])
        self.assertTrue(TicketStatusHistory.objects.filter(ticket=self.issued, to_status=Ticket.Status.CHECKED).exists())
        self.assertFalse(TicketStatusHistory.objects.filter(manual=True).exists())
