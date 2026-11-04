import json
from datetime import timedelta
from decimal import Decimal
from io import StringIO
from unittest import mock

from django.core.management import call_command
from django.db import OperationalError
from django.test import override_settings
from django.utils import timezone
from rest_framework.test import APITestCase

from apps.core import payments
from apps.core.models import Booking, PaymentAttempt, PaymentIncident, PaymentMethod, PaymentReceipt, Ticket

from .factories import build_operational_context
from .test_payment_security import (
    FEDAPAY_SETTINGS,
    FETCH,
    WEBHOOK_URL,
    fedapay_transaction,
    make_booking,
    signed_headers,
    webhook_body,
)

CREATE = "apps.core.payments._fedapay_create_transaction"


@override_settings(**FEDAPAY_SETTINGS)
class ReconciliationBase(APITestCase):
    def setUp(self):
        self.context = build_operational_context()
        self.fedapay = PaymentMethod.objects.create(code="FEDAPAY", label="FedaPay", active=True)
        self.booking = make_booking(self.context, customer=self.context["client"])

    def start_checkout(self, booking=None, transaction_id="1001"):
        """Le client ouvre la page de paiement : la transaction créée chez FedaPay est enregistrée."""
        booking = booking or self.booking
        created = {"id": int(transaction_id), "payment_url": "https://paiement.exemple.test/x"}
        with mock.patch(CREATE, return_value=created):
            payments.create_checkout(booking, payment_method=self.fedapay)
        return PaymentAttempt.objects.get(external_id=transaction_id)

    def reconcile(self, fetched, **kwargs):
        with mock.patch(FETCH, return_value=fetched) as fetch:
            counts = payments.reconcile_pending_payments(**kwargs)
        return counts, fetch

    def issued(self, booking=None):
        return (booking or self.booking).tickets.filter(status=Ticket.Status.ISSUED).count()


class PaymentAttemptRecordingTests(ReconciliationBase):
    def test_checkout_records_the_created_transaction(self):
        attempt = self.start_checkout()
        self.assertEqual(attempt.booking, self.booking)
        self.assertEqual(attempt.outcome, PaymentAttempt.Outcome.PENDING)
        self.assertEqual(attempt.amount, payments.amount_due(self.booking, self.fedapay))
        self.assertEqual(self.issued(), 0)


class ReconciliationTests(ReconciliationBase):
    def test_missed_webhook_is_caught_up_and_tickets_are_issued(self):
        attempt = self.start_checkout()
        counts, _ = self.reconcile(fedapay_transaction(self.booking))
        self.assertEqual(counts["settled"], 1)
        self.assertEqual(self.issued(), 2)
        receipt = PaymentReceipt.objects.get()
        self.assertEqual(receipt.source, PaymentReceipt.Source.RECONCILIATION)
        attempt.refresh_from_db()
        self.assertEqual(attempt.outcome, PaymentAttempt.Outcome.SETTLED)

    def test_webhook_then_reconciliation_issues_no_duplicate(self):
        attempt = self.start_checkout()
        body = webhook_body()
        with mock.patch(FETCH, return_value=fedapay_transaction(self.booking)):
            self.assertEqual(self.client.post(WEBHOOK_URL, data=body, content_type="application/json", **signed_headers(body)).status_code, 200)
        self.assertEqual(self.issued(), 2)
        counts, fetch = self.reconcile(fedapay_transaction(self.booking))
        # Déjà réglée : aucun appel à FedaPay, aucun billet ni reçu de plus.
        fetch.assert_not_called()
        self.assertEqual(counts["settled"], 0)
        self.assertEqual(self.issued(), 2)
        self.assertEqual(PaymentReceipt.objects.count(), 1)
        self.assertEqual(Ticket.objects.filter(booking=self.booking).count(), 2)
        attempt.refresh_from_db()
        self.assertEqual(attempt.outcome, PaymentAttempt.Outcome.SETTLED)

    def test_reconciliation_then_webhook_issues_no_duplicate(self):
        self.start_checkout()
        self.reconcile(fedapay_transaction(self.booking))
        body = webhook_body()
        with mock.patch(FETCH, return_value=fedapay_transaction(self.booking)):
            response = self.client.post(WEBHOOK_URL, data=body, content_type="application/json", **signed_headers(body))
        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.data["already_processed"])
        self.assertEqual(PaymentReceipt.objects.count(), 1)
        self.assertEqual(Ticket.objects.filter(booking=self.booking).count(), 2)

    def test_running_twice_issues_once(self):
        self.start_checkout()
        self.reconcile(fedapay_transaction(self.booking))
        counts, fetch = self.reconcile(fedapay_transaction(self.booking))
        fetch.assert_not_called()
        self.assertEqual((counts["settled"], PaymentReceipt.objects.count(), self.issued()), (0, 1, 2))

    def test_declined_payment_issues_nothing_and_is_closed(self):
        attempt = self.start_checkout()
        counts, _ = self.reconcile(fedapay_transaction(self.booking, status="declined"))
        self.assertEqual(counts["refused"], 1)
        self.assertEqual(self.issued(), 0)
        self.assertEqual(PaymentReceipt.objects.count(), 0)
        attempt.refresh_from_db()
        self.assertEqual((attempt.outcome, attempt.provider_status), (PaymentAttempt.Outcome.REFUSED, "declined"))
        # Une transaction close n'est plus jamais interrogée.
        _, fetch = self.reconcile(fedapay_transaction(self.booking, status="declined"))
        fetch.assert_not_called()

    def test_abandoned_payment_stays_pending_then_stops_after_the_window(self):
        attempt = self.start_checkout()
        counts, _ = self.reconcile(fedapay_transaction(self.booking, status="pending"))
        self.assertEqual(counts["pending"], 1)
        attempt.refresh_from_db()
        self.assertEqual((attempt.outcome, attempt.checks), (PaymentAttempt.Outcome.PENDING, 1))
        # Passé la durée d'interrogation, on arrête sans appeler FedaPay.
        later = timezone.now() + timedelta(minutes=1441)
        counts, fetch = self.reconcile(fedapay_transaction(self.booking, status="pending"), now=later)
        fetch.assert_not_called()
        self.assertEqual(counts["abandoned"], 1)
        attempt.refresh_from_db()
        self.assertEqual(attempt.outcome, PaymentAttempt.Outcome.ABANDONED)
        self.assertEqual(self.issued(), 0)

    def test_late_payment_after_hold_expiry_is_refund_due_without_ticket(self):
        attempt = self.start_checkout()
        Booking.objects.filter(pk=self.booking.pk).update(reservation_expires_at=timezone.now() - timedelta(minutes=1))
        self.booking.tickets.update(reservation_expires_at=timezone.now() - timedelta(minutes=1))
        # Toutes les places du voyage ont été prises entre-temps : plus aucune place libre
        self.booking.trip.seats.update(status="PAID")
        counts, _ = self.reconcile(fedapay_transaction(self.booking))
        self.assertEqual(counts["refund_due"], 1)
        self.assertEqual(self.issued(), 0)
        receipt = PaymentReceipt.objects.get()
        self.assertTrue(receipt.refund_due)
        self.booking.refresh_from_db()
        self.assertEqual(self.booking.status, Booking.Status.REFUND_DUE)
        attempt.refresh_from_db()
        self.assertEqual(attempt.outcome, PaymentAttempt.Outcome.REFUND_DUE)

    def test_approved_payment_with_wrong_amount_becomes_an_incident(self):
        attempt = self.start_checkout()
        counts, _ = self.reconcile(fedapay_transaction(self.booking, amount=100))
        self.assertEqual(counts["anomalies"], 1)
        self.assertEqual(self.issued(), 0)
        incident = PaymentIncident.objects.get()
        self.assertEqual((incident.source, incident.amount, incident.booking), (PaymentIncident.Source.RECONCILIATION, Decimal("100"), self.booking))
        attempt.refresh_from_db()
        self.assertEqual(attempt.outcome, PaymentAttempt.Outcome.ANOMALY)

    def test_provider_outage_stops_the_run_and_keeps_the_attempt_pending(self):
        attempt = self.start_checkout()
        with mock.patch(FETCH, side_effect=payments.ProviderUnavailable("FedaPay momentanément indisponible (HTTP 429).")) as fetch:
            counts = payments.reconcile_pending_payments()
        self.assertEqual(fetch.call_count, 1)
        self.assertEqual(counts["settled"], 0)
        attempt.refresh_from_db()
        self.assertEqual(attempt.outcome, PaymentAttempt.Outcome.PENDING)

    @override_settings(AXIS_PAYMENT_RECONCILE_BATCH=2)
    def test_calls_per_run_are_capped(self):
        self.start_checkout(transaction_id="1001")
        second = make_booking(self.context, customer=self.context["client"], seats=1, offset=2)
        third = make_booking(self.context, customer=self.context["client"], seats=1, offset=3)
        self.start_checkout(second, "1002")
        self.start_checkout(third, "1003")
        counts, fetch = self.reconcile(fedapay_transaction(self.booking, status="pending"))
        self.assertEqual((counts["checked"], fetch.call_count), (2, 2))

    def test_checks_are_spaced_out_after_thirty_minutes(self):
        attempt = self.start_checkout()
        start = attempt.created_at
        pending = fedapay_transaction(self.booking, status="pending")
        self.reconcile(pending, now=start + timedelta(minutes=31))
        # 5 minutes plus tard : trop tôt (toutes les 10 minutes entre 30 min et 2 h).
        _, fetch = self.reconcile(pending, now=start + timedelta(minutes=36))
        fetch.assert_not_called()
        _, fetch = self.reconcile(pending, now=start + timedelta(minutes=42))
        self.assertEqual(fetch.call_count, 1)

    @override_settings(AXIS_PAYMENT_RECONCILE_ENABLED=False)
    def test_switch_off_does_nothing(self):
        self.start_checkout()
        _, fetch = self.reconcile(fedapay_transaction(self.booking))
        fetch.assert_not_called()
        self.assertEqual(self.issued(), 0)

    @override_settings(FEDAPAY_SECRET_KEY="")
    def test_does_not_run_without_fedapay_key(self):
        with override_settings(FEDAPAY_SECRET_KEY="sk_sandbox_test"):
            self.start_checkout()
        _, fetch = self.reconcile(fedapay_transaction(self.booking))
        fetch.assert_not_called()
        self.assertEqual(self.issued(), 0)

    def test_command_logs_each_catch_up(self):
        self.start_checkout()
        output = StringIO()
        with mock.patch(FETCH, return_value=fedapay_transaction(self.booking)), self.assertLogs("axis.payments", level="INFO") as logs:
            call_command("reconcile_payments", stdout=output)
        self.assertIn("1 billet(s) émis", output.getvalue())
        self.assertTrue(any("1001" in line and "confirmée" in line for line in logs.output))


class WebhookRefusalTests(ReconciliationBase):
    """Refus métier définitif → 200 et incident durable ; erreur passagère → 503 ; signature invalide → 400."""

    def post(self, body, **headers):
        return self.client.post(WEBHOOK_URL, data=body, content_type="application/json", **headers)

    def signed(self, body, fetched=None, side_effect=None):
        with mock.patch(FETCH, return_value=fetched, side_effect=side_effect):
            return self.post(body, **signed_headers(body))

    def assert_refused(self, response, reason):
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data["status"], "REFUSED")
        incident = PaymentIncident.objects.get()
        self.assertEqual(incident.source, PaymentIncident.Source.WEBHOOK)
        self.assertIn(reason, incident.reason)
        self.assertFalse(incident.handled)
        self.assertEqual(self.issued(), 0)
        return incident

    def test_payment_for_unknown_booking_is_recorded_with_its_amount(self):
        fetched = fedapay_transaction(self.booking, amount=7500, metadata={"booking_id": 999999})
        incident = self.assert_refused(self.signed(webhook_body(), fetched), "Aucune réservation rattachée")
        self.assertEqual((incident.event, incident.external_id, incident.amount, incident.currency), ("transaction.approved", "1001", Decimal("7500"), "XOF"))
        self.assertTrue(incident.amount_verified)
        self.assertIsNone(incident.booking)

    def test_payment_without_metadata_is_recorded(self):
        self.assert_refused(self.signed(webhook_body(), fedapay_transaction(self.booking, metadata={})), "Aucune réservation rattachée")

    def test_wrong_currency_is_recorded(self):
        self.assert_refused(self.signed(webhook_body(), fedapay_transaction(self.booking, currency="EUR")), "francs CFA")

    def test_second_payment_on_an_already_paid_booking_is_recorded(self):
        self.signed(webhook_body("1001"), fedapay_transaction(self.booking, transaction_id="1001"))
        self.assertEqual(self.issued(), 2)
        response = self.signed(webhook_body("1002"), fedapay_transaction(self.booking, transaction_id="1002"))
        self.assertEqual(response.status_code, 200, response.data)
        incident = PaymentIncident.objects.get()
        self.assertEqual((incident.external_id, incident.booking), ("1002", self.booking))
        self.assertEqual(PaymentReceipt.objects.count(), 1)
        self.assertEqual(Ticket.objects.filter(booking=self.booking).count(), 2)

    def test_inactive_fedapay_method_is_recorded(self):
        PaymentMethod.objects.filter(pk=self.fedapay.pk).update(active=False)
        self.assert_refused(self.signed(webhook_body(), fedapay_transaction(self.booking)), "n'est pas actif")

    def test_signed_message_without_transaction_id_is_recorded(self):
        body = json.dumps({"name": "transaction.approved", "entity": {"status": "approved", "amount": 1018}}).encode()
        incident = self.assert_refused(self.post(body, **signed_headers(body)), "Identifiant de transaction manquant")
        self.assertEqual((incident.amount, incident.amount_verified), (Decimal("1018"), False))

    def test_signed_unreadable_body_is_recorded(self):
        body = b"pas du json"
        self.assert_refused(self.post(body, **signed_headers(body)), "illisible")

    def test_provider_outage_answers_503_so_fedapay_retries(self):
        response = self.signed(webhook_body(), side_effect=payments.ProviderUnavailable("Impossible de contacter FedaPay."))
        self.assertEqual(response.status_code, 503)
        self.assertEqual(PaymentIncident.objects.count(), 0)
        self.assertEqual(self.issued(), 0)

    def test_database_outage_answers_503_so_fedapay_retries(self):
        body = webhook_body()
        with mock.patch("apps.core.views.settle_from_fedapay_webhook", side_effect=OperationalError("base indisponible")):
            response = self.post(body, **signed_headers(body))
        self.assertEqual(response.status_code, 503)

    def test_refusal_that_cannot_be_recorded_answers_503(self):
        body = webhook_body()
        with mock.patch(FETCH, return_value=fedapay_transaction(self.booking, amount=100)), mock.patch(
            "apps.core.views.record_payment_incident", side_effect=OperationalError("base indisponible")
        ):
            response = self.post(body, **signed_headers(body))
        self.assertEqual(response.status_code, 503)

    def test_invalid_signature_still_answers_400_and_records_nothing(self):
        body = webhook_body()
        response = self.post(body, **signed_headers(body, secret="mauvais-secret"))
        self.assertEqual(response.status_code, 400)
        self.assertEqual(PaymentIncident.objects.count(), 0)

    def test_admin_can_see_incidents_in_django_admin(self):
        self.signed(webhook_body(), fedapay_transaction(self.booking, metadata={}))
        admin = self.context["admin"]
        admin.is_staff = admin.is_superuser = True
        admin.save()
        self.client.force_login(admin)
        page = self.client.get("/django-admin/core/paymentincident/")
        self.assertEqual(page.status_code, 200)
        self.assertContains(page, "Aucune réservation rattachée")
