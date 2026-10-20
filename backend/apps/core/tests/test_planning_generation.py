from datetime import datetime, time, timedelta

from django.utils import timezone
from rest_framework.test import APITestCase

from apps.core.models import Route, Trip, User, Vehicle

from .factories import build_operational_context

GENERATE = "/api/v1/trips/generate/"


class AlternatingPlanningTests(APITestCase):
    """Planning quotidien à heure fixe, en sens alterné, généré par l'administrateur."""

    def setUp(self):
        self.context = build_operational_context()
        self.route = self.context["route"]
        self.reverse = Route.objects.create(origin=self.route.destination, destination=self.route.origin)
        self.bus = self.context["vehicle"]
        self.tomorrow = timezone.localdate() + timedelta(days=1)
        self.client.force_authenticate(self.context["admin"])

    def generate(self, **overrides):
        payload = {
            "route": self.route.pk,
            "vehicle": self.bus.pk,
            "start_date": self.tomorrow.isoformat(),
            "days": 4,
            "departure_time": "09:00",
            **overrides,
        }
        return self.client.post(GENERATE, payload, format="json")

    def generated(self):
        return list(Trip.objects.filter(departure_at__date__gte=self.tomorrow).order_by("departure_at"))

    def at(self, day, hour):
        return timezone.make_aware(datetime.combine(day, time(hour, 0)))

    def test_one_departure_a_day_at_nine_alternating_direction(self):
        response = self.generate()
        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(response.data["created"], 4)
        trips = self.generated()
        self.assertEqual([trip.route_id for trip in trips], [self.route.pk, self.reverse.pk, self.route.pk, self.reverse.pk])
        for index, trip in enumerate(trips):
            local = timezone.localtime(trip.departure_at)
            self.assertEqual(local.date(), self.tomorrow + timedelta(days=index))
            self.assertEqual(local.time(), time(9, 0))
            self.assertIsNone(trip.arrival_at)
            self.assertEqual(trip.status, Trip.Status.SCHEDULED)
            self.assertEqual(trip.seats.count(), self.bus.capacity)

    def test_running_it_twice_creates_no_duplicate(self):
        self.generate()
        response = self.generate()
        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(response.data["created"], 0)
        self.assertEqual(len(response.data["skipped"]), 4)
        self.assertEqual(len(self.generated()), 4)

    def test_existing_departure_is_kept_and_its_day_skipped(self):
        second_day = self.tomorrow + timedelta(days=1)
        existing = Trip.objects.create(route=self.reverse, vehicle=self.bus, departure_at=self.at(second_day, 15))
        response = self.generate(days=3)
        self.assertEqual(response.data["created"], 2)
        self.assertEqual(
            response.data["skipped"], [{"date": second_day.isoformat(), "reason": "ce véhicule a déjà un départ ce jour-là"}]
        )
        existing.refresh_from_db()
        self.assertEqual(timezone.localtime(existing.departure_at).time(), time(15, 0))
        # Le sens suit le rang du jour : le 3e jour reprend le sens du 1er.
        third = Trip.objects.get(departure_at__date=self.tomorrow + timedelta(days=2))
        self.assertEqual(third.route_id, self.route.pk)

    def test_cancelled_departure_does_not_block_its_day(self):
        Trip.objects.create(
            route=self.route, vehicle=self.bus, status=Trip.Status.CANCELLED, departure_at=self.at(self.tomorrow, 9)
        )
        self.assertEqual(self.generate(days=1).data["created"], 1)

    def test_hour_already_passed_today_is_skipped(self):
        response = self.generate(start_date=timezone.localdate().isoformat(), days=1, departure_time="00:00")
        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(response.data["created"], 0)
        self.assertEqual(response.data["skipped"][0]["reason"], "heure déjà passée")

    def test_clear_errors_and_nothing_created(self):
        no_capacity = Vehicle.objects.create(category=Vehicle.Category.BUS, name="TEST sans capacité")
        cases = [
            ({"vehicle": no_capacity.pk}, "capacité"),
            ({"days": 0}, "entre 1 et 90"),
            ({"days": 91}, "entre 1 et 90"),
            ({"start_date": (timezone.localdate() - timedelta(days=1)).isoformat()}, "passée"),
            ({"start_date": "19/10/2026"}, "Date de début invalide"),
            ({"departure_time": "9h"}, "Heure de départ invalide"),
            ({"route": 999999}, "parcours du premier jour"),
        ]
        for overrides, expected in cases:
            with self.subTest(overrides=overrides):
                response = self.generate(**overrides)
                self.assertEqual(response.status_code, 400, response.data)
                self.assertIn(expected, str(response.data))
        self.reverse.delete()
        response = self.generate()
        self.assertEqual(response.status_code, 400)
        self.assertIn("parcours inverse", str(response.data))
        self.assertEqual(self.generated(), [])

    def test_only_admin_can_generate(self):
        counter = User.objects.create_user(username="guichet", password="secret", role=User.Role.COUNTER)
        for user in (self.context["client"], counter, self.context["controller"]):
            self.client.force_authenticate(user)
            self.assertEqual(self.generate().status_code, 403, user.role)
        self.client.force_authenticate(None)
        self.assertEqual(self.generate().status_code, 401)
        self.assertEqual(self.generated(), [])
