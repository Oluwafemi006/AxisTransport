"""Vente Mobile Money par le personnel : retour de FedaPay vers l'espace d'origine (liste fixe), ventes en attente."""
from decimal import Decimal
from unittest import mock

from django.core.exceptions import ValidationError
from django.test import SimpleTestCase, override_settings
from rest_framework.test import APITestCase

from apps.core import payments
from apps.core.models import PaymentAttempt, PaymentMethod, User

from .factories import build_operational_context
from .test_payment_security import FEDAPAY_SETTINGS

SALES = "/api/v1/staff/sales/"
CREATE = "apps.core.payments._fedapay_create_transaction"
RETURN = "https://site.exemple.test/paiement/retour"


@override_settings(FEDAPAY_CALLBACK_URL=RETURN)
class CallbackUrlTests(SimpleTestCase):
    def test_client_keeps_the_single_return_address(self):
        self.assertEqual(payments.checkout_callback_url(), RETURN)
        self.assertEqual(payments.checkout_callback_url(""), RETURN)

    def test_each_staff_space_has_its_own_page(self):
        for space in ("guichet", "controleur", "admin"):
            self.assertEqual(payments.checkout_callback_url(space), f"{RETURN}/{space}")

    def test_any_other_value_is_refused_no_open_redirect(self):
        for value in ("https://pirate.exemple.test", "../admin", "guichet/../..", "GUICHET", "client", "//x"):
            with self.subTest(value=value), self.assertRaises(ValidationError):
                payments.checkout_callback_url(value)

    @override_settings(FEDAPAY_CALLBACK_URL="")
    def test_no_return_address_configured_stays_empty(self):
        self.assertEqual(payments.checkout_callback_url("guichet"), "")


@override_settings(**{**FEDAPAY_SETTINGS, "FEDAPAY_CALLBACK_URL": RETURN})
class StaffSaleReturnSpaceTests(APITestCase):
    def setUp(self):
        self.context = build_operational_context()
        self.trip = self.context["trip"]
        self.counter = User.objects.create_user(username="guichet-test", password="TEST-pass-123", role=User.Role.COUNTER)
        self.fedapay = PaymentMethod.objects.create(code="FEDAPAY", label="Mobile Money TEST", active=True, fee_percentage=Decimal("0"))
        self.seat = self.trip.seats.order_by("number").first()
        self.client.force_authenticate(self.counter)

    def sell(self, key="vente-test-0001", **extra):
        with mock.patch(CREATE, return_value={"id": 7001, "payment_url": "https://paiement.exemple.test/TEST"}) as create:
            response = self.client.post(f"{SALES}sell/", {
                "idempotency_key": key, "trip": self.trip.pk, "seat": self.seat.pk, "passenger_name": "Passager TEST",
                "passenger_phone": "0100000009", "payment_method": self.fedapay.pk, **extra,
            }, format="json")
        return response, create

    def test_sale_from_counter_returns_to_counter_page(self):
        response, create = self.sell(espace="guichet")
        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(create.call_args.args[0]["callback_url"], f"{RETURN}/guichet")

    def test_sale_without_space_keeps_client_address(self):
        response, create = self.sell()
        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(create.call_args.args[0]["callback_url"], RETURN)

    def test_unknown_space_is_refused_before_anything_is_reserved(self):
        response, create = self.sell(espace="https://pirate.exemple.test")
        self.assertEqual(response.status_code, 400)
        create.assert_not_called()
        self.assertFalse(self.trip.bookings.exists())

    def test_pending_lists_own_unpaid_sale_with_its_transaction(self):
        response, _ = self.sell(espace="guichet")
        booking_id = response.data["booking"]["id"]
        pending = self.client.get(f"{SALES}pending/")
        self.assertEqual(pending.status_code, 200)
        self.assertEqual([row["booking"]["id"] for row in pending.data], [booking_id])
        self.assertEqual(pending.data[0]["transaction_id"], "7001")
        self.assertEqual(pending.data[0]["payment_method"], self.fedapay.pk)
        # Un autre agent ne voit pas cette vente.
        other = User.objects.create_user(username="guichet-test-2", password="TEST-pass-123", role=User.Role.COUNTER)
        self.client.force_authenticate(other)
        self.assertEqual(self.client.get(f"{SALES}pending/").data, [])

    def test_paid_or_failed_attempt_is_not_pending(self):
        response, _ = self.sell(espace="guichet")
        PaymentAttempt.objects.update(outcome=PaymentAttempt.Outcome.REFUSED)
        self.assertEqual(self.client.get(f"{SALES}pending/").data, [])
        self.assertEqual(response.status_code, 201)
