import json
from datetime import datetime, time, timedelta
from decimal import Decimal
from unittest import mock

from django.test import override_settings
from django.utils import timezone
from rest_framework import status
from rest_framework.test import APITestCase

from apps.core import payments
from apps.core.models import (
    Booking,
    LineStop,
    Location,
    PaymentMethod,
    Route,
    RouteStop,
    Seat,
    SegmentFare,
    SegmentFareChange,
    SystemSetting,
    Ticket,
    Trip,
    User,
    Vehicle,
)
from apps.core.payments import settle_booking_payment
from apps.core.services import generate_trip_seats, reserve_booking
from django.core.exceptions import ValidationError

from .test_payment_security import FEDAPAY_SETTINGS

CREATE = "apps.core.payments._fedapay_create_transaction"
FETCH = "apps.core.payments._fedapay_fetch_transaction"
CLIENT_BOOKINGS = "/api/v1/client/bookings/"
STAFF_SELL = "/api/v1/staff/sales/sell/"
TICKETS = "/api/v1/tickets/"


@override_settings(**FEDAPAY_SETTINGS)
class SegmentBookingAndPricingTests(APITestCase):
    """
    Tests complets de vente par tronçon :
    - Parakou → Savè = 4 500 FCFA de bout en bout (réservation, montant envoyé à FedaPay, billet)
    - Savè → Cotonou = 6 500 FCFA
    - Dassa → Bohicon = 4 000 FCFA
    - Sens inverse refusé côté serveur (validation du sens du bus)
    - Réservation « trajet complet » existante inchangée
    - Guichet et App (staff sales / tickets)
    - Heure d'escale (avec décalage configuré vs sans décalage)
    """

    def setUp(self):
        # 1. Villes de la ligne
        self.parakou = Location.objects.create(name="Parakou", address="Gare Parakou", active=True)
        self.save = Location.objects.create(name="Savè", address="Carrefour Savè", active=True)
        self.dassa = Location.objects.create(name="Dassa", address="Gare Dassa", active=True)
        self.bohicon = Location.objects.create(name="Bohicon", address="Gare Bohicon", active=True)
        self.cotonou = Location.objects.create(name="Cotonou", address="Gare Cotonou", active=True)

        # 2. LineStop (ordre global de la ligne : Parakou 1, Savè 2, Dassa 3, Bohicon 4, Cotonou 5)
        self.ls_parakou = LineStop.objects.create(location=self.parakou, position=1)
        self.ls_save = LineStop.objects.create(location=self.save, position=2)
        self.ls_dassa = LineStop.objects.create(location=self.dassa, position=3)
        self.ls_bohicon = LineStop.objects.create(location=self.bohicon, position=4)
        self.ls_cotonou = LineStop.objects.create(location=self.cotonou, position=5)

        # 3. Grille tarifaire par tronçon
        def _add_fare(start_ls, end_ls, amount):
            fare = SegmentFare.objects.create(start=start_ls, end=end_ls, amount=amount)
            SegmentFareChange.objects.create(fare=fare, old_amount=None, new_amount=amount)
            return fare

        _add_fare(self.ls_parakou, self.ls_cotonou, 7500)
        _add_fare(self.ls_parakou, self.ls_save, 4500)
        _add_fare(self.ls_save, self.ls_cotonou, 6500)
        _add_fare(self.ls_save, self.ls_bohicon, 6500)
        _add_fare(self.ls_save, self.ls_dassa, 2500)
        _add_fare(self.ls_dassa, self.ls_bohicon, 4000)
        _add_fare(self.ls_dassa, self.ls_cotonou, 4000)
        _add_fare(self.ls_bohicon, self.ls_cotonou, 1500)

        # 4. Véhicule et Itinéraire descendant (Parakou → Cotonou)
        self.vehicle = Vehicle.objects.create(
            category=Vehicle.Category.BUS,
            name="Yutong Test",
            capacity=10,
            state=Vehicle.State.ACTIVE,
        )
        self.route = Route.objects.create(origin=self.parakou, destination=self.cotonou, active=True)
        # Étapes ordonnées RouteStop avec décalage optionnel
        self.rs_parakou = RouteStop.objects.create(route=self.route, location=self.parakou, position=1, offset_minutes=0)
        self.rs_save = RouteStop.objects.create(route=self.route, location=self.save, position=2, offset_minutes=120)  # +2h
        self.rs_dassa = RouteStop.objects.create(route=self.route, location=self.dassa, position=3, offset_minutes=180)
        self.rs_bohicon = RouteStop.objects.create(route=self.route, location=self.bohicon, position=4, offset_minutes=360)
        self.rs_cotonou = RouteStop.objects.create(route=self.route, location=self.cotonou, position=5, offset_minutes=420)

        # Départ demain à 08:00
        departure = timezone.now().replace(hour=8, minute=0, second=0, microsecond=0) + timedelta(days=1)
        self.trip = Trip.objects.create(
            route=self.route,
            vehicle=self.vehicle,
            departure_at=departure,
            status=Trip.Status.SCHEDULED,
        )
        generate_trip_seats(self.trip)
        self.seats = list(self.trip.seats.order_by("number"))

        # 5. Moyens de paiement et réglages
        SystemSetting.objects.create(key="ticket_hold_minutes", value=15)
        self.fedapay = PaymentMethod.objects.create(code="FEDAPAY", label="FedaPay", active=True, fee_percentage=Decimal("0"))
        self.cash = PaymentMethod.objects.create(code="CASH", label="Espèces", active=True, fee_percentage=Decimal("0"))

        # 6. Utilisateurs
        self.counter_agent = User.objects.create_user(username="agent_guichet", password="secret", role=User.Role.COUNTER)
        self.client_user = User.objects.create_user(username="client_test", password="secret", role=User.Role.CLIENT, phone="97000001")

    # ── 1. Parakou → Savè = 4 500 FCFA de bout en bout ──────────────────────
    def test_parakou_to_save_end_to_end_pricing_fedapay_and_ticket(self):
        """Cas Parakou → Savè = 4 500 de bout en bout (réservation, montant envoyé à FedaPay, billet)."""
        seat = self.seats[0]
        # Devis avant réservation (/client/trips/<id>/payment-quotes/?origin=...&destination=...)
        quote_res = self.client.get(
            f"/api/v1/client/trips/{self.trip.pk}/payment-quotes/?origin={self.parakou.pk}&destination={self.save.pk}"
        )
        self.assertEqual(quote_res.status_code, status.HTTP_200_OK)
        quotes = quote_res.json()
        self.assertEqual(quotes[0]["total"], 4500)

        # Création de la réservation
        book_res = self.client.post(
            CLIENT_BOOKINGS,
            {
                "trip": self.trip.pk,
                "origin": self.parakou.pk,
                "destination": self.save.pk,
                "contact_phone": "97000001",
                "passengers": [{"full_name": "Passager Savè", "phone": "97000001", "seat": seat.pk}],
            },
            format="json",
        )
        self.assertEqual(book_res.status_code, status.HTTP_201_CREATED, book_res.data)
        booking_data = book_res.data
        booking_id = booking_data["id"]
        token = booking_data.get("guest_access_token")

        booking = Booking.objects.get(pk=booking_id)
        self.assertEqual(booking.amount, Decimal("4500.00"))
        self.assertEqual(booking.origin, self.parakou)
        self.assertEqual(booking.destination, self.save)
        self.assertEqual(booking.segment_label, "Parakou → Savè")

        # Paiement FedaPay : le montant envoyé à FedaPay doit être EXACTEMENT 4 500
        fedapay_mock = {"id": 99901, "payment_url": "https://fedapay.test/pay/99901"}
        with mock.patch(CREATE, return_value=fedapay_mock) as mocked_create:
            checkout_res = self.client.post(
                f"{CLIENT_BOOKINGS}{booking_id}/checkout/",
                {"payment_method": self.fedapay.pk},
                format="json",
                HTTP_X_BOOKING_TOKEN=token,
            )
            self.assertEqual(checkout_res.status_code, status.HTTP_200_OK, checkout_res.data)
            # Vérifier l'appel à _fedapay_create_transaction
            mocked_create.assert_called_once()
            called_payload = mocked_create.call_args[0][0]
            self.assertEqual(called_payload["amount"], 4500)
            self.assertEqual(called_payload["currency"], {"iso": "XOF"})

        # Encaissement / Émission du billet
        verified = {
            "id": 99901,
            "status": "approved",
            "amount": 4500,
            "currency": {"iso": "XOF"},
            "custom_metadata": {"booking_id": booking.id},
        }
        with mock.patch(FETCH, return_value=verified):
            settle_booking_payment(booking, payment_method=self.fedapay, actor=None, external_reference="99901")
        booking.refresh_from_db()
        self.assertEqual(booking.status, Booking.Status.CONFIRMED)

        ticket = booking.tickets.first()
        self.assertEqual(ticket.amount, Decimal("4500.00"))
        self.assertEqual(ticket.origin, self.parakou)
        self.assertEqual(ticket.destination, self.save)
        self.assertEqual(ticket.segment_label, "Parakou → Savè")

        # Affichage billet public (/client/tickets/public/<reference>/)
        public_res = self.client.get(f"/api/v1/client/tickets/public/{ticket.reference}/")
        self.assertEqual(public_res.status_code, status.HTTP_200_OK)
        pub_data = public_res.json()
        self.assertEqual(pub_data["origin"], "Parakou")
        self.assertEqual(pub_data["destination"], "Savè")
        self.assertEqual(pub_data["amount"], "4500.00")
        self.assertEqual(pub_data["print_info"]["segment_label"], "Parakou → Savè")
        self.assertEqual(pub_data["print_info"]["price_incl_tax"], 4500)

    # ── 2. Savè → Cotonou = 6 500 FCFA ──────────────────────────────────────
    def test_save_to_cotonou_pricing_and_booking(self):
        """Savè → Cotonou : vendu à bord par le personnel ; refusé en ligne (montée au terminus seulement)."""
        seat = self.seats[1]
        online = self.client.post(
            CLIENT_BOOKINGS,
            {
                "trip": self.trip.pk,
                "origin": self.save.pk,
                "destination": self.cotonou.pk,
                "contact_phone": "97000002",
                "passengers": [{"full_name": "TEST En ligne", "phone": "97000002", "seat": seat.pk}],
            },
            format="json",
        )
        self.assertEqual(online.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("se fait à bord", str(online.data))
        booking, _ = reserve_booking(
            trip=self.trip,
            passengers=[{"full_name": "TEST À bord", "seat": seat}],
            origin=self.save,
            destination=self.cotonou,
            channel=Ticket.Channel.COUNTER,
        )
        self.assertEqual(booking.amount, Decimal("6500.00"))
        self.assertEqual(booking.origin, self.save)
        self.assertEqual(booking.destination, self.cotonou)
        self.assertEqual(booking.segment_label, "Savè → Cotonou")

    def test_inactive_city_refuses_new_sales_and_keeps_issued_tickets(self):
        """Ville retirée : plus de nouvelle vente vers ou depuis elle ; le billet déjà vendu ne change pas."""
        booking, _ = reserve_booking(
            trip=self.trip, passengers=[{"full_name": "TEST Avant", "seat": self.seats[0]}],
            origin=self.dassa, destination=self.cotonou,
        )
        Location.objects.filter(pk=self.dassa.pk).update(active=False)
        for origin, destination in ((self.dassa, self.cotonou), (self.parakou, self.dassa)):
            with self.assertRaisesMessage(ValidationError, "Cette ville n'est plus desservie"):
                reserve_booking(
                    trip=self.trip, passengers=[{"full_name": "TEST Après", "seat": self.seats[1]}],
                    origin=origin, destination=destination,
                )
        booking.refresh_from_db()
        self.assertEqual(booking.origin, self.dassa)
        self.assertEqual(booking.tickets.count(), 1)

    # ── 3. Dassa → Bohicon = 4 000 FCFA ──────────────────────────────────
    def test_dassa_to_bohicon_pricing_and_booking(self):
        """Dassa → Bohicon : vendu à bord par le personnel ; refusé en ligne (montée au terminus seulement)."""
        seat = self.seats[2]
        online = self.client.post(
            CLIENT_BOOKINGS,
            {
                "trip": self.trip.pk,
                "origin": self.dassa.pk,
                "destination": self.bohicon.pk,
                "contact_phone": "97000003",
                "passengers": [{"full_name": "TEST En ligne", "phone": "97000003", "seat": seat.pk}],
            },
            format="json",
        )
        self.assertEqual(online.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("se fait à bord", str(online.data))
        booking, _ = reserve_booking(
            trip=self.trip,
            passengers=[{"full_name": "TEST À bord", "seat": seat}],
            origin=self.dassa,
            destination=self.bohicon,
            channel=Ticket.Channel.COUNTER,
        )
        self.assertEqual(booking.amount, Decimal("4000.00"))
        self.assertEqual(booking.origin, self.dassa)
        self.assertEqual(booking.destination, self.bohicon)
        self.assertEqual(booking.segment_label, "Dassa → Bohicon")

    def test_reverse_direction_is_strictly_rejected(self):
        """Sens inverse refusé côté serveur avec message clair en français."""
        seat = self.seats[3]
        # Bus descendant Parakou → Cotonou : Savè vers Parakou est en sens inverse
        res = self.client.post(
            CLIENT_BOOKINGS,
            {
                "trip": self.trip.pk,
                "origin": self.save.pk,
                "destination": self.parakou.pk,
                "contact_phone": "97000004",
                "passengers": [{"full_name": "Sens Inverse", "seat": seat.pk}],
            },
            format="json",
        )
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)
        error_msg = str(res.data)
        self.assertTrue("ne dessert pas le tronçon" in error_msg or "sens" in error_msg)

        # Cotonou vers Savè aussi refusé
        res2 = self.client.post(
            CLIENT_BOOKINGS,
            {
                "trip": self.trip.pk,
                "origin": self.cotonou.pk,
                "destination": self.save.pk,
                "contact_phone": "97000004",
                "passengers": [{"full_name": "Sens Inverse 2", "seat": seat.pk}],
            },
            format="json",
        )
        self.assertEqual(res2.status_code, status.HTTP_400_BAD_REQUEST)

    # ── 5. Réservation « trajet complet » existante inchangée ───────────────
    def test_full_trip_booking_without_origin_destination_unchanged(self):
        """Réservation existante sans origin/dest reste facturée au tarif trajet complet (7 500 FCFA)."""
        seat = self.seats[4]
        res = self.client.post(
            CLIENT_BOOKINGS,
            {
                "trip": self.trip.pk,
                "contact_phone": "97000005",
                "passengers": [{"full_name": "Trajet Complet", "seat": seat.pk}],
            },
            format="json",
        )
        self.assertEqual(res.status_code, status.HTTP_201_CREATED, res.data)
        booking = Booking.objects.get(pk=res.data["id"])
        self.assertEqual(booking.amount, Decimal("7500.00"))
        self.assertEqual(booking.origin, self.parakou)
        self.assertEqual(booking.destination, self.cotonou)
        self.assertEqual(booking.segment_label, "Parakou → Cotonou")

    # ── 6. Guichet et App (Vente personnel) ─────────────────────────────────
    def test_counter_sale_with_segment(self):
        """Vente au guichet avec tronçon (ex: Parakou → Savè à 4 500 FCFA)."""
        self.client.force_authenticate(self.counter_agent)
        seat = self.seats[5]
        res = self.client.post(
            STAFF_SELL,
            {
                "idempotency_key": "SALE-TEST-KEY-0000000000000001",
                "trip": self.trip.pk,
                "seat": seat.pk,
                "passenger_name": "Passager Guichet",
                "passenger_phone": "97000006",
                "payment_method": self.cash.pk,
                "origin": self.parakou.pk,
                "destination": self.save.pk,
            },
            format="json",
        )
        self.assertEqual(res.status_code, status.HTTP_201_CREATED, res.data)
        booking = Booking.objects.get(pk=res.data["booking"]["id"])
        self.assertEqual(booking.amount, Decimal("4500.00"))
        self.assertEqual(booking.segment_label, "Parakou → Savè")
        ticket = booking.tickets.first()
        self.assertEqual(ticket.amount, Decimal("4500.00"))
        self.assertEqual(ticket.segment_label, "Parakou → Savè")

    def test_direct_ticket_creation_with_segment(self):
        """Création directe via /tickets/ avec tronçon."""
        self.client.force_authenticate(self.counter_agent)
        seat = self.seats[6]
        res = self.client.post(
            TICKETS,
            {
                "trip": self.trip.pk,
                "seat": seat.pk,
                "passenger_name": "Direct Ticket",
                "passenger_phone": "97000007",
                "origin": self.parakou.pk,
                "destination": self.save.pk,
            },
            format="json",
        )
        self.assertEqual(res.status_code, status.HTTP_201_CREATED, res.data)
        ticket = Ticket.objects.get(pk=res.data["id"])
        self.assertEqual(ticket.amount, Decimal("4500.00"))
        self.assertEqual(ticket.origin, self.parakou)
        self.assertEqual(ticket.destination, self.save)
        self.assertEqual(ticket.segment_label, "Parakou → Savè")

    # ── 7. Heure d'escale (avec décalage vs sans décalage) ───────────────────
    def test_stop_departure_time_with_configured_offset(self):
        """
        Passager montant à une escale avec décalage configuré (Savè, offset=120 min) :
        affiche heure de départ calculée et libellé 'Départ de Savè'.
        """
        seat = self.seats[7]
        booking, _ = reserve_booking(
            trip=self.trip,
            passengers=[{"full_name": "Passager Escale", "seat": seat}],
            origin=self.save,
            destination=self.cotonou,
        )
        ticket = booking.tickets.first()
        dep_time, dep_label, is_offset = ticket.get_departure_time_and_label()
        self.assertTrue(is_offset)
        self.assertEqual(dep_label, "Départ de Savè")
        self.assertEqual(dep_time, self.trip.departure_at + timedelta(minutes=120))

    def test_stop_departure_time_without_offset_does_not_invent_time(self):
        """
        Passager montant à une escale sans décalage configuré :
        affiche l'heure du terminus libellée 'Départ de Parakou' (aucune heure inventée).
        """
        # On supprime le décalage sur Savè
        self.rs_save.offset_minutes = None
        self.rs_save.save()

        seat = self.seats[8]
        booking, _ = reserve_booking(
            trip=self.trip,
            passengers=[{"full_name": "Passager Sans Offset", "seat": seat}],
            origin=self.save,
            destination=self.cotonou,
        )
        ticket = booking.tickets.first()
        dep_time, dep_label, is_offset = ticket.get_departure_time_and_label()
        self.assertFalse(is_offset)
        self.assertEqual(dep_label, "Départ de Parakou")
        self.assertEqual(dep_time, self.trip.departure_at)
