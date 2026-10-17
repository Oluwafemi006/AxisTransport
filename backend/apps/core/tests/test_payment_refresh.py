from unittest import mock

from django.core.cache import cache
from django.test import override_settings
from rest_framework.settings import api_settings
from rest_framework.test import APITestCase

from apps.core import payments
from apps.core.models import Booking, PaymentAttempt, PaymentMethod, PaymentReceipt, Ticket, User

from .factories import build_operational_context
from .test_payment_security import FEDAPAY_SETTINGS, FETCH, fedapay_transaction, make_booking

CREATE = "apps.core.payments._fedapay_create_transaction"


@override_settings(**FEDAPAY_SETTINGS)
class RefreshPaymentTests(APITestCase):
    """« Vérifier mon paiement » : le client relance la relecture de SA transaction chez FedaPay."""

    def setUp(self):
        cache.clear()
        self.context = build_operational_context()
        self.fedapay = PaymentMethod.objects.create(code="FEDAPAY", label="FedaPay", active=True)
        self.booking = make_booking(self.context, customer=self.context["client"], seats=1)
        self.attempt = self.start_checkout(self.booking, "7001")

    def start_checkout(self, booking, transaction_id):
        with mock.patch(CREATE, return_value={"id": int(transaction_id), "payment_url": "https://paiement.exemple.test/x"}):
            payments.create_checkout(booking, payment_method=self.fedapay)
        return PaymentAttempt.objects.get(external_id=transaction_id)

    def refresh(self, booking=None, fetched=None, user="client", **extra):
        booking = booking or self.booking
        if user:
            self.client.force_authenticate(self.context[user] if isinstance(user, str) else user)
        with mock.patch(FETCH, return_value=fetched or fedapay_transaction(booking, transaction_id="7001")) as fetch:
            response = self.client.post(f"/api/v1/client/bookings/{booking.pk}/refresh-payment/", {}, format="json", **extra)
        return response, fetch

    def test_approved_payment_issues_the_ticket_at_the_price(self):
        response, fetch = self.refresh()
        self.assertEqual(response.status_code, 200, response.data)
        fetch.assert_called_once_with("7001")
        self.assertEqual(response.data["status"], Booking.Status.CONFIRMED)
        ticket = Ticket.objects.get(booking=self.booking)
        self.assertEqual(ticket.status, Ticket.Status.ISSUED)
        receipt = PaymentReceipt.objects.get(booking=self.booking)
        self.assertEqual((receipt.amount, receipt.source), (self.booking.amount, PaymentReceipt.Source.RECONCILIATION))
        self.attempt.refresh_from_db()
        self.assertEqual(self.attempt.outcome, PaymentAttempt.Outcome.SETTLED)

    def test_client_ticket_gives_its_booking_for_the_check(self):
        self.client.force_authenticate(self.context["client"])
        rows = self.client.get("/api/v1/client/tickets/").json()
        rows = rows["results"] if isinstance(rows, dict) else rows
        self.assertEqual([(row["status"], row["booking"]) for row in rows], [("HELD", self.booking.pk)])

    def test_pending_payment_changes_nothing(self):
        response, _ = self.refresh(fetched=fedapay_transaction(self.booking, transaction_id="7001", status="pending"))
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data["status"], Booking.Status.HELD)
        self.assertFalse(PaymentReceipt.objects.exists())
        self.attempt.refresh_from_db()
        self.assertEqual(self.attempt.outcome, PaymentAttempt.Outcome.PENDING)

    def test_repeated_requests_issue_a_single_ticket(self):
        self.refresh()
        response, fetch = self.refresh()
        self.assertEqual(response.status_code, 200)
        fetch.assert_not_called()  # déjà réglée : rien à redemander à FedaPay
        self.assertEqual(PaymentReceipt.objects.count(), 1)
        self.assertEqual(Ticket.objects.filter(booking=self.booking, status=Ticket.Status.ISSUED).count(), 1)

    def test_without_transaction_nothing_is_asked_to_fedapay(self):
        other = make_booking(self.context, customer=self.context["client"], seats=1, offset=1)
        response, fetch = self.refresh(booking=other)
        self.assertEqual(response.status_code, 200)
        fetch.assert_not_called()
        self.assertEqual(response.data["status"], Booking.Status.HELD)

    def test_only_this_booking_is_checked(self):
        other = make_booking(self.context, customer=self.context["client"], seats=1, offset=1)
        self.start_checkout(other, "7002")
        _, fetch = self.refresh()
        self.assertEqual([call.args[0] for call in fetch.call_args_list], ["7001"])

    def test_other_accounts_and_anonymous_are_refused(self):
        intruder = User.objects.create_user(username="intrus", password="secret", role=User.Role.CLIENT)
        response, fetch = self.refresh(user=intruder)
        self.assertIn(response.status_code, (403, 404))
        self.client.force_authenticate(None)
        response, fetch_anonymous = self.refresh(user=None)
        self.assertIn(response.status_code, (401, 403, 404))
        fetch.assert_not_called()
        fetch_anonymous.assert_not_called()
        self.assertFalse(PaymentReceipt.objects.exists())

    def test_guest_with_its_token_can_check(self):
        created = self.client.post(
            "/api/v1/client/bookings/",
            {
                "trip": self.context["trip"].pk,
                "contact_phone": "90000000",
                "passengers": [{"full_name": "Invité", "seat": self.context["trip"].seats.order_by("number")[2].pk}],
            },
            format="json",
        )
        self.assertEqual(created.status_code, 201, created.data)
        guest = Booking.objects.get(pk=created.data["id"])
        self.start_checkout(guest, "7003")
        fetched = fedapay_transaction(guest, transaction_id="7003")
        response, _ = self.refresh(booking=guest, fetched=fetched, user=None)
        self.assertIn(response.status_code, (403, 404))
        response, _ = self.refresh(booking=guest, fetched=fetched, user=None, HTTP_X_BOOKING_TOKEN=created.data["guest_access_token"])
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data["status"], Booking.Status.CONFIRMED)

    def test_requests_are_limited_per_address_with_a_clear_message(self):
        merged = {**api_settings.user_settings, "DEFAULT_THROTTLE_RATES": {**api_settings.DEFAULT_THROTTLE_RATES, "payment_refresh": "2/min"}}
        pending = fedapay_transaction(self.booking, transaction_id="7001", status="pending")
        with override_settings(REST_FRAMEWORK=merged):
            self.assertEqual(self.refresh(fetched=pending)[0].status_code, 200)
            self.assertEqual(self.refresh(fetched=pending)[0].status_code, 200)
            blocked, fetch = self.refresh(fetched=pending)
        self.assertEqual(blocked.status_code, 429)
        self.assertIn("Trop de tentatives", blocked.data["detail"])
        fetch.assert_not_called()
