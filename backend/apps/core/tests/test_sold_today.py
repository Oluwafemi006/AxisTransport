"""Billets vendus aujourd'hui : lecture seule, l'agent voit ses ventes, l'admin toutes, le client rien."""
from decimal import Decimal

from django.test import override_settings
from rest_framework.test import APITestCase

from apps.core.models import PaymentMethod, User

from .factories import build_operational_context

SALES = "/api/v1/staff/sales/"


@override_settings(PUBLIC_WEB_URL="https://site.test")
class SoldTodayTests(APITestCase):
    def setUp(self):
        self.context = build_operational_context()
        self.trip = self.context["trip"]
        self.counter = User.objects.create_user(username="guichet-test", password="TEST-pass-123", role=User.Role.COUNTER)
        self.cash = PaymentMethod.objects.create(code="especes", label="Espèces", active=True)
        self.seats = list(self.trip.seats.order_by("number"))

    def sell(self, user, key, seat):
        self.client.force_authenticate(user)
        response = self.client.post(f"{SALES}sell/", {
            "idempotency_key": key, "trip": self.trip.pk, "seat": seat.pk, "passenger_name": "Passager TEST",
            "passenger_phone": "90000000", "payment_method": self.cash.pk,
        }, format="json")
        self.assertIn(response.status_code, {200, 201}, response.content)

    def test_each_agent_sees_own_sales_and_admin_sees_all(self):
        self.sell(self.counter, "vente-test-0001", self.seats[0])
        self.sell(self.context["controller"], "vente-test-0002", self.seats[1])

        self.client.force_authenticate(self.counter)
        rows = self.client.get(f"{SALES}today/").json()
        self.assertEqual(len(rows), 1)
        row = rows[0]
        self.assertEqual(row["passenger_phone"], "90000000")
        self.assertTrue(row["public_url"].startswith("https://site.test/t/"))
        self.assertEqual(row["amount_fcfa"], int(Decimal(row["amount_fcfa"])))

        self.client.force_authenticate(self.context["admin"])
        self.assertEqual(len(self.client.get(f"{SALES}today/").json()), 2)

    def test_read_only_and_refused_to_clients(self):
        self.client.force_authenticate(self.counter)
        self.assertEqual(self.client.post(f"{SALES}today/", {}, format="json").status_code, 405)
        self.client.force_authenticate(self.context["client"])
        self.assertEqual(self.client.get(f"{SALES}today/").status_code, 403)
