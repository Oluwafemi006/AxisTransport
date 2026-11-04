"""Report d'un billet non scanné (délai réglé dans /admin), recherche et annulation par l'admin, annulation de colis."""
from datetime import timedelta

from django.core.exceptions import ValidationError
from django.utils import timezone
from rest_framework.test import APITestCase

from apps.core.models import Parcel, SystemSetting, Ticket, Trip, User
from apps.core.payments import settle_ticket_payment
from apps.core.services import generate_trip_seats, reserve_ticket, validate_ticket

from .factories import build_operational_context


class TicketReportTests(APITestCase):
    def setUp(self):
        self.context = build_operational_context()
        trip = self.context["trip"]
        held = reserve_ticket(trip=trip, seat=trip.seats.first(), customer=self.context["client"],
                              passenger_name="Passager TEST")
        self.ticket = settle_ticket_payment(
            held, payment_method=self.context["payment_method"], actor=self.context["admin"]
        ).target
        # Départ d'hier, billet jamais scanné.
        Trip.objects.filter(pk=trip.pk).update(departure_at=timezone.now() - timedelta(days=1))
        self.today_trip = Trip.objects.create(
            route=trip.route, vehicle=self.context["vehicle"], departure_at=timezone.now() + timedelta(hours=1)
        )
        generate_trip_seats(self.today_trip)

    def scan(self, expected_trip=None):
        return validate_ticket(qr_token=self.ticket.qr_token, controller=self.context["controller"],
                               expected_trip=expected_trip)

    def test_without_setting_a_past_ticket_is_refused(self):
        with self.assertRaises(ValidationError):
            self.scan()

    def test_within_delay_the_ticket_is_accepted_once(self):
        SystemSetting.objects.create(key="ticket_report_days", value=2)
        ticket, control = self.scan(self.today_trip)
        self.assertEqual(ticket.status, Ticket.Status.CHECKED)
        self.assertIn("reporté", control.note)
        with self.assertRaises(ValidationError):
            self.scan(self.today_trip)

    def test_beyond_delay_the_ticket_is_refused(self):
        SystemSetting.objects.create(key="ticket_report_days", value=0)
        with self.assertRaises(ValidationError):
            self.scan()

    def test_cancelled_ticket_is_never_reported(self):
        SystemSetting.objects.create(key="ticket_report_days", value=5)
        Ticket.objects.filter(pk=self.ticket.pk).update(status=Ticket.Status.CANCELLED)
        with self.assertRaises(ValidationError):
            self.scan()


class AdminTicketAndParcelTests(APITestCase):
    def setUp(self):
        self.context = build_operational_context()
        trip = self.context["trip"]
        self.ticket = reserve_ticket(trip=trip, seat=trip.seats.first(), customer=self.context["client"],
                                     passenger_name="Passager Recherche TEST")
        self.parcel = Parcel.objects.create(
            sender_name="Expéditeur TEST", sender_phone="00000000", recipient_name="Destinataire TEST",
            recipient_phone="11111111", origin=self.context["origin"], destination=self.context["destination"],
            description="Colis TEST",
        )
        self.client.force_authenticate(self.context["admin"])

    def test_admin_searches_by_passenger_name(self):
        rows = self.client.get("/api/v1/tickets/", {"q": "recherche test"}).json()
        rows = rows["results"] if isinstance(rows, dict) else rows
        self.assertEqual([row["id"] for row in rows], [self.ticket.pk])

    def test_manual_cancel_needs_a_reason(self):
        url = f"/api/v1/tickets/{self.ticket.pk}/transition/"
        self.assertEqual(self.client.post(url, {"status": "CANCELLED"}, format="json").status_code, 400)
        self.assertEqual(self.client.post(url, {"status": "CANCELLED", "note": "Doublon TEST"}, format="json").status_code, 200)
        self.ticket.refresh_from_db()
        self.assertEqual(self.ticket.status, Ticket.Status.CANCELLED)

    def test_parcel_cancel_admin_only_with_reason(self):
        url = f"/api/v1/parcels/{self.parcel.pk}/transition/"
        counter = User.objects.create_user(username="guichet-test", password="TEST-pass-123", role=User.Role.COUNTER)
        self.client.force_authenticate(counter)
        self.assertEqual(self.client.post(url, {"status": "CANCELLED", "note": "TEST"}, format="json").status_code, 403)
        self.client.force_authenticate(self.context["admin"])
        self.assertEqual(self.client.post(url, {"status": "CANCELLED"}, format="json").status_code, 400)
        self.assertEqual(self.client.post(url, {"status": "CANCELLED", "note": "Erreur TEST"}, format="json").status_code, 200)
        self.parcel.refresh_from_db()
        self.assertEqual(self.parcel.status, Parcel.Status.CANCELLED)
