"""Clôture de caisse : période du service, montant attendu (espèces de l'agent), corrections, pas de doublon."""
from decimal import Decimal

from rest_framework.test import APITestCase

from apps.core.models import Booking, CashHandover, PaymentMethod, Transaction, User

from .factories import build_operational_context
from .test_payment_security import make_booking

URL = "/api/v1/cash-handovers/"


class CashClosingTests(APITestCase):
    def setUp(self):
        self.context = build_operational_context()
        self.agent = User.objects.create_user(username="guichet-caisse-test", password="TEST-x", role=User.Role.COUNTER)
        self.cash = PaymentMethod.objects.create(code="especes-test", label="Espèces TEST", active=True)
        self.momo = PaymentMethod.objects.create(code="fedapay", label="Mobile Money TEST", active=True)
        self.client.force_authenticate(self.context["admin"])

    def sale(self, amount, method=None, offset=0):
        booking = make_booking(self.context, seats=1, offset=offset)
        Booking.objects.filter(pk=booking.pk).update(sold_by=self.agent)
        ticket = booking.tickets.get()
        Transaction.objects.create(payment_method=method or self.cash, amount=Decimal(amount), status=Transaction.Status.SUCCEEDED, ticket=ticket)

    def close(self, declared, agent=None):
        return self.client.post(URL, {"agent": (agent or self.agent).pk, "declared_fcfa": declared}, format="json")

    def test_expected_counts_only_this_agent_cash(self):
        self.sale(3000)
        self.sale(5000, method=self.momo, offset=1)
        response = self.close(2500)
        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual((response.data["expected_fcfa"], response.data["declared_fcfa"], response.data["difference_fcfa"]), (3000, 2500, -500))

    def test_next_closure_starts_where_the_previous_ended(self):
        self.sale(3000)
        first = self.close(3000).data
        self.sale(1000, offset=1)
        second = self.close(1000).data
        self.assertEqual(second["period_start"], first["period_end"])
        self.assertEqual(second["expected_fcfa"], 1000)

    def test_same_period_cannot_be_closed_twice(self):
        self.sale(3000)
        row = CashHandover.objects.get(pk=self.close(3000).data["id"])
        with self.assertRaises(Exception):
            CashHandover.objects.create(agent=self.agent, period_start=row.period_start, period_end=row.period_end,
                                        expected_fcfa=0, declared_fcfa=0, difference_fcfa=0, received_by=self.context["admin"])

    def test_correction_adds_a_row_and_keeps_the_original(self):
        self.sale(3000)
        original = self.close(2000).data
        self.assertEqual(self.client.post(f"{URL}{original['id']}/correct/", {"declared_fcfa": 3000}, format="json").status_code, 400)
        corrected = self.client.post(f"{URL}{original['id']}/correct/", {"declared_fcfa": 3000, "note": "Billet de 1000 oublié TEST"}, format="json")
        self.assertEqual(corrected.status_code, 201, corrected.data)
        self.assertEqual((corrected.data["corrects"], corrected.data["difference_fcfa"]), (original["id"], 0))
        self.assertEqual(CashHandover.objects.get(pk=original["id"]).declared_fcfa, 2000)
        self.assertIn(self.client.patch(f"{URL}{original['id']}/", {"declared_fcfa": 1}, format="json").status_code, (404, 405))
        self.assertIn(self.client.delete(f"{URL}{original['id']}/").status_code, (404, 405))

    def test_agents_cannot_see_or_record_closures(self):
        self.sale(3000)
        for user in (self.agent, self.context["controller"], self.context["client"]):
            self.client.force_authenticate(user)
            self.assertEqual(self.client.get(URL).status_code, 403)
            self.assertEqual(self.close(3000).status_code, 403)

    def test_only_counter_or_controller_can_be_closed(self):
        self.assertEqual(self.close(0, agent=self.context["client"]).status_code, 400)
        self.assertEqual(self.close("TEST").status_code, 400)
