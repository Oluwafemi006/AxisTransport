import hashlib
import hmac
import json
import threading
import time
from decimal import Decimal
from unittest import mock, skipUnless

from django.core.exceptions import ValidationError
from django.db import IntegrityError, connection, transaction
from django.test import TransactionTestCase, override_settings
from rest_framework.test import APIClient, APITestCase

from apps.core import payments
from apps.core.models import Booking, PaymentMethod, PaymentReceipt, Ticket, Transaction, User
from apps.core.services import pay_and_issue_booking, reserve_booking

from .factories import build_operational_context

WEBHOOK_SECRET = "whsec_test_secret"
WEBHOOK_URL = "/api/v1/client/webhooks/fedapay/"
FETCH = "apps.core.payments._fedapay_fetch_transaction"
FEDAPAY_SETTINGS = {"FEDAPAY_SECRET_KEY": "sk_sandbox_test", "FEDAPAY_WEBHOOK_SECRET": WEBHOOK_SECRET}


def make_booking(context, *, customer=None, seats=2, offset=0):
    trip_seats = list(context["trip"].seats.order_by("number")[offset : offset + seats])
    booking, _ = reserve_booking(
        trip=context["trip"],
        customer=customer,
        passengers=[{"full_name": f"Voyageur {index}", "seat": seat} for index, seat in enumerate(trip_seats)],
    )
    return booking


def fedapay_transaction(booking, *, transaction_id="1001", amount=None, status="approved", metadata=None, currency="XOF"):
    return {
        "id": int(transaction_id),
        "status": status,
        "amount": int(booking.amount if amount is None else amount),
        "currency": {"iso": currency} if currency else None,
        "custom_metadata": {"booking_id": booking.pk} if metadata is None else metadata,
    }


def signed_headers(body, *, secret=WEBHOOK_SECRET, timestamp=None):
    timestamp = int(time.time()) if timestamp is None else timestamp
    signature = hmac.new(secret.encode(), f"{timestamp}.".encode() + body, hashlib.sha256).hexdigest()
    return {"HTTP_X_FEDAPAY_SIGNATURE": f"t={timestamp},s={signature}"}


def webhook_body(transaction_id="1001", status="approved"):
    return json.dumps(
        {"name": f"transaction.{status}", "entity": {"id": int(transaction_id), "status": status}}
    ).encode()


@override_settings(**FEDAPAY_SETTINGS)
class PaymentVerificationTests(APITestCase):
    def setUp(self):
        self.context = build_operational_context()
        self.fedapay = PaymentMethod.objects.create(code="FEDAPAY", label="FedaPay", active=True)
        self.booking = make_booking(self.context, customer=self.context["client"])
        self.client.force_authenticate(self.context["client"])
        self.pay_url = f"/api/v1/client/bookings/{self.booking.pk}/pay/"

    def pay(self, **payload):
        return self.client.post(self.pay_url, {"payment_method": self.fedapay.pk, **payload}, format="json")

    def assert_nothing_issued(self, booking=None):
        booking = booking or self.booking
        booking.refresh_from_db()
        self.assertEqual(booking.status, Booking.Status.HELD)
        self.assertFalse(booking.tickets.exclude(status=Ticket.Status.HELD).exists())
        self.assertEqual(Transaction.objects.count(), 0)
        self.assertEqual(PaymentReceipt.objects.count(), 0)

    def test_payment_without_reference_is_refused(self):
        with mock.patch(FETCH) as fetch:
            response = self.pay()
        self.assertEqual(response.status_code, 400, response.data)
        fetch.assert_not_called()
        self.assert_nothing_issued()

    def test_verified_payment_issues_tickets(self):
        with mock.patch(FETCH, return_value=fedapay_transaction(self.booking)):
            response = self.pay(external_reference="1001")
        self.assertEqual(response.status_code, 200, response.data)
        self.booking.refresh_from_db()
        self.assertEqual(self.booking.status, Booking.Status.CONFIRMED)
        self.assertEqual(self.booking.tickets.filter(status=Ticket.Status.ISSUED).count(), 2)
        receipt = PaymentReceipt.objects.get()
        self.assertEqual((receipt.provider, receipt.external_id, receipt.booking_id), ("FEDAPAY", "1001", self.booking.pk))
        self.assertEqual(receipt.amount, Decimal("2000.00"))

    def test_insufficient_amount_is_refused(self):
        with mock.patch(FETCH, return_value=fedapay_transaction(self.booking, amount=1999)):
            response = self.pay(external_reference="1001")
        self.assertEqual(response.status_code, 400, response.data)
        self.assert_nothing_issued()

    def test_excess_amount_is_refused(self):
        with mock.patch(FETCH, return_value=fedapay_transaction(self.booking, amount=2001)):
            response = self.pay(external_reference="1001")
        self.assertEqual(response.status_code, 400, response.data)
        self.assert_nothing_issued()

    def test_unapproved_transaction_is_refused(self):
        with mock.patch(FETCH, return_value=fedapay_transaction(self.booking, status="pending")):
            response = self.pay(external_reference="1001")
        self.assertEqual(response.status_code, 400, response.data)
        # Le statut exact du prestataire est transmis au client (en attente / refusé).
        self.assertEqual(response.data["payment_status"], "pending")
        self.assert_nothing_issued()

    def test_transaction_created_for_another_booking_is_refused(self):
        other = make_booking(self.context, customer=self.context["client"], seats=2, offset=2)
        with mock.patch(FETCH, return_value=fedapay_transaction(other)):
            response = self.pay(external_reference="1001")
        self.assertEqual(response.status_code, 400, response.data)
        self.assert_nothing_issued()

    def test_transaction_without_booking_metadata_is_refused(self):
        with mock.patch(FETCH, return_value=fedapay_transaction(self.booking, metadata={})):
            response = self.pay(external_reference="1001")
        self.assertEqual(response.status_code, 400, response.data)
        self.assert_nothing_issued()

    def test_reused_transaction_is_refused_for_another_booking(self):
        with mock.patch(FETCH, return_value=fedapay_transaction(self.booking)):
            self.assertEqual(self.pay(external_reference="1001").status_code, 200)
        other = make_booking(self.context, customer=self.context["client"], seats=2, offset=2)
        # Même si le prestataire renvoyait des métadonnées favorables, la transaction est déjà consommée.
        with mock.patch(FETCH, return_value=fedapay_transaction(other)):
            response = self.client.post(
                f"/api/v1/client/bookings/{other.pk}/pay/",
                {"payment_method": self.fedapay.pk, "external_reference": "1001"},
                format="json",
            )
        self.assertEqual(response.status_code, 400, response.data)
        other.refresh_from_db()
        self.assertEqual(other.status, Booking.Status.HELD)
        self.assertEqual(PaymentReceipt.objects.count(), 1)

    def test_database_rejects_duplicate_provider_transaction(self):
        other = make_booking(self.context, customer=self.context["client"], seats=2, offset=2)
        PaymentReceipt.objects.create(
            provider="FEDAPAY", external_id="1001", booking=self.booking, amount=2000, source="CLIENT"
        )
        with self.assertRaises(IntegrityError), transaction.atomic():
            PaymentReceipt.objects.create(
                provider="FEDAPAY", external_id="1001", booking=other, amount=2000, source="CLIENT"
            )

    def test_same_confirmation_twice_issues_once(self):
        with mock.patch(FETCH, return_value=fedapay_transaction(self.booking)):
            first = self.pay(external_reference="1001")
            second = self.pay(external_reference="1001")
        self.assertEqual((first.status_code, second.status_code), (200, 200))
        self.assertEqual(Transaction.objects.count(), 2)
        self.assertEqual(PaymentReceipt.objects.count(), 1)

    @override_settings(FEDAPAY_SECRET_KEY="")
    def test_missing_secret_key_refuses_payment(self):
        for reference in ("1001", "test_123"):
            with mock.patch(FETCH) as fetch:
                response = self.pay(external_reference=reference)
            self.assertEqual(response.status_code, 400, response.data)
            fetch.assert_not_called()
        self.assert_nothing_issued()

    @override_settings(FEDAPAY_SECRET_KEY="", DEBUG=True)
    def test_missing_secret_key_refuses_payment_even_in_debug(self):
        response = self.pay(external_reference="test_123")
        self.assertEqual(response.status_code, 400, response.data)
        self.assert_nothing_issued()

    def test_manual_method_cannot_be_used_by_client(self):
        response = self.client.post(
            self.pay_url, {"payment_method": self.context["payment_method"].pk}, format="json"
        )
        self.assertEqual(response.status_code, 400, response.data)
        self.assert_nothing_issued()

    def test_kkiapay_never_issues(self):
        kkiapay = PaymentMethod.objects.create(code="KKIAPAY", label="KKiaPay", active=True)
        response = self.client.post(
            self.pay_url, {"payment_method": kkiapay.pk, "external_reference": "any-id"}, format="json"
        )
        self.assertEqual(response.status_code, 400, response.data)
        webhook = APIClient().post(
            "/api/v1/client/webhooks/kkiapay/",
            {"transaction_id": "any-id", "booking_id": self.booking.pk},
            format="json",
        )
        self.assertEqual(webhook.status_code, 503)
        self.assert_nothing_issued()

    def test_issuing_service_requires_a_receipt(self):
        with self.assertRaises(ValidationError):
            pay_and_issue_booking(self.booking, payment_method=self.fedapay, receipt=None)
        self.assert_nothing_issued()


class SimulatedPaymentTests(APITestCase):
    def setUp(self):
        self.context = build_operational_context()
        self.simulation = PaymentMethod.objects.create(code="SIMULATION", label="Paiement simulé", active=True)
        self.booking = make_booking(self.context, customer=self.context["client"])
        self.client.force_authenticate(self.context["client"])

    def pay(self):
        return self.client.post(
            f"/api/v1/client/bookings/{self.booking.pk}/pay/",
            {"payment_method": self.simulation.pk, "external_reference": "SIM-1"},
            format="json",
        )

    @override_settings(DEBUG=False, AXIS_PAYMENT_SIMULATION=True)
    def test_simulation_refused_outside_debug(self):
        self.assertEqual(self.pay().status_code, 400)
        self.assertEqual(PaymentReceipt.objects.count(), 0)

    @override_settings(DEBUG=True, AXIS_PAYMENT_SIMULATION=False)
    def test_simulation_refused_when_not_enabled(self):
        self.assertEqual(self.pay().status_code, 400)
        self.assertEqual(PaymentReceipt.objects.count(), 0)

    @override_settings(DEBUG=True, AXIS_PAYMENT_SIMULATION=True)
    def test_simulation_accepted_in_debug_when_enabled(self):
        response = self.pay()
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(self.booking.tickets.filter(status=Ticket.Status.ISSUED).count(), 2)


@override_settings(**FEDAPAY_SETTINGS)
class FedaPayWebhookTests(APITestCase):
    def setUp(self):
        self.context = build_operational_context()
        self.fedapay = PaymentMethod.objects.create(code="FEDAPAY", label="FedaPay", active=True)
        self.booking = make_booking(self.context, customer=self.context["client"])

    def post(self, body, **headers):
        return self.client.post(WEBHOOK_URL, data=body, content_type="application/json", **headers)

    def assert_held(self):
        self.booking.refresh_from_db()
        self.assertEqual(self.booking.status, Booking.Status.HELD)
        self.assertEqual(PaymentReceipt.objects.count(), 0)

    def test_missing_signature_is_rejected(self):
        with mock.patch(FETCH, return_value=fedapay_transaction(self.booking)) as fetch:
            response = self.post(webhook_body())
        self.assertEqual(response.status_code, 400)
        fetch.assert_not_called()
        self.assert_held()

    def test_invalid_signature_is_rejected(self):
        body = webhook_body()
        with mock.patch(FETCH, return_value=fedapay_transaction(self.booking)) as fetch:
            response = self.post(body, **signed_headers(body, secret="wrong-secret"))
        self.assertEqual(response.status_code, 400)
        fetch.assert_not_called()
        self.assert_held()

    def test_signature_of_another_body_is_rejected(self):
        with mock.patch(FETCH, return_value=fedapay_transaction(self.booking)):
            response = self.post(webhook_body("1001"), **signed_headers(webhook_body("9999")))
        self.assertEqual(response.status_code, 400)
        self.assert_held()

    def test_legacy_unsigned_format_is_rejected(self):
        body = webhook_body()
        digest = hmac.new(WEBHOOK_SECRET.encode(), body, hashlib.sha256).hexdigest()
        with mock.patch(FETCH, return_value=fedapay_transaction(self.booking)):
            response = self.post(body, HTTP_X_FEDAPAY_SIGNATURE=digest)
        self.assertEqual(response.status_code, 400)
        self.assert_held()

    def test_stale_timestamp_is_rejected(self):
        body = webhook_body()
        with mock.patch(FETCH, return_value=fedapay_transaction(self.booking)):
            response = self.post(body, **signed_headers(body, timestamp=int(time.time()) - 301))
        self.assertEqual(response.status_code, 400)
        self.assert_held()

    @override_settings(FEDAPAY_WEBHOOK_TOLERANCE_SECONDS=3600)
    def test_tolerance_is_configurable(self):
        body = webhook_body()
        with mock.patch(FETCH, return_value=fedapay_transaction(self.booking)):
            response = self.post(body, **signed_headers(body, timestamp=int(time.time()) - 301))
        self.assertEqual(response.status_code, 200, response.data)

    @override_settings(FEDAPAY_WEBHOOK_SECRET="")
    def test_unconfigured_secret_is_rejected(self):
        body = webhook_body()
        with mock.patch(FETCH, return_value=fedapay_transaction(self.booking)):
            response = self.post(body, **signed_headers(body, secret=""))
        self.assertEqual(response.status_code, 503)
        self.assert_held()

    def test_valid_webhook_issues_tickets(self):
        body = webhook_body()
        with mock.patch(FETCH, return_value=fedapay_transaction(self.booking)):
            response = self.post(body, **signed_headers(body))
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data["tickets_issued"], 2)
        self.booking.refresh_from_db()
        self.assertEqual(self.booking.status, Booking.Status.CONFIRMED)
        self.assertEqual(PaymentReceipt.objects.get().source, PaymentReceipt.Source.WEBHOOK)

    def test_signed_webhook_with_wrong_amount_is_refused(self):
        body = webhook_body()
        with mock.patch(FETCH, return_value=fedapay_transaction(self.booking, amount=100)):
            response = self.post(body, **signed_headers(body))
        self.assertEqual(response.status_code, 400)
        self.assert_held()

    def test_signed_webhook_not_approved_by_api_is_refused(self):
        body = webhook_body()
        with mock.patch(FETCH, return_value=fedapay_transaction(self.booking, status="pending")):
            response = self.post(body, **signed_headers(body))
        self.assertEqual(response.status_code, 400)
        self.assert_held()

    def test_non_approved_event_is_ignored(self):
        body = webhook_body(status="declined")
        with mock.patch(FETCH) as fetch:
            response = self.post(body, **signed_headers(body))
        self.assertEqual(response.status_code, 200)
        fetch.assert_not_called()
        self.assert_held()

    def _assert_single_issue(self):
        self.assertEqual(Ticket.objects.filter(booking=self.booking).count(), 2)
        self.assertEqual(Ticket.objects.filter(booking=self.booking, status=Ticket.Status.ISSUED).count(), 2)
        self.assertEqual(Transaction.objects.count(), 2)
        self.assertEqual(PaymentReceipt.objects.count(), 1)

    def test_client_then_webhook_issues_once(self):
        body = webhook_body()
        client = APIClient()
        client.force_authenticate(self.context["client"])
        with mock.patch(FETCH, return_value=fedapay_transaction(self.booking)):
            paid = client.post(
                f"/api/v1/client/bookings/{self.booking.pk}/pay/",
                {"payment_method": self.fedapay.pk, "external_reference": "1001"},
                format="json",
            )
            webhook = self.post(body, **signed_headers(body))
        self.assertEqual(paid.status_code, 200, paid.data)
        self.assertEqual(webhook.status_code, 200, webhook.data)
        self.assertTrue(webhook.data["already_processed"])
        self._assert_single_issue()

    def test_webhook_then_client_issues_once(self):
        body = webhook_body()
        client = APIClient()
        client.force_authenticate(self.context["client"])
        with mock.patch(FETCH, return_value=fedapay_transaction(self.booking)):
            webhook = self.post(body, **signed_headers(body))
            paid = client.post(
                f"/api/v1/client/bookings/{self.booking.pk}/pay/",
                {"payment_method": self.fedapay.pk, "external_reference": "1001"},
                format="json",
            )
        self.assertEqual(webhook.status_code, 200, webhook.data)
        self.assertFalse(webhook.data["already_processed"])
        self.assertEqual(paid.status_code, 200, paid.data)
        self.assertEqual(paid.data["booking"]["status"], Booking.Status.CONFIRMED)
        self._assert_single_issue()


@skipUnless(connection.vendor == "postgresql", "Verrous de ligne réels : PostgreSQL uniquement.")
@override_settings(**FEDAPAY_SETTINGS)
class ConcurrentSettlementTests(TransactionTestCase):
    """La confirmation client et le webhook arrivent en même temps : une seule émission."""

    def setUp(self):
        self.context = build_operational_context()
        self.fedapay = PaymentMethod.objects.create(code="FEDAPAY", label="FedaPay", active=True)
        self.booking = make_booking(self.context, customer=self.context["client"])

    def test_simultaneous_client_and_webhook_issue_once(self):
        barrier = threading.Barrier(2)
        outcomes = []

        def run(kind):
            try:
                barrier.wait(timeout=10)
                if kind == "client":
                    settlement = payments.settle_booking_payment(
                        Booking.objects.get(pk=self.booking.pk),
                        payment_method=self.fedapay,
                        external_reference="1001",
                        actor=User.objects.get(pk=self.context["client"].pk),
                    )
                else:
                    settlement = payments.settle_from_fedapay_webhook("1001")
                outcomes.append((kind, settlement.created))
            except Exception as exc:  # noqa: BLE001 - le test échoue plus bas si un fil a levé
                outcomes.append((kind, exc))
            finally:
                connection.close()

        with mock.patch(FETCH, return_value=fedapay_transaction(self.booking)):
            threads = [threading.Thread(target=run, args=(kind,)) for kind in ("client", "webhook")]
            for thread in threads:
                thread.start()
            for thread in threads:
                thread.join(timeout=30)

        self.assertEqual(sorted(created for _, created in outcomes), [False, True], outcomes)
        self.assertEqual(Ticket.objects.filter(booking=self.booking, status=Ticket.Status.ISSUED).count(), 2)
        self.assertEqual(Ticket.objects.filter(booking=self.booking).count(), 2)
        self.assertEqual(Transaction.objects.count(), 2)
        self.assertEqual(PaymentReceipt.objects.count(), 1)
