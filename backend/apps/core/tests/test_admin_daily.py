"""Admin au jour le jour : tableau de bord du jour, bloc « À traiter », filtres jour / période / statut des listes."""
from datetime import datetime, time, timedelta
from decimal import Decimal

from django.utils import timezone
from rest_framework.test import APITestCase

from apps.core.models import Parcel, RentalBooking, Ticket, Vehicle

from .factories import build_operational_context
from .test_payment_security import make_booking


def local_noon(day):
    return timezone.make_aware(datetime.combine(day, time(12)), timezone.get_current_timezone())


class AdminDailyTests(APITestCase):
    def setUp(self):
        self.context = build_operational_context()
        self.today = timezone.localdate()
        self.yesterday = self.today - timedelta(days=1)
        self.trip = self.context["trip"]
        self.trip.departure_at = local_noon(self.today)
        self.trip.save(update_fields=["departure_at"])
        route = self.trip.route

        def parcel(label, **extra):
            return Parcel.objects.create(
                sender_name=f"Expéditeur {label} TEST", sender_phone="0100000009", recipient_name="Destinataire TEST",
                recipient_phone="0100000008", origin=route.origin, destination=route.destination,
                description="Carton TEST", **extra,
            )

        self.departing = parcel("départ", trip=self.trip)
        self.unassigned_today = parcel("sans départ")
        self.old_waiting = parcel("en attente")
        Parcel.objects.filter(pk=self.old_waiting.pk).update(
            status=Parcel.Status.READY_FOR_PICKUP, created_at=local_noon(self.yesterday - timedelta(days=5))
        )
        car = Vehicle.objects.create(category=Vehicle.Category.RENTAL, name="TEST voiture", capacity=4, rental_daily_rate=Decimal("20000"))
        start = local_noon(self.yesterday - timedelta(days=3))
        self.active_rental = RentalBooking.objects.create(
            vehicle=car, customer=self.context["client"], starts_at=start, ends_at=start + timedelta(days=2),
            status=RentalBooking.Status.ACTIVE,
        )
        self.client.force_authenticate(self.context["admin"])

    def test_dashboard_parcels_of_the_day_and_registered_counter(self):
        data = self.client.get("/api/v1/dashboard/").json()
        self.assertEqual(data["parcels_day"], {"departing": 1, "registered": 2})

    def test_to_handle_shows_old_items_whatever_the_day(self):
        block = self.client.get("/api/v1/dashboard/").json()["to_handle"]
        self.assertEqual([row["id"] for row in block["parcels_awaiting_pickup"]], [self.old_waiting.id])
        self.assertEqual(block["parcels_awaiting_pickup_count"], 1)
        self.assertEqual([row["id"] for row in block["rentals_active"]], [self.active_rental.id])
        self.assertEqual(block["rentals_active_count"], 1)
        self.assertEqual(block["rentals_requested_count"], 0)

    def test_to_handle_keeps_requested_rentals(self):
        start = timezone.now() + timedelta(days=30)
        requested = RentalBooking.objects.create(
            vehicle=self.active_rental.vehicle, customer=self.context["client"], starts_at=start, ends_at=start + timedelta(days=1),
        )
        block = self.client.get("/api/v1/dashboard/").json()["to_handle"]
        self.assertEqual([row["id"] for row in block["rentals_requested"]], [requested.id])

    def test_parcel_list_by_day_all_days_and_status(self):
        day = self.client.get("/api/v1/parcels/", {"start": self.today.isoformat()}).json()["results"]
        self.assertEqual({row["id"] for row in day}, {self.departing.id, self.unassigned_today.id})
        every = self.client.get("/api/v1/parcels/").json()["results"]
        self.assertEqual(len(every), 3)
        ready = self.client.get("/api/v1/parcels/", {"status": "READY_FOR_PICKUP"}).json()["results"]
        self.assertEqual([row["id"] for row in ready], [self.old_waiting.id])
        self.assertEqual(self.client.get("/api/v1/parcels/", {"status": "TEST"}).status_code, 400)

    def test_ticket_list_by_departure_day_and_period(self):
        # On réserve sur un départ futur, puis on le ramène à aujourd'hui (la réservation d'un départ passé est refusée).
        type(self.trip).objects.filter(pk=self.trip.pk).update(departure_at=timezone.now() + timedelta(days=1))
        ticket = make_booking(self.context, customer=self.context["client"], seats=1).tickets.get()
        type(self.trip).objects.filter(pk=self.trip.pk).update(departure_at=local_noon(self.today))
        today = self.client.get("/api/v1/tickets/", {"start": self.today.isoformat()}).json()["results"]
        self.assertIn(ticket.id, [row["id"] for row in today])
        before = self.client.get("/api/v1/tickets/", {"start": (self.yesterday - timedelta(days=2)).isoformat(), "end": self.yesterday.isoformat()}).json()["results"]
        self.assertEqual(before, [])
        status = self.client.get("/api/v1/tickets/", {"status": Ticket.Status.CANCELLED}).json()["results"]
        self.assertNotIn(ticket.id, [row["id"] for row in status])

    def test_rental_list_by_day_keeps_rentals_running_that_day(self):
        inside = (self.yesterday - timedelta(days=2)).isoformat()
        self.assertEqual([r["id"] for r in self.client.get("/api/v1/rentals/", {"start": inside}).json()["results"]], [self.active_rental.id])
        self.assertEqual(self.client.get("/api/v1/rentals/", {"start": self.today.isoformat()}).json()["results"], [])

    def test_bad_dates_are_refused_in_french(self):
        response = self.client.get("/api/v1/parcels/", {"start": "hier"})
        self.assertEqual(response.status_code, 400)
        self.assertIn("AAAA-MM-JJ", str(response.json()))
