from datetime import timedelta
from decimal import Decimal
from unittest import mock

from django.core.management import call_command
from django.test import override_settings
from django.utils import timezone
from rest_framework.test import APITestCase

from apps.core import payments
from apps.core.models import (
    Booking,
    Location,
    Passenger,
    PaymentMethod,
    PaymentReceipt,
    Route,
    RouteStop,
    Seat,
    SystemSetting,
    Ticket,
    Trip,
    User,
    Vehicle,
)
from apps.core.services import release_expired_holds, reserve_booking
from .test_payment_security import FEDAPAY_SETTINGS, FETCH, WEBHOOK_URL, fedapay_transaction, signed_headers, webhook_body

CLIENT_BOOKINGS = "/api/v1/client/bookings/"


@override_settings(**FEDAPAY_SETTINGS)
class ReservationPlacesAttributionTests(APITestCase):
    def setUp(self):
        call_command("load_segment_fares")
        SystemSetting.objects.update_or_create(key="ticket_hold_minutes", defaults={"value": "5"})
        self.fedapay = PaymentMethod.objects.create(code="FEDAPAY", label="FedaPay", active=True)

        Location.objects.update(active=True)
        self.parakou = Location.objects.get(name="Parakou")
        self.save_loc = Location.objects.get(name="Savè")
        self.glazoue = Location.objects.get(name="Glazoué")
        self.dassa = Location.objects.get(name="Dassa")
        self.bohicon = Location.objects.get(name="Bohicon")
        self.cotonou = Location.objects.get(name="Cotonou")

        self.route = Route.objects.create(origin=self.parakou, destination=self.cotonou, active=True)
        for idx, (loc, offset) in enumerate(
            [
                (self.parakou, 0),
                (self.save_loc, 120),
                (self.glazoue, 180),
                (self.dassa, 210),
                (self.bohicon, 300),
                (self.cotonou, 360),
            ],
            start=1,
        ):
            RouteStop.objects.create(route=self.route, location=loc, position=idx, offset_minutes=offset)

        self.vehicle = Vehicle.objects.create(
            name="Bus TEST Yutong",
            registration_number="TEST-888-BJ",
            category=Vehicle.Category.BUS,
            capacity=8,
            seat_configuration=[
                {"label": str(i), "row": (i - 1) // 4 + 1, "column": (i - 1) % 4 + 1}
                for i in range(1, 9)
            ],
        )
        self.trip = Trip.objects.create(
            route=self.route,
            vehicle=self.vehicle,
            departure_at=timezone.now() + timedelta(days=2),
            status=Trip.Status.SCHEDULED,
        )
        for i in range(1, 9):
            Seat.objects.create(
                trip=self.trip,
                number=str(i),
                row=(i - 1) // 4 + 1,
                column=(i - 1) % 4 + 1,
                status=Seat.Status.AVAILABLE,
            )

        self.client1 = User.objects.create_user(
            username="client1_test",
            password="password123",
            first_name="Koffi",
            last_name="TEST",
            phone="97000001",
            role=User.Role.CLIENT,
        )
        self.client2 = User.objects.create_user(
            username="client2_test",
            password="password123",
            first_name="Awa",
            last_name="TEST",
            phone="97000002",
            role=User.Role.CLIENT,
        )
        self.admin = User.objects.create_user(
            username="admin_test",
            password="password123",
            role=User.Role.ADMIN,
        )

    def test_two_clients_targeting_same_seat_returns_exact_french_error(self):
        """Deux clients visant le même siège : le second reçoit 'Cette place vient d'être prise'."""
        seat1 = Seat.objects.get(trip=self.trip, number="1")

        self.client.force_authenticate(self.client1)
        res1 = self.client.post(
            CLIENT_BOOKINGS,
            {
                "trip": self.trip.pk,
                "passengers": [{"full_name": "Koffi TEST", "seat": seat1.pk}],
            },
            format="json",
        )
        self.assertEqual(res1.status_code, 201, res1.data)
        seat1.refresh_from_db()
        self.assertEqual(seat1.status, Seat.Status.HELD)

        self.client.force_authenticate(self.client2)
        res2 = self.client.post(
            CLIENT_BOOKINGS,
            {
                "trip": self.trip.pk,
                "passengers": [{"full_name": "Awa TEST", "seat": seat1.pk}],
            },
            format="json",
        )
        self.assertEqual(res2.status_code, 400)
        self.assertIn("Cette place vient d'être prise", str(res2.data))

    def test_hold_duration_and_expiration_releases_seats(self):
        """La retenue dure ticket_hold_minutes et l'expiration libère les sièges."""
        self.client.force_authenticate(self.client1)
        res = self.client.post(
            CLIENT_BOOKINGS,
            {
                "trip": self.trip.pk,
                "passengers": [{"full_name": "Koffi TEST"}],
            },
            format="json",
        )
        self.assertEqual(res.status_code, 201, res.data)
        booking = Booking.objects.get(pk=res.data["id"])
        delta = booking.reservation_expires_at - timezone.now()
        self.assertTrue(timedelta(minutes=4) < delta <= timedelta(minutes=5, seconds=5))

        seat = booking.tickets.first().seat
        self.assertEqual(seat.status, Seat.Status.HELD)

        # Expiration
        past = timezone.now() - timedelta(seconds=10)
        Booking.objects.filter(pk=booking.pk).update(reservation_expires_at=past)
        Ticket.objects.filter(booking=booking).update(reservation_expires_at=past)
        released = release_expired_holds()
        self.assertEqual(released, 1)

        booking.refresh_from_db()
        seat.refresh_from_db()
        self.assertEqual(booking.status, Booking.Status.EXPIRED)
        self.assertEqual(booking.client_status_display, "Expirée")
        self.assertEqual(seat.status, Seat.Status.AVAILABLE)

    def test_automatic_grouping_side_by_side_and_fallback_smallest_number(self):
        """
        Places non choisies : groupées côte à côte si possible (ex. sièges 3 et 4 si le 1 est pris),
        sinon par plus petit numéro (ex. sièges 2 et 6 si seuls 2, 6, 8 sont libres).
        """
        # Siège 1 occupé : sur la rangée 1 ([1,2] | [3,4]), le siège 2 est seul à gauche,
        # mais les sièges 3 et 4 sont côte à côte à droite.
        Seat.objects.filter(trip=self.trip, number="1").update(status=Seat.Status.PAID)

        booking, _ = reserve_booking(
            trip=self.trip,
            customer=self.client1,
            passengers=[
                {"full_name": "Passager A"},
                {"full_name": "Passager B"},
            ],
        )
        assigned_numbers = sorted(t.seat.number for t in booking.tickets.all())
        self.assertEqual(assigned_numbers, ["3", "4"])

        # Forçons maintenant uniquement des sièges isolés libres : 2 et 6 (en occupant 3, 4, 5, 7, 8)
        Seat.objects.filter(trip=self.trip, number__in=["5", "7", "8"]).update(status=Seat.Status.PAID)
        booking2, _ = reserve_booking(
            trip=self.trip,
            customer=self.client2,
            passengers=[
                {"full_name": "Passager C"},
                {"full_name": "Passager D"},
            ],
        )
        assigned_fallback = sorted(t.seat.number for t in booking2.tickets.all())
        self.assertEqual(assigned_fallback, ["2", "6"])

    def test_multiple_passengers_optional_seat_choice_and_summary_labels(self):
        """
        Plusieurs passagers : choix du siège facultatif.
        Avant paiement : 'préférence' pour les places choisies, 'Places attribuées après paiement' pour les automatiques.
        Après paiement : le siège devient PAID définitivement et le numéro s'affiche sur le billet.
        """
        seat5 = Seat.objects.get(trip=self.trip, number="5")
        self.client.force_authenticate(self.client1)
        res = self.client.post(
            CLIENT_BOOKINGS,
            {
                "trip": self.trip.pk,
                "passengers": [
                    {"full_name": "Koffi TEST", "seat": seat5.pk},
                    {"full_name": "Enfant TEST", "passenger_type": Passenger.Type.CHILD},
                ],
            },
            format="json",
        )
        self.assertEqual(res.status_code, 201, res.data)
        tickets_data = res.data["tickets"]
        self.assertEqual(len(tickets_data), 2)

        by_name = {t["passenger_name"]: t for t in tickets_data}
        self.assertTrue(by_name["Koffi TEST"]["seat_preference"])
        self.assertIn("préférence", by_name["Koffi TEST"]["seat_summary_label"].lower())

        self.assertFalse(by_name["Enfant TEST"]["seat_preference"])
        self.assertEqual(by_name["Enfant TEST"]["seat_summary_label"], "Places attribuées après paiement")

        # Paiement confirmé : les sièges deviennent PAID définitivement et le numéro apparaît sur chaque billet
        booking = Booking.objects.get(pk=res.data["id"])
        with mock.patch(FETCH, return_value=fedapay_transaction(booking, transaction_id="5001")):
            pay_res = self.client.post(
                f"{CLIENT_BOOKINGS}{booking.pk}/pay/",
                {"payment_method": self.fedapay.pk, "external_reference": "5001"},
                format="json",
            )
        self.assertEqual(pay_res.status_code, 200, pay_res.data)
        paid_tickets = pay_res.data["booking"]["tickets"]
        for t in paid_tickets:
            self.assertEqual(t["status"], Ticket.Status.ISSUED)
            self.assertTrue(t["seat_detail"]["number"])
            self.assertEqual(t["seat_summary_label"], f"Siège {t['seat_detail']['number']}")
            self.assertEqual(Seat.objects.get(pk=t["seat"]).status, Seat.Status.PAID)

    def test_late_payment_when_original_seats_still_free_reclaims_them(self):
        """
        Paiement tardif (cas 1 - places libres) : la retenue a expiré et les places ont été libérées,
        mais personne ne les a prises -> le serveur reprend les mêmes places et émet les billets.
        """
        seat1 = Seat.objects.get(trip=self.trip, number="1")
        seat2 = Seat.objects.get(trip=self.trip, number="2")
        booking, _ = reserve_booking(
            trip=self.trip,
            customer=self.client1,
            passengers=[
                {"full_name": "Koffi TEST", "seat": seat1},
                {"full_name": "Awa TEST", "seat": seat2},
            ],
        )
        past = timezone.now() - timedelta(minutes=2)
        Booking.objects.filter(pk=booking.pk).update(reservation_expires_at=past)
        Ticket.objects.filter(booking=booking).update(reservation_expires_at=past)
        release_expired_holds()

        booking.refresh_from_db()
        seat1.refresh_from_db()
        seat2.refresh_from_db()
        self.assertEqual(booking.status, Booking.Status.EXPIRED)
        self.assertEqual(seat1.status, Seat.Status.AVAILABLE)
        self.assertEqual(seat2.status, Seat.Status.AVAILABLE)

        self.client.force_authenticate(self.client1)
        with mock.patch(FETCH, return_value=fedapay_transaction(booking, transaction_id="6001")):
            res = self.client.post(
                f"{CLIENT_BOOKINGS}{booking.pk}/pay/",
                {"payment_method": self.fedapay.pk, "external_reference": "6001"},
                format="json",
            )
        self.assertEqual(res.status_code, 200, res.data)
        booking.refresh_from_db()
        seat1.refresh_from_db()
        seat2.refresh_from_db()
        self.assertEqual(booking.status, Booking.Status.CONFIRMED)
        self.assertEqual((seat1.status, seat2.status), (Seat.Status.PAID, Seat.Status.PAID))
        self.assertEqual(
            sorted(booking.tickets.filter(status=Ticket.Status.ISSUED).values_list("seat__number", flat=True)),
            ["1", "2"],
        )
        self.assertFalse(PaymentReceipt.objects.get(booking=booking).refund_due)

    def test_late_payment_when_original_seats_taken_assigns_other_free_seats(self):
        """
        Paiement tardif (cas 2 - places prises) : la retenue a expiré et les places 1 et 2 ont été prises
        par un autre voyageur, mais d'autres places sont libres sur le voyage -> réattribution et émission.
        """
        seat1 = Seat.objects.get(trip=self.trip, number="1")
        seat2 = Seat.objects.get(trip=self.trip, number="2")
        booking, _ = reserve_booking(
            trip=self.trip,
            customer=self.client1,
            passengers=[
                {"full_name": "Koffi TEST", "seat": seat1},
                {"full_name": "Awa TEST", "seat": seat2},
            ],
        )
        past = timezone.now() - timedelta(minutes=2)
        Booking.objects.filter(pk=booking.pk).update(reservation_expires_at=past)
        Ticket.objects.filter(booking=booking).update(reservation_expires_at=past)
        release_expired_holds()

        # Un autre client réserve et occupe les sièges 1 et 2
        other_booking, _ = reserve_booking(
            trip=self.trip,
            customer=self.client2,
            passengers=[
                {"full_name": "Autre 1", "seat": seat1},
                {"full_name": "Autre 2", "seat": seat2},
            ],
        )
        self.assertEqual(other_booking.status, Booking.Status.HELD)

        # Le paiement de la 1re réservation arrive (via webhook FedaPay)
        body = webhook_body("6002")
        with mock.patch(FETCH, return_value=fedapay_transaction(booking, transaction_id="6002")):
            res = self.client.post(WEBHOOK_URL, data=body, content_type="application/json", **signed_headers(body))
        self.assertEqual(res.status_code, 200, res.data)

        booking.refresh_from_db()
        self.assertEqual(booking.status, Booking.Status.CONFIRMED)
        new_seat_numbers = sorted(
            booking.tickets.filter(status=Ticket.Status.ISSUED).values_list("seat__number", flat=True)
        )
        # Les sièges 3 et 4 (côte à côte libres) ont été attribués
        self.assertEqual(new_seat_numbers, ["3", "4"])
        self.assertFalse(PaymentReceipt.objects.get(booking=booking).refund_due)

    def test_late_payment_when_not_enough_free_seats_marks_paid_unavailable_and_visible_in_admin(self):
        """
        Paiement tardif (cas 3 - plus assez de places) : la retenue a expiré et il ne reste qu'une seule place
        libre pour une réservation de 2 passagers -> marquée REFUND_DUE ('Payée, places indisponibles'),
        trace du paiement conservée, et visible dans l'admin.
        """
        seat1 = Seat.objects.get(trip=self.trip, number="1")
        seat2 = Seat.objects.get(trip=self.trip, number="2")
        booking, _ = reserve_booking(
            trip=self.trip,
            customer=self.client1,
            passengers=[
                {"full_name": "Koffi TEST", "seat": seat1},
                {"full_name": "Awa TEST", "seat": seat2},
            ],
        )
        past = timezone.now() - timedelta(minutes=2)
        Booking.objects.filter(pk=booking.pk).update(reservation_expires_at=past)
        Ticket.objects.filter(booking=booking).update(reservation_expires_at=past)
        release_expired_holds()

        # 7 sièges sur 8 sont vendus (il ne reste que le siège 8 libre, insuffisant pour 2 passagers)
        Seat.objects.filter(trip=self.trip, number__in=["1", "2", "3", "4", "5", "6", "7"]).update(
            status=Seat.Status.PAID
        )

        self.client.force_authenticate(self.client1)
        with mock.patch(FETCH, return_value=fedapay_transaction(booking, transaction_id="6003")):
            res = self.client.post(
                f"{CLIENT_BOOKINGS}{booking.pk}/pay/",
                {"payment_method": self.fedapay.pk, "external_reference": "6003"},
                format="json",
            )
        self.assertEqual(res.status_code, 409, res.data)
        self.assertTrue(res.data["refund_due"])

        booking.refresh_from_db()
        self.assertEqual(booking.status, Booking.Status.REFUND_DUE)
        self.assertEqual(booking.client_status_display, "Payée, places indisponibles")
        receipt = PaymentReceipt.objects.get(booking=booking)
        self.assertTrue(receipt.refund_due)
        self.assertEqual(receipt.amount, Decimal("15000.00"))

        # Visible dans l'admin via /api/v1/bookings/?status=REFUND_DUE
        self.client.force_authenticate(self.admin)
        admin_res = self.client.get("/api/v1/bookings/?status=REFUND_DUE")
        self.assertEqual(admin_res.status_code, 200)
        results = admin_res.data.get("results", admin_res.data)
        self.assertEqual(len(results), 1)
        self.assertEqual(results[0]["reference"], booking.reference)
        self.assertEqual(results[0]["client_status_display"], "Payée, places indisponibles")

    def test_segment_3500_and_full_trip_7500_prices_unchanged(self):
        """Aucune régression sur les prix : Parakou -> Savè = 3500 FCFA, Parakou -> Cotonou = 7500 FCFA."""
        self.client.force_authenticate(self.client1)

        # Tronçon Parakou -> Savè (2 passagers sans choix de siège = 2 x 3500 = 7000 FCFA)
        res_seg = self.client.post(
            CLIENT_BOOKINGS,
            {
                "trip": self.trip.pk,
                "origin": str(self.parakou.pk),
                "destination": str(self.save_loc.pk),
                "passengers": [
                    {"full_name": "Passager 1"},
                    {"full_name": "Passager 2"},
                ],
            },
            format="json",
        )
        self.assertEqual(res_seg.status_code, 201, res_seg.data)
        self.assertEqual(Decimal(str(res_seg.data["amount"])), Decimal("7000.00"))
        for t in res_seg.data["tickets"]:
            self.assertEqual(Decimal(str(t["amount"])), Decimal("3500.00"))

        # Trajet complet Parakou -> Cotonou (1 passager sans choix de siège = 7500 FCFA)
        res_full = self.client.post(
            CLIENT_BOOKINGS,
            {
                "trip": self.trip.pk,
                "origin": str(self.parakou.pk),
                "destination": str(self.cotonou.pk),
                "passengers": [{"full_name": "Passager 3"}],
            },
            format="json",
        )
        self.assertEqual(res_full.status_code, 201, res_full.data)
        self.assertEqual(Decimal(str(res_full.data["amount"])), Decimal("7500.00"))
        self.assertEqual(Decimal(str(res_full.data["tickets"][0]["amount"])), Decimal("7500.00"))

    def test_cancel_pending_booking_and_client_my_bookings_list(self):
        """
        'Mes réservations' (/api/v1/client/bookings/mine/) retourne les réservations du client connecté
        et l'annulation d'une réservation en attente libère immédiatement les places.
        """
        self.client.force_authenticate(self.client1)
        res = self.client.post(
            CLIENT_BOOKINGS,
            {
                "trip": self.trip.pk,
                "passengers": [{"full_name": "Koffi TEST"}, {"full_name": "Awa TEST"}],
            },
            format="json",
        )
        self.assertEqual(res.status_code, 201, res.data)
        booking_id = res.data["id"]

        mine = self.client.get(f"{CLIENT_BOOKINGS}mine/")
        self.assertEqual(mine.status_code, 200)
        self.assertEqual(len(mine.data), 1)
        self.assertEqual(mine.data[0]["id"], booking_id)
        self.assertEqual(mine.data[0]["client_status_display"], "En attente de paiement")

        # Annulation
        cancel_res = self.client.post(f"{CLIENT_BOOKINGS}{booking_id}/cancel/")
        self.assertEqual(cancel_res.status_code, 200, cancel_res.data)
        self.assertEqual(cancel_res.data["status"], Booking.Status.CANCELLED)
        self.assertEqual(cancel_res.data["client_status_display"], "Annulée")

        # Toutes les places du voyage sont redevenues AVAILABLE
        self.assertEqual(Seat.objects.filter(trip=self.trip, status=Seat.Status.AVAILABLE).count(), 8)
