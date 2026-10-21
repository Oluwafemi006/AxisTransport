from datetime import timedelta
from decimal import Decimal
from unittest import mock

from django.test import override_settings
from django.utils import timezone
from rest_framework.test import APITestCase

from apps.core import payments
from apps.core.models import (
    Booking,
    FareRule,
    PaymentAttempt,
    PaymentIncident,
    PaymentMethod,
    PaymentReceipt,
    SegmentFare,
    Ticket,
    Transaction,
)

from .factories import build_operational_context
from .test_payment_security import FETCH, FEDAPAY_SETTINGS, WEBHOOK_URL, fedapay_transaction, signed_headers, webhook_body

CREATE = "apps.core.payments._fedapay_create_transaction"
BOOKINGS = "/api/v1/client/bookings/"


def money(value):
    return Decimal(str(value))


@override_settings(**FEDAPAY_SETTINGS)
class FinalPriceTests(APITestCase):
    """
    Décision de la direction : le montant affiché au client est celui qu'il paie. FedaPay reçoit exactement
    le prix du billet (grille par tronçon, trajet complet) ; ses frais sont supportés par l'agence.
    """

    def setUp(self):
        self.context = build_operational_context(trip_date=timezone.localdate() + timedelta(days=1))
        self.trip = self.context["trip"]
        # Taux de frais client non précisé : valeur par défaut.
        self.fedapay = PaymentMethod.objects.create(code="FEDAPAY", label="FedaPay", active=True)

    def set_price(self, amount):
        SegmentFare.objects.filter(pk=self.context["segment_fare"].pk).update(amount=amount)

    def book(self, seat_index=0):
        seat = self.trip.seats.order_by("number")[seat_index]
        response = self.client.post(
            BOOKINGS,
            {"trip": self.trip.pk, "contact_phone": "90000000", "passengers": [{"full_name": "Awa Test", "seat": seat.pk}]},
            format="json",
        )
        self.assertEqual(response.status_code, 201, response.data)
        return Booking.objects.get(pk=response.data["id"]), response.data["guest_access_token"]

    def checkout(self, booking, token, transaction_id):
        created = {"id": transaction_id, "payment_url": "https://paiement.exemple.test/x"}
        with mock.patch(CREATE, return_value=created) as create:
            response = self.client.post(
                f"{BOOKINGS}{booking.pk}/checkout/", {"payment_method": self.fedapay.pk}, format="json", HTTP_X_BOOKING_TOKEN=token
            )
        self.assertEqual(response.status_code, 200, response.data)
        return response, create.call_args.args[0]

    def webhook(self, booking, transaction_id, amount):
        body = webhook_body(str(transaction_id))
        with mock.patch(FETCH, return_value=fedapay_transaction(booking, transaction_id=str(transaction_id), amount=amount)):
            return self.client.post(WEBHOOK_URL, data=body, content_type="application/json", **signed_headers(body))

    def assert_end_to_end(self, price):
        self.set_price(price)
        expected = Decimal(price)

        # Affiché avant toute réservation : prix seul, aucun frais.
        trip = self.client.get(f"/api/v1/client/trips/{self.trip.pk}/").json()
        self.assertEqual(money(trip["current_fare"]["amount"]), expected)
        (quote,) = self.client.get(f"/api/v1/client/trips/{self.trip.pk}/payment-quotes/").json()
        self.assertEqual((money(quote["amount"]), money(quote["fee_amount"]), money(quote["total"])), (expected, 0, expected))

        # Réservation, puis montant envoyé à FedaPay.
        booking, token = self.book()
        self.assertEqual(booking.amount, expected)
        response, payload = self.checkout(booking, token, transaction_id=3000 + price)
        self.assertEqual(payload["amount"], price)
        self.assertEqual(money(response.data["total"]), expected)
        self.assertEqual(PaymentAttempt.objects.get(external_id=str(3000 + price)).amount, expected)

        # Confirmation par le webhook : billet, transaction et reçu au même montant.
        self.assertEqual(self.webhook(booking, 3000 + price, price).status_code, 200)
        ticket = Ticket.objects.get(booking=booking)
        self.assertEqual(ticket.status, Ticket.Status.ISSUED)
        self.assertEqual(ticket.amount, expected)
        self.assertEqual(Transaction.objects.get(ticket=ticket).amount, expected)
        self.assertEqual(PaymentReceipt.objects.get(booking=booking).amount, expected)

    def test_1000_gives_1000_end_to_end(self):
        self.assert_end_to_end(1000)

    def test_7500_gives_7500_end_to_end(self):
        self.assert_end_to_end(7500)

    def test_route_fare_rule_no_longer_sets_the_price(self):
        FareRule.objects.filter(route=self.context["route"]).update(amount=Decimal("9999"))
        self.set_price(7500)
        booking, _ = self.book()
        self.assertEqual(booking.amount, Decimal("7500"))
        self.assertTrue(FareRule.objects.filter(route=self.context["route"]).exists())  # code et données gardés

    def test_old_total_with_fees_is_refused(self):
        # Un paiement au montant de l'ancien calcul (7 500 + 1,8 %) ne correspond plus au montant dû.
        self.set_price(7500)
        booking, token = self.book()
        self.checkout(booking, token, transaction_id=4001)
        self.assertEqual(self.webhook(booking, 4001, 7635).status_code, 200)  # incident enregistré, pas d'émission
        self.assertFalse(Ticket.objects.filter(booking=booking, status=Ticket.Status.ISSUED).exists())
        self.assertFalse(PaymentReceipt.objects.exists())
        self.assertTrue(PaymentIncident.objects.filter(external_id="4001", booking=booking).exists())

    def test_reconciliation_settles_at_the_ticket_price(self):
        self.set_price(7500)
        booking, token = self.book()
        self.checkout(booking, token, transaction_id=4002)
        with mock.patch(FETCH, return_value=fedapay_transaction(booking, transaction_id="4002", amount=7500)):
            counts = payments.reconcile_pending_payments()
        self.assertEqual(counts["settled"], 1)
        receipt = PaymentReceipt.objects.get(booking=booking)
        self.assertEqual((receipt.amount, receipt.source), (Decimal("7500"), PaymentReceipt.Source.RECONCILIATION))

    def test_late_payment_is_marked_refund_due_at_the_ticket_price(self):
        self.set_price(7500)
        booking, token = self.book()
        self.checkout(booking, token, transaction_id=4003)
        Booking.objects.filter(pk=booking.pk).update(reservation_expires_at=timezone.now() - timedelta(minutes=1))
        Ticket.objects.filter(booking=booking).update(reservation_expires_at=timezone.now() - timedelta(minutes=1))
        self.assertEqual(self.webhook(booking, 4003, 7500).status_code, 200)
        booking.refresh_from_db()
        self.assertEqual(booking.status, Booking.Status.REFUND_DUE)
        receipt = PaymentReceipt.objects.get(booking=booking)
        self.assertEqual((receipt.amount, receipt.refund_due), (Decimal("7500"), True))

    def test_existing_booking_keeps_its_sale_price(self):
        self.set_price(7500)
        booking, _ = self.book()
        self.set_price(9000)
        booking.refresh_from_db()
        self.assertEqual(booking.amount, Decimal("7500"))
        self.assertEqual(booking.tickets.get().amount, Decimal("7500"))
        self.assertEqual(payments.amount_due(booking, self.fedapay), Decimal("7500"))
        # Un nouveau billet prend le nouveau prix.
        self.assertEqual(self.book(seat_index=1)[0].amount, Decimal("9000"))

    def test_default_client_fee_is_zero_and_stays_configurable(self):
        self.assertEqual(self.fedapay.fee_percentage, Decimal("0"))
        self.set_price(7500)
        PaymentMethod.objects.filter(pk=self.fedapay.pk).update(fee_percentage=Decimal("1.80"))
        (quote,) = self.client.get(f"/api/v1/client/trips/{self.trip.pk}/payment-quotes/").json()
        self.assertEqual(money(quote["total"]), Decimal("7635"))

    def test_fedapay_payload_amount_is_strictly_net_ticket_price_without_fees(self):
        self.set_price(7500)
        PaymentMethod.objects.filter(pk=self.fedapay.pk).update(fee_percentage=Decimal("1.80"))
        booking, token = self.book()
        response, payload = self.checkout(booking, token, transaction_id=4009)
        self.assertEqual(payload["amount"], 7500)
        self.assertEqual(PaymentAttempt.objects.get(external_id="4009").amount, Decimal("7500"))


class FirstStartTests(APITestCase):
    """Premier démarrage du serveur (procédure VPS) : grille chargée, nouvelles villes invisibles, aucun frais client."""

    def setUp(self):
        from io import StringIO

        from django.core.management import call_command

        call_command("bootstrap_axis", stdout=StringIO())

    def test_grid_is_loaded_with_the_given_prices(self):
        from apps.core.management.commands.load_segment_fares import FARES

        self.assertEqual(
            FARES,
            {
                ("Parakou", "Cotonou"): 7500, ("Parakou", "Porto-Novo"): 7500, ("Parakou", "Kétou"): 6500,
                ("Parakou", "Savè"): 4500, ("Savè", "Cotonou"): 6500, ("Savè", "Porto-Novo"): 6500,
                ("Savè", "Kétou"): 2500, ("Kétou", "Porto-Novo"): 4000, ("Kétou", "Cotonou"): 4000,
                ("Porto-Novo", "Cotonou"): 1500,
            },
        )
        loaded = {(fare.start.location.name, fare.end.location.name): fare.amount for fare in SegmentFare.objects.all()}
        self.assertEqual(loaded, FARES)

    def test_new_cities_stay_invisible_to_clients_while_inactive(self):
        from apps.core.models import Location

        self.assertEqual(
            set(Location.objects.filter(active=False).values_list("name", flat=True)), {"Savè", "Kétou", "Porto-Novo"}
        )
        for url in ("/api/v1/client/locations/", "/api/v1/locations/"):
            body = self.client.get(url).json()
            rows = body["results"] if isinstance(body, dict) else body
            self.assertEqual({row["name"] for row in rows}, {"Cotonou", "Parakou"}, url)

    def test_fedapay_is_created_without_client_fee(self):
        self.assertEqual(PaymentMethod.objects.get(code="FEDAPAY").fee_percentage, Decimal("0"))
