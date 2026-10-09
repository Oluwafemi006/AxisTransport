from unittest import mock

from django.test import override_settings
from rest_framework.test import APITestCase

from apps.core import payments
from apps.core.models import Booking, PaymentAttempt, PaymentMethod, PaymentReceipt, Seat, Ticket, User
from apps.core.services import reserve_booking

from .factories import build_operational_context
from .test_payment_security import (
    FEDAPAY_SETTINGS,
    FETCH,
    WEBHOOK_URL,
    fedapay_transaction,
    signed_headers,
    webhook_body,
)

BOOKINGS = "/api/v1/client/bookings/"
CREATE = "apps.core.payments._fedapay_create_transaction"


@override_settings(**FEDAPAY_SETTINGS)
class BookingCancellationTests(APITestCase):
    """Annulation par le client d'une réservation non payée : siège libéré, paiement tardif à rembourser."""

    def setUp(self):
        self.context = build_operational_context()
        self.trip = self.context["trip"]
        self.fedapay = PaymentMethod.objects.create(code="FEDAPAY", label="FedaPay", active=True)
        self.seat = self.trip.seats.order_by("number").first()
        self.owner = self.context["client"]
        self.booking, _ = reserve_booking(
            trip=self.trip, customer=self.owner, passengers=[{"full_name": "Awa Test", "seat": self.seat}]
        )
        self.url = f"{BOOKINGS}{self.booking.pk}/cancel/"

    def guest_booking(self):
        seat = self.trip.seats.order_by("number")[1]
        booking, token = reserve_booking(
            trip=self.trip, customer=None, contact_phone="90000000", passengers=[{"full_name": "Invité", "seat": seat}]
        )
        return booking, token, seat

    def start_checkout(self, booking=None, transaction_id="3001"):
        with mock.patch(CREATE, return_value={"id": int(transaction_id), "payment_url": "https://paiement.exemple.test/x"}):
            payments.create_checkout(booking or self.booking, payment_method=self.fedapay)
        return PaymentAttempt.objects.get(external_id=transaction_id)

    def assert_cancelled(self, booking, seat):
        booking.refresh_from_db()
        seat.refresh_from_db()
        self.assertEqual(booking.status, Booking.Status.CANCELLED)
        self.assertEqual(set(booking.tickets.values_list("status", flat=True)), {Ticket.Status.CANCELLED})
        self.assertEqual(seat.status, Seat.Status.AVAILABLE)

    def assert_refund_due_without_ticket(self, source):
        self.booking.refresh_from_db()
        self.assertEqual(self.booking.status, Booking.Status.REFUND_DUE)
        self.assertFalse(self.booking.tickets.filter(status__in=[Ticket.Status.ISSUED, Ticket.Status.PAID]).exists())
        receipt = PaymentReceipt.objects.get()
        self.assertTrue(receipt.refund_due)
        self.assertEqual(receipt.source, source)

    # ── Qui peut annuler
    def test_owner_cancels_and_the_seat_is_free_at_once(self):
        self.client.force_authenticate(self.owner)
        response = self.client.post(self.url)
        self.assertEqual(response.status_code, 200, response.data)
        self.assertTrue(response.data["cancelled"])
        self.assertEqual(response.data["status"], Booking.Status.CANCELLED)
        self.assert_cancelled(self.booking, self.seat)
        # Le siège est revendable tout de suite.
        again, _ = reserve_booking(trip=self.trip, customer=self.owner, passengers=[{"full_name": "Autre", "seat": self.seat}])
        self.assertEqual(again.status, Booking.Status.HELD)

    def test_guest_cancels_with_the_booking_token(self):
        booking, token, seat = self.guest_booking()
        response = self.client.post(f"{BOOKINGS}{booking.pk}/cancel/", HTTP_X_BOOKING_TOKEN=token)
        self.assertEqual(response.status_code, 200, response.data)
        self.assert_cancelled(booking, seat)

    def test_anyone_else_is_refused(self):
        booking, token, seat = self.guest_booking()
        other = User.objects.create_user(username="autre", password="secret", role=User.Role.CLIENT)
        attempts = [
            (self.url, {}, None),  # anonyme, sans jeton
            (self.url, {"HTTP_X_BOOKING_TOKEN": token}, None),  # jeton d'une autre réservation
            (self.url, {}, other),  # autre client
            (self.url, {}, self.context["admin"]),  # personnel : pas par la surface client
            (f"{BOOKINGS}{booking.pk}/cancel/", {"HTTP_X_BOOKING_TOKEN": "faux-jeton"}, None),
            (f"{BOOKINGS}{booking.pk}/cancel/", {}, self.owner),  # un client sur la réservation d'un invité
        ]
        for url, headers, user in attempts:
            self.client.force_authenticate(user)
            self.assertEqual(self.client.post(url, **headers).status_code, 403, (url, headers, user))
        for held, held_seat in ((self.booking, self.seat), (booking, seat)):
            held.refresh_from_db()
            held_seat.refresh_from_db()
            self.assertEqual((held.status, held_seat.status), (Booking.Status.HELD, Seat.Status.HELD))

    # ── Ce qui ne s'annule pas
    def test_paid_booking_cannot_be_cancelled(self):
        self.start_checkout()
        with mock.patch(FETCH, return_value=fedapay_transaction(self.booking, transaction_id="3001")):
            payments.settle_fedapay_transaction("3001", source=PaymentReceipt.Source.WEBHOOK)
        self.client.force_authenticate(self.owner)
        response = self.client.post(self.url)
        self.assertEqual(response.status_code, 400, response.data)
        self.booking.refresh_from_db()
        self.seat.refresh_from_db()
        self.assertEqual(self.booking.status, Booking.Status.CONFIRMED)
        self.assertEqual(self.booking.tickets.filter(status=Ticket.Status.ISSUED).count(), 1)
        self.assertEqual(self.seat.status, Seat.Status.PAID)

    def test_double_cancellation_is_idempotent(self):
        self.client.force_authenticate(self.owner)
        first, second = self.client.post(self.url), self.client.post(self.url)
        self.assertEqual((first.status_code, second.status_code), (200, 200))
        self.assertEqual((first.data["cancelled"], second.data["cancelled"]), (True, False))
        self.assert_cancelled(self.booking, self.seat)
        self.assertEqual(self.booking.tickets.get().status_history.filter(to_status=Ticket.Status.CANCELLED).count(), 1)

    # ── Transaction déjà créée, puis paiement malgré l'annulation
    def test_cancellation_marks_the_created_transaction_as_abandoned(self):
        attempt = self.start_checkout()
        self.client.force_authenticate(self.owner)
        self.client.post(self.url)
        attempt.refresh_from_db()
        self.assertEqual(attempt.outcome, PaymentAttempt.Outcome.CANCELLED)
        self.assertIn("Abandonnée", attempt.get_outcome_display())

    def cancel_then(self):
        attempt = self.start_checkout()
        self.client.force_authenticate(self.owner)
        self.assertEqual(self.client.post(self.url).status_code, 200)
        return attempt

    def test_late_payment_after_cancellation_seen_by_webhook_is_refund_due(self):
        self.cancel_then()
        self.client.force_authenticate(None)
        body = webhook_body("3001")
        with mock.patch(FETCH, return_value=fedapay_transaction(self.booking, transaction_id="3001")):
            response = self.client.post(WEBHOOK_URL, data=body, content_type="application/json", **signed_headers(body))
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual((response.data["status"], response.data["tickets_issued"]), ("REFUND_DUE", 0))
        self.assert_refund_due_without_ticket(PaymentReceipt.Source.WEBHOOK)

    def test_late_payment_after_cancellation_seen_by_reconciliation_is_refund_due(self):
        attempt = self.cancel_then()
        with mock.patch(FETCH, return_value=fedapay_transaction(self.booking, transaction_id="3001")):
            counts = payments.reconcile_pending_payments()
        self.assertEqual(counts["refund_due"], 1)
        self.assert_refund_due_without_ticket(PaymentReceipt.Source.RECONCILIATION)
        attempt.refresh_from_db()
        self.assertEqual(attempt.outcome, PaymentAttempt.Outcome.REFUND_DUE)

    def test_late_payment_after_cancellation_checked_by_the_client_is_refund_due(self):
        self.cancel_then()
        with mock.patch(FETCH, return_value=fedapay_transaction(self.booking, transaction_id="3001")):
            response = self.client.post(
                f"{BOOKINGS}{self.booking.pk}/pay/", {"payment_method": self.fedapay.pk, "external_reference": "3001"}, format="json"
            )
        self.assertEqual(response.status_code, 409, response.data)
        self.assertTrue(response.data["refund_due"])
        self.assert_refund_due_without_ticket(PaymentReceipt.Source.CLIENT)

    def test_late_payment_never_takes_back_a_seat_sold_to_someone_else(self):
        self.cancel_then()
        other = User.objects.create_user(username="autre", password="secret", role=User.Role.CLIENT)
        resold, _ = reserve_booking(trip=self.trip, customer=other, passengers=[{"full_name": "Nouveau", "seat": self.seat}])
        with mock.patch(FETCH, return_value=fedapay_transaction(self.booking, transaction_id="3001")):
            payments.reconcile_pending_payments()
        self.assert_refund_due_without_ticket(PaymentReceipt.Source.RECONCILIATION)
        resold.refresh_from_db()
        self.seat.refresh_from_db()
        self.assertEqual((resold.status, self.seat.status), (Booking.Status.HELD, Seat.Status.HELD))
        self.assertEqual(resold.tickets.get().status, Ticket.Status.HELD)

    def test_unpaid_cancelled_transaction_stays_watched_then_stops(self):
        attempt = self.cancel_then()
        with mock.patch(FETCH, return_value=fedapay_transaction(self.booking, transaction_id="3001", status="pending")) as fetch:
            payments.reconcile_pending_payments()
        self.assertEqual(fetch.call_count, 1)
        attempt.refresh_from_db()
        self.assertEqual(attempt.outcome, PaymentAttempt.Outcome.CANCELLED)
        with mock.patch(FETCH, return_value=fedapay_transaction(self.booking, transaction_id="3001", status="canceled")):
            payments.reconcile_pending_payments()
        attempt.refresh_from_db()
        self.assertEqual(attempt.outcome, PaymentAttempt.Outcome.REFUSED)
        self.assertEqual(PaymentReceipt.objects.count(), 0)

    def test_checkout_is_refused_on_a_cancelled_booking(self):
        self.client.force_authenticate(self.owner)
        self.client.post(self.url)
        with mock.patch(CREATE) as create:
            response = self.client.post(f"{BOOKINGS}{self.booking.pk}/checkout/", {"payment_method": self.fedapay.pk}, format="json")
        self.assertEqual(response.status_code, 400)
        create.assert_not_called()
