import json
from datetime import timedelta
from decimal import Decimal
from io import StringIO
from unittest import mock

from django.core.management import call_command
from django.core.management.base import CommandError
from django.test import TestCase, override_settings
from django.utils import timezone
from rest_framework.test import APITestCase

from apps.core.models import (
    Booking,
    FareRule,
    PaymentMethod,
    PaymentReceipt,
    Seat,
    SegmentFare,
    Ticket,
    Transaction,
    Trip,
    User,
)
from apps.core.services import release_expired_holds, reserve_ticket

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
class FeesAndCheckoutTests(APITestCase):
    def setUp(self):
        self.context = build_operational_context()
        self.fedapay = PaymentMethod.objects.create(
            code="FEDAPAY", label="FedaPay", active=True, fee_percentage=Decimal("1.80")
        )
        self.booking = make_booking(self.context, customer=self.context["client"])
        self.client.force_authenticate(self.context["client"])
        self.base = f"/api/v1/client/bookings/{self.booking.pk}"

    def pay(self, **payload):
        return self.client.post(f"{self.base}/pay/", {"payment_method": self.fedapay.pk, **payload}, format="json")

    def test_booking_exposes_server_computed_total(self):
        quotes = self.client.get(f"{self.base}/").data["payment_quotes"]
        quote = next(item for item in quotes if item["code"] == "FEDAPAY")
        self.assertEqual(Decimal(str(quote["amount"])), Decimal("2000.00"))
        self.assertEqual(Decimal(str(quote["fee_amount"])), Decimal("36"))
        self.assertEqual(Decimal(str(quote["total"])), Decimal("2036"))

    def test_total_is_rounded_to_the_franc(self):
        from apps.core.payments import payment_quote

        self.fedapay.fee_percentage = Decimal("1.75")
        ticket = self.booking.tickets.first()  # 1000 XOF -> 1017,5 -> 1018
        self.assertEqual(payment_quote(ticket, self.fedapay)["total"], Decimal("1018"))

    def test_checkout_creates_transaction_with_server_amount(self):
        created = {"id": 777, "payment_url": "https://sandbox-process.fedapay.com/abc"}
        with mock.patch(CREATE, return_value=created) as create:
            response = self.client.post(f"{self.base}/checkout/", {"payment_method": self.fedapay.pk}, format="json")
        self.assertEqual(response.status_code, 200, response.data)
        payload = create.call_args.args[0]
        self.assertEqual(payload["amount"], 2000)
        self.assertEqual(payload["currency"], {"iso": "XOF"})
        self.assertEqual(payload["custom_metadata"]["booking_id"], self.booking.pk)
        self.assertEqual(response.data["transaction_id"], "777")
        self.assertEqual(response.data["payment_url"], created["payment_url"])
        self.assertEqual(Decimal(str(response.data["total"])), Decimal("2036"))

    @override_settings(FEDAPAY_CALLBACK_URL="")
    def test_checkout_sends_no_return_address_when_none_is_configured(self):
        created = {"id": 777, "payment_url": "https://sandbox-process.fedapay.com/abc"}
        with mock.patch(CREATE, return_value=created) as create:
            self.client.post(f"{self.base}/checkout/", {"payment_method": self.fedapay.pk}, format="json")
        self.assertNotIn("callback_url", create.call_args.args[0])

    def test_checkout_ignores_amount_sent_by_client(self):
        created = {"id": 777, "payment_url": "https://sandbox-process.fedapay.com/abc"}
        with mock.patch(CREATE, return_value=created) as create:
            self.client.post(
                f"{self.base}/checkout/", {"payment_method": self.fedapay.pk, "amount": 1, "total": 1}, format="json"
            )
        self.assertEqual(create.call_args.args[0]["amount"], 2000)

    def test_checkout_refused_for_other_client(self):
        other = User.objects.create_user(username="autre", password="secret", role=User.Role.CLIENT)
        self.client.force_authenticate(other)
        with mock.patch(CREATE) as create:
            response = self.client.post(f"{self.base}/checkout/", {"payment_method": self.fedapay.pk}, format="json")
        self.assertEqual(response.status_code, 403)
        create.assert_not_called()

    def test_checkout_refused_for_counter_only_method(self):
        with mock.patch(CREATE) as create:
            response = self.client.post(
                f"{self.base}/checkout/", {"payment_method": self.context["payment_method"].pk}, format="json"
            )
        self.assertEqual(response.status_code, 400)
        create.assert_not_called()

    @override_settings(FEDAPAY_SECRET_KEY="")
    def test_checkout_refused_without_secret_key(self):
        with mock.patch(CREATE) as create:
            response = self.client.post(f"{self.base}/checkout/", {"payment_method": self.fedapay.pk}, format="json")
        self.assertEqual(response.status_code, 400)
        create.assert_not_called()

    def test_price_without_fees_is_refused(self):
        with mock.patch(FETCH, return_value=fedapay_transaction(self.booking, amount=2000)):
            response = self.pay(external_reference="1001")
        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(PaymentReceipt.objects.count(), 0)

    def test_price_with_fees_is_accepted(self):
        with mock.patch(FETCH, return_value=fedapay_transaction(self.booking, amount=2036)):
            response = self.pay(external_reference="1001")
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(PaymentReceipt.objects.get().amount, Decimal("2036.00"))

    def test_other_currency_is_refused(self):
        with mock.patch(FETCH, return_value=fedapay_transaction(self.booking, amount=2036, currency="EUR")):
            response = self.pay(external_reference="1001")
        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(PaymentReceipt.objects.count(), 0)

    def test_missing_currency_is_refused(self):
        with mock.patch(FETCH, return_value=fedapay_transaction(self.booking, amount=2036, currency=None)):
            response = self.pay(external_reference="1001")
        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(PaymentReceipt.objects.count(), 0)


@override_settings(**FEDAPAY_SETTINGS)
class TicketShowsFareOnlyTests(APITestCase):
    """Avec un taux de frais client configuré (0 par défaut), le billet porte toujours le prix du billet seul."""

    def setUp(self):
        self.context = build_operational_context()
        SegmentFare.objects.filter(pk=self.context["segment_fare"].pk).update(amount=7500)
        self.fedapay = PaymentMethod.objects.create(
            code="FEDAPAY", label="FedaPay", active=True, fee_percentage=Decimal("1.80")
        )
        self.booking = make_booking(self.context, customer=self.context["client"], seats=1)
        self.client.force_authenticate(self.context["client"])

    def test_ticket_keeps_fare_when_total_paid_includes_fees(self):
        quote = self.client.get(f"/api/v1/client/bookings/{self.booking.pk}/").data["payment_quotes"]
        total = next(Decimal(str(item["total"])) for item in quote if item["code"] == "FEDAPAY")
        self.assertEqual(total, Decimal("7635"))  # 7 500 + 1,80 % = 7 635

        with mock.patch(FETCH, return_value=fedapay_transaction(self.booking, amount=7635)):
            paid = self.client.post(
                f"/api/v1/client/bookings/{self.booking.pk}/pay/",
                {"payment_method": self.fedapay.pk, "external_reference": "1001"},
                format="json",
            )
        self.assertEqual(paid.status_code, 200, paid.data)

        ticket = Ticket.objects.get(booking=self.booking)
        self.assertEqual(ticket.amount, Decimal("7500.00"))
        self.assertEqual(Transaction.objects.get(ticket=ticket).amount, Decimal("7500.00"))
        # Le total payé, frais inclus, ne vit que dans le reçu de paiement.
        self.assertEqual(PaymentReceipt.objects.get(booking=self.booking).amount, Decimal("7635.00"))

        issued = paid.data["booking"]["tickets"][0]
        self.assertEqual(Decimal(str(issued["amount"])), Decimal("7500.00"))
        mine = self.client.get(f"/api/v1/client/tickets/{ticket.pk}/").data
        self.assertEqual(Decimal(str(mine["amount"])), Decimal("7500.00"))
        public = self.client.get(f"/api/v1/client/tickets/public/{ticket.reference}/").json()
        self.assertEqual(Decimal(str(public["amount"])), Decimal("7500.00"))
        self.assertEqual(public["formatted_amount"], "7 500 XOF")
        self.assertNotIn("7635", json.dumps(public))
        self.assertNotIn("7 635", json.dumps(public, ensure_ascii=False))


@override_settings(**FEDAPAY_SETTINGS)
class PaidAfterExpiryTests(APITestCase):
    def setUp(self):
        self.context = build_operational_context()
        self.fedapay = PaymentMethod.objects.create(code="FEDAPAY", label="FedaPay", active=True)
        self.booking = make_booking(self.context, customer=self.context["client"])
        past = timezone.now() - timedelta(minutes=1)
        Booking.objects.filter(pk=self.booking.pk).update(reservation_expires_at=past)
        Ticket.objects.filter(booking=self.booking).update(reservation_expires_at=past)
        Seat.objects.filter(tickets__booking=self.booking).update(hold_expires_at=past)
        # Les autres places du voyage sont occupées (PAID) et l'une des places a été vendue :
        # il ne reste plus assez de places libres pour les 2 passagers de la réservation.
        booking_seat_ids = list(self.booking.tickets.values_list("seat_id", flat=True))
        Seat.objects.filter(trip=self.context["trip"]).exclude(pk__in=booking_seat_ids).update(status=Seat.Status.PAID)
        Seat.objects.filter(pk=booking_seat_ids[0]).update(status=Seat.Status.PAID, hold_expires_at=None)
        Ticket.objects.filter(booking=self.booking, seat_id=booking_seat_ids[0]).update(status=Ticket.Status.EXPIRED)
        self.client.force_authenticate(self.context["client"])

    def pay(self):
        with mock.patch(FETCH, return_value=fedapay_transaction(self.booking)):
            return self.client.post(
                f"/api/v1/client/bookings/{self.booking.pk}/pay/",
                {"payment_method": self.fedapay.pk, "external_reference": "1001"},
                format="json",
            )

    def assert_refund_due(self):
        self.booking.refresh_from_db()
        self.assertEqual(self.booking.status, Booking.Status.REFUND_DUE)
        receipt = PaymentReceipt.objects.get()
        self.assertTrue(receipt.refund_due)
        self.assertEqual((receipt.external_id, receipt.booking_id), ("1001", self.booking.pk))
        self.assertFalse(Ticket.objects.filter(booking=self.booking, status=Ticket.Status.ISSUED).exists())
        self.assertEqual(Transaction.objects.count(), 0)
        self.assertEqual(
            Seat.objects.filter(tickets__booking=self.booking, status=Seat.Status.AVAILABLE).count(), 1
        )

    def test_payment_after_expiry_keeps_receipt_and_issues_nothing(self):
        response = self.pay()
        self.assertEqual(response.status_code, 409, response.data)
        self.assertTrue(response.data["refund_due"])
        self.assert_refund_due()

    def test_payment_after_holds_were_released(self):
        release_expired_holds()
        self.booking.refresh_from_db()
        self.assertEqual(self.booking.status, Booking.Status.EXPIRED)
        self.assertEqual(self.pay().status_code, 409)
        self.assert_refund_due()

    def test_second_arrival_does_not_duplicate_receipt(self):
        self.assertEqual(self.pay().status_code, 409)
        self.assertEqual(self.pay().status_code, 409)
        self.assert_refund_due()

    def test_webhook_after_expiry_reports_refund_due(self):
        body = webhook_body()
        with mock.patch(FETCH, return_value=fedapay_transaction(self.booking)):
            response = self.client.post(
                WEBHOOK_URL, data=body, content_type="application/json", **signed_headers(body)
            )
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data["status"], "REFUND_DUE")
        self.assertEqual(response.data["tickets_issued"], 0)
        self.assert_refund_due()


class LegacyRouteProtectionTests(APITestCase):
    def setUp(self):
        self.context = build_operational_context()
        self.counter = User.objects.create_user(username="guichet", password="secret", role=User.Role.COUNTER)
        self.seats = list(self.context["trip"].seats.order_by("number"))
        self.ticket = reserve_ticket(
            trip=self.context["trip"], seat=self.seats[0], customer=self.context["client"], passenger_name="Client"
        )
        self.method = self.context["payment_method"]

    def test_anonymous_cannot_use_legacy_sale_routes(self):
        trip = self.context["trip"]
        for prefix in ("/api", "/api/v1"):
            create = self.client.post(
                f"{prefix}/tickets/", {"trip": trip.pk, "seat": self.seats[1].pk, "passenger_name": "X"}, format="json"
            )
            pay = self.client.post(f"{prefix}/tickets/{self.ticket.pk}/pay/", {"payment_method": self.method.pk})
            booking = self.client.post(
                f"{prefix}/bookings/",
                {"trip": trip.pk, "passengers": [{"full_name": "X", "seat": self.seats[1].pk}]},
                format="json",
            )
            self.assertEqual((create.status_code, pay.status_code, booking.status_code), (401, 401, 401), prefix)
        self.assertEqual(Ticket.objects.count(), 1)

    def test_client_cannot_get_ticket_without_verified_payment(self):
        self.client.force_authenticate(self.context["client"])
        response = self.client.post(f"/api/v1/tickets/{self.ticket.pk}/pay/", {"payment_method": self.method.pk})
        self.assertEqual(response.status_code, 400, response.data)
        self.ticket.refresh_from_db()
        self.assertEqual(self.ticket.status, Ticket.Status.HELD)

    def test_client_cannot_pay_ticket_of_another_client(self):
        other = User.objects.create_user(username="autre", password="secret", role=User.Role.CLIENT)
        self.client.force_authenticate(other)
        response = self.client.post(f"/api/v1/tickets/{self.ticket.pk}/pay/", {"payment_method": self.method.pk})
        self.assertEqual(response.status_code, 404)

    def test_controller_cannot_cash_in(self):
        self.client.force_authenticate(self.context["controller"])
        response = self.client.post(f"/api/v1/tickets/{self.ticket.pk}/pay/", {"payment_method": self.method.pk})
        self.assertEqual(response.status_code, 403)

    def test_counter_cashes_in_with_manual_method(self):
        self.client.force_authenticate(self.counter)
        response = self.client.post(f"/api/v1/tickets/{self.ticket.pk}/pay/", {"payment_method": self.method.pk})
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data["ticket"]["status"], Ticket.Status.ISSUED)
        receipt = PaymentReceipt.objects.get()
        self.assertEqual((receipt.source, receipt.recorded_by_id), (PaymentReceipt.Source.COUNTER, self.counter.pk))

    def test_counter_cannot_skip_verification_of_online_method(self):
        fedapay = PaymentMethod.objects.create(code="FEDAPAY", label="FedaPay", active=True)
        self.client.force_authenticate(self.counter)
        response = self.client.post(f"/api/v1/tickets/{self.ticket.pk}/pay/", {"payment_method": fedapay.pk})
        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(PaymentReceipt.objects.count(), 0)


class StaffSurfaceTests(APITestCase):
    SELL = "/api/v1/staff/tickets/sell_counter/"
    VALIDATE = "/api/v1/staff/tickets/validate/"

    def setUp(self):
        self.context = build_operational_context()
        self.counter = User.objects.create_user(username="guichet", password="secret", role=User.Role.COUNTER)
        self.seat = self.context["trip"].seats.order_by("number").first()
        Trip.objects.filter(pk=self.context["trip"].pk).update(departure_at=timezone.now() + timedelta(hours=2))
        self.payload = {
            "trip_id": self.context["trip"].pk,
            "seat_id": self.seat.pk,
            "passenger_name": "Passager Guichet",
            "passenger_phone": "90000000",
            "payment_method": self.context["payment_method"].pk,
        }

    def test_counter_sells_ticket_with_fare_rule_and_transaction(self):
        self.client.force_authenticate(self.counter)
        response = self.client.post(self.SELL, self.payload, format="json")
        self.assertEqual(response.status_code, 201, response.data)
        ticket = Ticket.objects.get(reference=response.data["ticket_reference"])
        fare = self.context["segment_fare"]
        self.assertEqual((ticket.status, ticket.channel, ticket.amount), (Ticket.Status.ISSUED, "COUNTER", fare.amount))
        payment = Transaction.objects.get(ticket=ticket)
        self.assertEqual((payment.status, payment.amount), (Transaction.Status.SUCCEEDED, fare.amount))
        self.assertEqual(PaymentReceipt.objects.get().source, PaymentReceipt.Source.COUNTER)
        self.seat.refresh_from_db()
        self.assertEqual(self.seat.status, Seat.Status.PAID)

    def test_admin_can_sell(self):
        self.client.force_authenticate(self.context["admin"])
        self.assertEqual(self.client.post(self.SELL, self.payload, format="json").status_code, 201)

    def test_other_roles_cannot_sell(self):
        self.assertEqual(self.client.post(self.SELL, self.payload, format="json").status_code, 401)
        for user in (self.context["controller"], self.context["client"]):
            self.client.force_authenticate(user)
            self.assertEqual(self.client.post(self.SELL, self.payload, format="json").status_code, 403)
        self.assertEqual(Ticket.objects.count(), 0)

    def test_taken_seat_is_refused(self):
        self.client.force_authenticate(self.counter)
        self.assertEqual(self.client.post(self.SELL, self.payload, format="json").status_code, 201)
        self.assertEqual(self.client.post(self.SELL, self.payload, format="json").status_code, 400)
        self.assertEqual(Ticket.objects.count(), 1)

    def test_missing_payment_method_is_refused(self):
        self.client.force_authenticate(self.counter)
        payload = {key: value for key, value in self.payload.items() if key != "payment_method"}
        self.assertEqual(self.client.post(self.SELL, payload, format="json").status_code, 400)
        self.assertEqual(Ticket.objects.count(), 0)

    def test_unverified_online_method_leaves_seat_free(self):
        fedapay = PaymentMethod.objects.create(code="FEDAPAY", label="FedaPay", active=True)
        self.client.force_authenticate(self.counter)
        response = self.client.post(self.SELL, {**self.payload, "payment_method": fedapay.pk}, format="json")
        self.assertEqual(response.status_code, 400, response.data)
        self.seat.refresh_from_db()
        self.assertEqual(self.seat.status, Seat.Status.AVAILABLE)
        self.assertEqual(Ticket.objects.count(), 0)

    def _issued_ticket(self):
        self.client.force_authenticate(self.counter)
        response = self.client.post(self.SELL, self.payload, format="json")
        return response.data["qr_token"]

    def test_controller_validates_ticket_once(self):
        qr_token = self._issued_ticket()
        self.client.force_authenticate(self.context["controller"])
        payload = {"qr_token": qr_token, "expected_trip_id": self.context["trip"].pk}
        first = self.client.post(self.VALIDATE, payload, format="json")
        self.assertEqual(first.status_code, 200, first.data)
        self.assertEqual(first.data["ticket"]["status"], Ticket.Status.CHECKED)
        self.assertEqual(self.client.post(self.VALIDATE, payload, format="json").status_code, 400)

    def test_validate_requires_controller_or_admin(self):
        qr_token = self._issued_ticket()
        self.client.force_authenticate(None)
        self.assertEqual(self.client.post(self.VALIDATE, {"qr_token": qr_token}, format="json").status_code, 401)
        for user in (self.counter, self.context["client"]):
            self.client.force_authenticate(user)
            self.assertEqual(self.client.post(self.VALIDATE, {"qr_token": qr_token}, format="json").status_code, 403)

    def test_validate_requires_qr_token(self):
        self.client.force_authenticate(self.context["controller"])
        self.assertEqual(self.client.post(self.VALIDATE, {}, format="json").status_code, 400)

    def test_validate_rejects_ticket_of_another_trip(self):
        qr_token = self._issued_ticket()
        other = Trip.objects.create(
            route=self.context["route"],
            vehicle=self.context["vehicle"],
            departure_at=timezone.now() + timedelta(hours=5),
        )
        self.client.force_authenticate(self.context["controller"])
        response = self.client.post(
            self.VALIDATE, {"qr_token": qr_token, "expected_trip_id": other.pk}, format="json"
        )
        self.assertEqual(response.status_code, 400)


class SeedDemoTests(TestCase):
    @override_settings(DEBUG=False)
    def test_refuses_to_run_outside_debug(self):
        with self.assertRaises(CommandError):
            call_command("seed_demo", stdout=StringIO())
        self.assertEqual(User.objects.count(), 0)

    @override_settings(DEBUG=True, AXIS_ENVIRONMENT="local", AXIS_PAYMENT_SIMULATION=False)
    def test_creates_demo_data_and_is_idempotent(self):
        call_command("seed_demo", stdout=StringIO())
        call_command("seed_demo", stdout=StringIO())
        roles = dict(User.objects.filter(username__startswith="demo_").values_list("username", "role"))
        self.assertEqual(
            roles,
            {"demo_client": "CLIENT", "demo_guichet": "COUNTER", "demo_controleur": "CONTROLLER", "demo_admin": "ADMIN"},
        )
        trips = Trip.objects.filter(note="Voyage DÉMO")
        self.assertTrue(trips.exists())
        self.assertEqual(trips.first().seats.count(), 12)
        self.assertEqual(FareRule.objects.filter(name="Tarif DÉMO").count(), 1)
        self.assertFalse(PaymentMethod.objects.get(code="SIMULATION").active)

    @override_settings(DEBUG=True, AXIS_ENVIRONMENT="")
    def test_refuses_to_run_outside_the_local_environment(self):
        # Debug activé par erreur sur un serveur : la commande refuse quand même, aucune donnée créée.
        for environment in ("", "production", "recette"):
            with self.subTest(environment=environment), override_settings(AXIS_ENVIRONMENT=environment):
                with self.assertRaisesMessage(CommandError, "AXIS_ENVIRONMENT"):
                    call_command("seed_demo", stdout=StringIO())
        self.assertEqual(User.objects.count(), 0)
        self.assertFalse(Trip.objects.exists())

    @override_settings(DEBUG=False)
    def test_ticket_option_also_refuses_outside_debug(self):
        with self.assertRaises(CommandError):
            call_command("seed_demo", with_ticket=True, stdout=StringIO())
        self.assertEqual(Ticket.objects.count(), 0)

    @override_settings(DEBUG=True, AXIS_ENVIRONMENT="local", AXIS_PAYMENT_SIMULATION=False)
    def test_ticket_option_issues_a_ticket_scannable_today(self):
        output = StringIO()
        call_command("seed_demo", with_ticket=True, stdout=output)
        ticket = Ticket.objects.get()
        self.assertEqual(ticket.status, Ticket.Status.ISSUED)
        self.assertIn(ticket.reference, output.getvalue())
        self.assertEqual(timezone.localdate(ticket.trip.departure_at), timezone.localdate())
        self.assertEqual(ticket.trip.note, "Voyage DÉMO")
        self.assertEqual(PaymentReceipt.objects.get().source, PaymentReceipt.Source.COUNTER)
        self.assertEqual(Transaction.objects.get(ticket=ticket).status, Transaction.Status.SUCCEEDED)

        # Le contrôleur DÉMO peut le valider, sans indiquer de voyage.
        from apps.core.services import validate_ticket

        checked, _ = validate_ticket(qr_token=ticket.qr_token, controller=User.objects.get(username="demo_controleur"))
        self.assertEqual(checked.status, Ticket.Status.CHECKED)

        # Une seconde exécution émet un autre billet, sur un autre siège.
        call_command("seed_demo", with_ticket=True, stdout=StringIO())
        self.assertEqual(Ticket.objects.count(), 2)
        self.assertEqual(Ticket.objects.values("seat").distinct().count(), 2)
