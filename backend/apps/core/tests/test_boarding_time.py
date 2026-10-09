from datetime import datetime, time, timedelta

from django.utils import timezone
from django.utils.dateparse import parse_datetime
from rest_framework.test import APITestCase

from apps.core.models import SystemSetting, Ticket, Trip
from apps.core.serializers import ControllerTicketSerializer
from apps.core.services import boarding_lead_minutes, boarding_time

from .factories import build_operational_context


class BoardingTimeTests(APITestCase):
    """Heure d'embarquement = départ − boarding_lead_minutes, calculée à chaque réponse."""

    def setUp(self):
        self.context = build_operational_context(trip_date=timezone.localdate() + timedelta(days=1))
        self.trip = self.context["trip"]
        self.ticket = Ticket.objects.create(
            trip=self.trip,
            seat=self.trip.seats.order_by("number").first(),
            passenger_name="Awa Test",
            amount=1000,
            currency="XOF",
            status=Ticket.Status.ISSUED,
            customer=self.context["client"],
        )

    def public_ticket(self):
        response = self.client.get(f"/api/v1/client/tickets/public/{self.ticket.reference}/")
        self.assertEqual(response.status_code, 200)
        return response.json()

    def set_lead(self, value):
        SystemSetting.objects.update_or_create(key="boarding_lead_minutes", defaults={"value": value})

    def test_default_is_thirty_minutes_before_departure(self):
        data = self.public_ticket()
        self.assertEqual(parse_datetime(data["departure_at"]), self.trip.departure_at)
        self.assertEqual(parse_datetime(data["boarding_at"]), self.trip.departure_at - timedelta(minutes=30))

    def test_boarding_time_crosses_midnight(self):
        # Départ à 00:10 : l'embarquement tombe la veille à 23:40.
        tomorrow = timezone.localdate() + timedelta(days=1)
        departure = timezone.make_aware(datetime.combine(tomorrow, time(0, 10)))
        Trip.objects.filter(pk=self.trip.pk).update(departure_at=departure, arrival_at=None)
        boarding = timezone.localtime(parse_datetime(self.public_ticket()["boarding_at"]))
        self.assertEqual(boarding.date(), tomorrow - timedelta(days=1))
        self.assertEqual((boarding.hour, boarding.minute), (23, 40))

    def test_changed_setting_applies_to_existing_tickets(self):
        self.set_lead(45)
        self.assertEqual(
            parse_datetime(self.public_ticket()["boarding_at"]), self.trip.departure_at - timedelta(minutes=45)
        )
        self.set_lead(0)
        self.assertEqual(parse_datetime(self.public_ticket()["boarding_at"]), self.trip.departure_at)

    def test_invalid_setting_falls_back_to_default(self):
        for value in ("abc", -5, ""):
            self.set_lead(value)
            self.assertEqual(boarding_lead_minutes(), 30)

    def test_boarding_time_follows_a_departure_change(self):
        new_departure = self.trip.departure_at + timedelta(hours=2)
        Trip.objects.filter(pk=self.trip.pk).update(
            departure_at=new_departure, arrival_at=new_departure + timedelta(hours=4)
        )
        self.assertEqual(
            parse_datetime(self.public_ticket()["boarding_at"]), new_departure - timedelta(minutes=30)
        )

    def test_boarding_time_is_not_stored(self):
        for model in (Trip, Ticket):
            self.assertNotIn("boarding_at", [field.name for field in model._meta.get_fields()])
        self.assertEqual(boarding_time(self.trip), self.trip.departure_at - timedelta(minutes=30))

    def test_client_trip_and_ticket_payloads_carry_boarding_time(self):
        expected = self.trip.departure_at - timedelta(minutes=30)
        trips = self.client.get("/api/v1/client/trips/").json()
        trips = trips if isinstance(trips, list) else trips["results"]
        self.assertEqual(parse_datetime(trips[0]["boarding_at"]), expected)
        self.client.force_authenticate(self.context["client"])
        tickets = self.client.get("/api/v1/client/tickets/").json()
        tickets = tickets if isinstance(tickets, list) else tickets["results"]
        self.assertEqual(parse_datetime(tickets[0]["trip_detail"]["boarding_at"]), expected)

    def test_scan_result_carries_boarding_time(self):
        # Le résultat du scan contrôleur renvoie ce sérialiseur.
        data = ControllerTicketSerializer(self.ticket).data
        self.assertEqual(
            parse_datetime(data["trip_detail"]["boarding_at"]), self.trip.departure_at - timedelta(minutes=30)
        )
