from datetime import timedelta
from decimal import Decimal
from unittest import mock

from django.test import override_settings
from django.utils import timezone
from rest_framework.test import APITestCase

from apps.core import payments
from apps.core.models import Booking, FareRule, PaymentAttempt, PaymentMethod, Seat

from .factories import build_operational_context
from .test_payment_security import FEDAPAY_SETTINGS

CREATE = "apps.core.payments._fedapay_create_transaction"
BOOKINGS = "/api/v1/client/bookings/"


@override_settings(**FEDAPAY_SETTINGS)
class SinglePayButtonTests(APITestCase):
    """Parcours « Payer [total] » : total connu avant le clic, une seule réservation, paiement réessayable."""

    def setUp(self):
        # Départ demain : seuls les départs à venir sont proposés aux clients.
        self.context = build_operational_context(trip_date=timezone.localdate() + timedelta(days=1))
        self.trip = self.context["trip"]
        self.fedapay = PaymentMethod.objects.create(code="FEDAPAY", label="FedaPay", active=True, fee_percentage=Decimal("1.8"))
        self.seat = self.trip.seats.order_by("number").first()
        self.quotes_url = f"/api/v1/client/trips/{self.trip.pk}/payment-quotes/"

    def book(self, seat=None, **extra):
        seat = seat or self.seat
        return self.client.post(
            BOOKINGS,
            {"trip": self.trip.pk, "contact_phone": "90000000", "passengers": [{"full_name": "Awa Test", "seat": seat.pk}], **extra},
            format="json",
        )

    def checkout(self, booking, token, transaction_id=2001):
        created = {"id": transaction_id, "payment_url": "https://paiement.exemple.test/x"}
        with mock.patch(CREATE, return_value=created):
            return self.client.post(
                f"{BOOKINGS}{booking}/checkout/", {"payment_method": self.fedapay.pk}, format="json", HTTP_X_BOOKING_TOKEN=token
            )

    # ── Total visible avant le clic
    def test_total_is_given_by_the_server_before_any_booking(self):
        response = self.client.get(self.quotes_url)
        self.assertEqual(response.status_code, 200, response.data)
        (quote,) = response.json()
        self.assertEqual((Decimal(str(quote["amount"])), Decimal(str(quote["fee_amount"])), Decimal(str(quote["total"]))), (Decimal("1000"), Decimal("18"), Decimal("1018")))
        self.assertEqual(quote["payment_method"], self.fedapay.pk)
        self.assertEqual(Booking.objects.count(), 0)

    def test_quote_equals_the_amount_charged_at_checkout(self):
        quote = self.client.get(self.quotes_url).json()[0]
        created = self.book()
        checkout = self.checkout(created.data["id"], created.data["guest_access_token"])
        self.assertEqual(checkout.status_code, 200, checkout.data)
        self.assertEqual(Decimal(str(checkout.data["total"])), Decimal(str(quote["total"])))

    def test_quote_lists_only_online_methods(self):
        PaymentMethod.objects.create(code="especes", label="Espèces", active=True)
        PaymentMethod.objects.create(code="SIMULATION", label="Simulé", active=True)
        self.assertEqual([item["code"] for item in self.client.get(self.quotes_url).json()], ["FEDAPAY"])

    def test_quote_scales_with_passengers_and_rejects_bad_counts(self):
        self.assertEqual(Decimal(str(self.client.get(self.quotes_url, {"passengers": 2}).json()[0]["total"])), Decimal("2036"))
        for value in ("0", "9", "abc"):
            self.assertEqual(self.client.get(self.quotes_url, {"passengers": value}).status_code, 400)

    def test_trip_without_fare_has_no_quote_and_no_fallback(self):
        FareRule.objects.all().delete()
        self.assertEqual(self.client.get(self.quotes_url).status_code, 400)

    # ── Double clic
    def test_double_click_creates_a_single_booking_for_the_seat(self):
        first, second = self.book(), self.book()
        self.assertEqual(first.status_code, 201, first.data)
        self.assertEqual(second.status_code, 400, second.data)
        self.assertEqual(Booking.objects.count(), 1)
        self.assertEqual(Seat.objects.filter(trip=self.trip, status=Seat.Status.HELD).count(), 1)

    # ── Échec du paiement après la réservation, puis réessai
    def test_failed_checkout_keeps_the_booking_and_retry_reuses_it(self):
        created = self.book()
        booking_id, token = created.data["id"], created.data["guest_access_token"]
        expires = Booking.objects.get(pk=booking_id).reservation_expires_at
        with mock.patch(CREATE, side_effect=payments.ProviderUnavailable("Impossible de contacter FedaPay.")):
            failed = self.client.post(
                f"{BOOKINGS}{booking_id}/checkout/", {"payment_method": self.fedapay.pk}, format="json", HTTP_X_BOOKING_TOKEN=token
            )
        self.assertEqual(failed.status_code, 400, failed.data)
        booking = Booking.objects.get(pk=booking_id)
        self.assertEqual(booking.status, Booking.Status.HELD)
        self.assertEqual(PaymentAttempt.objects.count(), 0)

        retry = self.checkout(booking_id, token)
        self.assertEqual(retry.status_code, 200, retry.data)
        self.assertTrue(retry.data["payment_url"])
        # Même réservation, même siège, même délai de tenue.
        self.assertEqual(Booking.objects.count(), 1)
        booking.refresh_from_db()
        self.assertEqual(booking.reservation_expires_at, expires)
        self.seat.refresh_from_db()
        self.assertEqual(self.seat.status, Seat.Status.HELD)
        self.assertEqual(PaymentAttempt.objects.get().booking_id, booking_id)

    def test_resuming_payment_twice_keeps_one_booking(self):
        created = self.book()
        booking_id, token = created.data["id"], created.data["guest_access_token"]
        self.checkout(booking_id, token, 2001)
        self.checkout(booking_id, token, 2002)
        self.assertEqual(Booking.objects.count(), 1)
        self.assertEqual(PaymentAttempt.objects.filter(booking_id=booking_id).count(), 2)

    def test_checkout_of_another_guest_booking_is_forbidden(self):
        created = self.book()
        other = self.book(seat=self.trip.seats.order_by("number")[1])
        response = self.checkout(created.data["id"], other.data["guest_access_token"])
        self.assertEqual(response.status_code, 403)
