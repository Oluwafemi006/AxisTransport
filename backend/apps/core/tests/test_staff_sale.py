from datetime import timedelta
from decimal import Decimal
from unittest import mock

from django.test import override_settings
from django.utils import timezone
from rest_framework.test import APITestCase

from apps.core import payments
from apps.core.models import Booking, FareRule, PaymentAttempt, PaymentMethod, PaymentReceipt, Seat, Ticket, Trip, User
from apps.core.services import generate_trip_seats, release_expired_holds

from .factories import build_operational_context
from .test_payment_security import FEDAPAY_SETTINGS, FETCH, fedapay_transaction

SALES = "/api/v1/staff/sales/"
CREATE = "apps.core.payments._fedapay_create_transaction"


@override_settings(**FEDAPAY_SETTINGS)
class StaffSaleTests(APITestCase):
    """Vente d'un billet par un agent depuis l'application staff (contrôleur à l'arrêt, guichet, admin)."""

    def setUp(self):
        self.context = build_operational_context()  # départ du jour
        self.trip = self.context["trip"]
        self.controller = self.context["controller"]
        self.counter = User.objects.create_user(username="guichet", password="secret", role=User.Role.COUNTER)
        self.cash = PaymentMethod.objects.create(code="especes", label="Espèces", active=True)
        self.fedapay = PaymentMethod.objects.create(code="FEDAPAY", label="FedaPay", active=True, fee_percentage=Decimal("1.8"))
        self.seat = self.trip.seats.order_by("number").first()
        self.client.force_authenticate(self.controller)

    def sell(self, key="vente-0001", method=None, seat=None, trip=None, **extra):
        return self.client.post(
            f"{SALES}sell/",
            {
                "idempotency_key": key,
                "trip": (trip or self.trip).pk,
                "seat": (seat or self.seat).pk,
                "passenger_name": "Awa Test",
                "passenger_phone": "90000000",
                "payment_method": (method or self.cash).pk,
                **extra,
            },
            format="json",
        )

    def sell_mobile_money(self, key="vente-mm-01", transaction_id=5001, **kwargs):
        with mock.patch(CREATE, return_value={"id": transaction_id, "payment_url": "https://paiement.exemple.test/x"}):
            return self.sell(key=key, method=self.fedapay, **kwargs)

    def tomorrow_trip(self):
        departure = self.trip.departure_at + timedelta(days=1)
        trip = Trip.objects.create(route=self.trip.route, vehicle=self.trip.vehicle, departure_at=departure)
        generate_trip_seats(trip)
        return trip

    # ── Espèces
    def test_controller_sells_for_cash_and_the_sale_is_auditable(self):
        response = self.sell()
        self.assertEqual(response.status_code, 201, response.data)
        ticket = Ticket.objects.get()
        self.assertEqual((ticket.status, ticket.amount, ticket.channel), (Ticket.Status.ISSUED, Decimal("1000.00"), Ticket.Channel.COUNTER))
        self.assertEqual(response.data["booking"]["tickets"][0]["reference"], ticket.reference)
        booking = Booking.objects.get()
        self.assertEqual((booking.status, booking.sold_by), (Booking.Status.CONFIRMED, self.controller))
        receipt = PaymentReceipt.objects.get()
        self.assertEqual((receipt.recorded_by, receipt.source, receipt.amount), (self.controller, PaymentReceipt.Source.COUNTER, Decimal("1000.00")))
        self.assertIsNotNone(receipt.created_at)
        self.seat.refresh_from_db()
        self.assertEqual(self.seat.status, Seat.Status.PAID)

    def test_same_key_replayed_never_sells_twice(self):
        first, second = self.sell(), self.sell()
        self.assertEqual((first.status_code, second.status_code), (201, 200))
        self.assertEqual((first.data["created"], second.data["created"]), (True, False))
        self.assertEqual(first.data["booking"]["id"], second.data["booking"]["id"])
        self.assertEqual((Booking.objects.count(), Ticket.objects.count(), PaymentReceipt.objects.count()), (1, 1, 1))

    def test_missing_or_invalid_key_is_refused(self):
        for key in ("", "court", "avec espace 123"):
            self.assertEqual(self.sell(key=key).status_code, 400, key)
        self.assertEqual(Booking.objects.count(), 0)

    # ── Qui peut vendre
    def test_other_roles_cannot_sell_whatever_the_app_shows(self):
        self.client.force_authenticate(self.context["client"])
        self.assertEqual(self.sell().status_code, 403)
        self.assertEqual(self.client.get(f"{SALES}options/").status_code, 403)
        self.client.force_authenticate(None)
        self.assertEqual(self.sell().status_code, 401)
        self.assertEqual(Booking.objects.count(), 0)

    def test_counter_and_admin_can_also_sell(self):
        # Départ de demain : le guichet et l'admin ne vendent que des départs à venir, quelle que soit l'heure du test.
        trip = self.tomorrow_trip()
        for index, user in enumerate((self.counter, self.context["admin"])):
            self.client.force_authenticate(user)
            seat = trip.seats.order_by("number")[index]
            self.assertEqual(self.sell(key=f"vente-agent-{index}", trip=trip, seat=seat).status_code, 201)

    # ── Ce que le contrôleur ne peut pas forcer
    def test_controller_sells_only_on_today_departures(self):
        trip = self.tomorrow_trip()
        response = self.sell(trip=trip, seat=trip.seats.first())
        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(Booking.objects.count(), 0)
        # Le guichet, lui, vend les départs à venir.
        self.client.force_authenticate(self.counter)
        self.assertEqual(self.sell(key="vente-guichet-1", trip=trip, seat=trip.seats.first()).status_code, 201)

    def test_no_fare_means_no_sale_and_no_fallback_price(self):
        FareRule.objects.all().delete()
        self.assertEqual(self.sell().status_code, 400)
        self.assertEqual(Booking.objects.count(), 0)
        (trip,) = self.client.get(f"{SALES}options/").json()["trips"]
        self.assertEqual(trip["quotes"], [])

    def test_taken_seat_and_closed_trip_are_refused(self):
        self.sell()
        self.assertEqual(self.sell(key="vente-0002").status_code, 400)  # même siège, autre vente
        Trip.objects.filter(pk=self.trip.pk).update(status=Trip.Status.CANCELLED)
        other = self.trip.seats.order_by("number")[1]
        self.assertEqual(self.sell(key="vente-0003", seat=other).status_code, 400)
        self.assertEqual(Ticket.objects.count(), 1)

    def test_seat_of_another_trip_is_refused(self):
        trip = self.tomorrow_trip()
        self.assertEqual(self.sell(seat=trip.seats.first()).status_code, 400)
        self.assertEqual(Booking.objects.count(), 0)

    # ── Ce que l'application affiche avant la vente
    def test_options_list_today_departures_with_server_amounts(self):
        self.tomorrow_trip()
        trips = self.client.get(f"{SALES}options/").json()["trips"]
        self.assertEqual([item["id"] for item in trips], [self.trip.pk])
        self.assertEqual(trips[0]["available_seats"], 4)
        quotes = {item["code"]: item for item in trips[0]["quotes"]}
        self.assertEqual((Decimal(str(quotes["especes"]["total"])), quotes["especes"]["online"]), (Decimal("1000"), False))
        self.assertEqual((Decimal(str(quotes["FEDAPAY"]["total"])), quotes["FEDAPAY"]["online"]), (Decimal("1018"), True))

    # ── Mobile Money
    def test_mobile_money_holds_the_seat_and_issues_only_after_server_check(self):
        response = self.sell_mobile_money()
        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(response.data["checkout"]["payment_url"], "https://paiement.exemple.test/x")
        self.assertEqual(Decimal(str(response.data["checkout"]["total"])), Decimal("1018"))
        booking = Booking.objects.get()
        self.assertEqual(booking.status, Booking.Status.HELD)
        self.assertEqual(Ticket.objects.get().status, Ticket.Status.HELD)
        self.assertEqual(PaymentReceipt.objects.count(), 0)
        self.assertEqual(PaymentAttempt.objects.get().booking, booking)

        verify = f"{SALES}{booking.pk}/verify/"
        body = {"payment_method": self.fedapay.pk, "external_reference": "5001"}
        # Paiement pas encore fait : aucun billet, l'état « en attente » est transmis.
        with mock.patch(FETCH, return_value=fedapay_transaction(booking, transaction_id="5001", amount=1018, status="pending")):
            pending = self.client.post(verify, body, format="json")
        self.assertEqual(pending.status_code, 400)
        self.assertEqual(str(pending.data["payment_status"]), "pending")
        self.assertEqual(Ticket.objects.get().status, Ticket.Status.HELD)

        with mock.patch(FETCH, return_value=fedapay_transaction(booking, transaction_id="5001", amount=1018)):
            paid = self.client.post(verify, body, format="json")
        self.assertEqual(paid.status_code, 200, paid.data)
        self.assertEqual(Ticket.objects.get().status, Ticket.Status.ISSUED)
        receipt = PaymentReceipt.objects.get()
        self.assertEqual((receipt.recorded_by, receipt.amount, receipt.provider), (self.controller, Decimal("1018.00"), "FEDAPAY"))

    def test_unpaid_mobile_money_sale_expires_and_frees_the_seat(self):
        self.sell_mobile_money()
        Ticket.objects.update(reservation_expires_at=timezone.now() - timedelta(minutes=1))
        Booking.objects.update(reservation_expires_at=timezone.now() - timedelta(minutes=1))
        release_expired_holds()
        self.seat.refresh_from_db()
        self.assertEqual(self.seat.status, Seat.Status.AVAILABLE)
        booking = Booking.objects.get()
        self.assertEqual(self.client.get(f"{SALES}{booking.pk}/").json()["booking"]["status"], Booking.Status.EXPIRED)
        self.assertEqual(Ticket.objects.filter(status=Ticket.Status.ISSUED).count(), 0)

    def test_payment_start_failure_keeps_the_seat_and_retry_reuses_the_sale(self):
        with mock.patch(CREATE, side_effect=payments.ProviderUnavailable("Impossible de contacter FedaPay.")):
            failed = self.sell(key="vente-mm-02", method=self.fedapay)
        self.assertEqual(failed.status_code, 201, failed.data)
        self.assertIsNone(failed.data["checkout"])
        self.assertIn("FedaPay", failed.data["payment_error"])
        self.assertEqual(Booking.objects.get().status, Booking.Status.HELD)

        retry = self.sell_mobile_money(key="vente-mm-02")
        self.assertEqual(retry.status_code, 200, retry.data)
        self.assertTrue(retry.data["checkout"]["payment_url"])
        self.assertEqual(Booking.objects.count(), 1)
        self.assertEqual(Ticket.objects.count(), 1)

    def test_agent_cancels_an_unpaid_sale_and_frees_the_seat(self):
        self.sell_mobile_money()
        booking = Booking.objects.get()
        response = self.client.post(f"{SALES}{booking.pk}/cancel/")
        self.assertEqual(response.status_code, 200, response.data)
        self.assertTrue(response.data["cancelled"])
        self.seat.refresh_from_db()
        self.assertEqual(self.seat.status, Seat.Status.AVAILABLE)
        self.assertEqual(PaymentAttempt.objects.get().outcome, PaymentAttempt.Outcome.CANCELLED)

    def test_paid_sale_cannot_be_cancelled(self):
        self.sell()
        booking = Booking.objects.get()
        self.assertEqual(self.client.post(f"{SALES}{booking.pk}/cancel/").status_code, 400)
        self.assertEqual(Ticket.objects.get().status, Ticket.Status.ISSUED)

    def test_another_agent_cannot_touch_the_sale_but_admin_can_see_it(self):
        self.sell_mobile_money()
        booking = Booking.objects.get()
        other = User.objects.create_user(username="controleur2", password="secret", role=User.Role.CONTROLLER)
        self.client.force_authenticate(other)
        self.assertEqual(self.client.get(f"{SALES}{booking.pk}/").status_code, 403)
        self.assertEqual(self.client.post(f"{SALES}{booking.pk}/cancel/").status_code, 403)
        self.assertEqual(
            self.client.post(f"{SALES}{booking.pk}/verify/", {"payment_method": self.fedapay.pk, "external_reference": "5001"}, format="json").status_code, 403
        )
        self.client.force_authenticate(self.context["admin"])
        self.assertEqual(self.client.get(f"{SALES}{booking.pk}/").status_code, 200)
        booking.refresh_from_db()
        self.assertEqual(booking.status, Booking.Status.HELD)

    def test_client_bookings_are_not_reachable_through_the_sale_surface(self):
        from apps.core.services import reserve_booking

        own, _ = reserve_booking(trip=self.trip, customer=self.context["client"], passengers=[{"full_name": "Client", "seat": self.seat}])
        self.assertEqual(self.client.get(f"{SALES}{own.pk}/").status_code, 404)
        self.assertEqual(self.client.post(f"{SALES}{own.pk}/cancel/").status_code, 404)
