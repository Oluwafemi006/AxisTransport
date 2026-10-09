from rest_framework.test import APITestCase

from apps.core.models import PaymentIncident, User

from .factories import build_operational_context

URL = "/api/v1/payment-incidents/"


class PaymentIncidentApiTests(APITestCase):
    """Liste des incidents de paiement du portail admin : ADMIN uniquement, lecture seule sauf « traité »."""

    def setUp(self):
        self.context = build_operational_context()
        self.incident = PaymentIncident.objects.create(
            source=PaymentIncident.Source.WEBHOOK, provider="FEDAPAY", event="transaction.approved",
            external_id="1001", amount=7500, currency="XOF", amount_verified=True,
            reason="Aucune réservation rattachée à cette transaction.",
        )
        self.counter = User.objects.create_user(username="guichet", password="secret", role=User.Role.COUNTER)

    def rows(self, response):
        return response.json() if isinstance(response.json(), list) else response.json()["results"]

    def test_admin_lists_incidents(self):
        self.client.force_authenticate(self.context["admin"])
        (row,) = self.rows(self.client.get(URL))
        self.assertEqual((row["external_id"], row["reason"], row["handled"], row["booking_reference"]), ("1001", self.incident.reason, False, ""))

    def test_other_roles_and_anonymous_are_refused(self):
        self.assertEqual(self.client.get(URL).status_code, 401)
        for user in (self.counter, self.context["controller"], self.context["client"]):
            self.client.force_authenticate(user)
            self.assertEqual(self.client.get(URL).status_code, 403, user.role)
            self.assertEqual(self.client.patch(f"{URL}{self.incident.pk}/", {"handled": True}, format="json").status_code, 403)

    def test_admin_can_only_tick_handled(self):
        self.client.force_authenticate(self.context["admin"])
        response = self.client.patch(
            f"{URL}{self.incident.pk}/", {"handled": True, "amount": "1", "reason": "modifié", "external_id": "9"}, format="json"
        )
        self.assertEqual(response.status_code, 200, response.data)
        self.incident.refresh_from_db()
        self.assertTrue(self.incident.handled)
        self.assertEqual((self.incident.amount, self.incident.reason, self.incident.external_id), (7500, "Aucune réservation rattachée à cette transaction.", "1001"))

    def test_incidents_cannot_be_created_or_deleted(self):
        self.client.force_authenticate(self.context["admin"])
        self.assertEqual(self.client.post(URL, {"reason": "x"}, format="json").status_code, 405)
        self.assertEqual(self.client.delete(f"{URL}{self.incident.pk}/").status_code, 405)
        self.assertEqual(PaymentIncident.objects.count(), 1)
