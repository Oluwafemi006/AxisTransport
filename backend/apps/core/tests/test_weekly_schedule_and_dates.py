from datetime import datetime, time, timedelta

from django.core.exceptions import ValidationError
from django.core.management import call_command
from django.utils import timezone
from rest_framework.test import APITestCase

from apps.core.models import Location, Route, Trip, User, Vehicle, WeeklySchedule
from apps.core.serializers import TripSerializer
from apps.core.services import generate_trips_from_schedule

from .factories import build_operational_context


class TripDateValidationTests(APITestCase):
    """Validation stricte des dates et heures sur le modèle Trip et les Serializers."""

    def setUp(self):
        self.context = build_operational_context()
        self.route = self.context["route"]
        self.bus = self.context["vehicle"]
        self.today = timezone.localdate() + timedelta(days=2)
        self.client.force_authenticate(self.context["admin"])

    def test_arrival_before_departure_rejected_by_clean(self):
        dep = timezone.make_aware(datetime.combine(self.today, time(10, 0)))
        arr = timezone.make_aware(datetime.combine(self.today, time(8, 0)))
        trip = Trip(route=self.route, vehicle=self.bus, departure_at=dep, arrival_at=arr)
        with self.assertRaises(ValidationError) as ctx:
            trip.clean()
        self.assertIn("arrival_at", ctx.exception.message_dict)

    def test_arrival_equal_to_departure_rejected_by_clean(self):
        dep = timezone.make_aware(datetime.combine(self.today, time(10, 0)))
        trip = Trip(route=self.route, vehicle=self.bus, departure_at=dep, arrival_at=dep)
        with self.assertRaises(ValidationError) as ctx:
            trip.clean()
        self.assertIn("arrival_at", ctx.exception.message_dict)

    def test_arrival_next_day_rejected_by_clean(self):
        dep = timezone.make_aware(datetime.combine(self.today, time(20, 0)))
        arr = timezone.make_aware(datetime.combine(self.today + timedelta(days=1), time(2, 0)))
        trip = Trip(route=self.route, vehicle=self.bus, departure_at=dep, arrival_at=arr)
        with self.assertRaises(ValidationError) as ctx:
            trip.clean()
        self.assertIn("arrival_at", ctx.exception.message_dict)

    def test_serializer_rejects_arrival_before_departure(self):
        payload = {
            "route": self.route.pk,
            "vehicle": self.bus.pk,
            "departure_at": f"{self.today}T10:00:00Z",
            "arrival_at": f"{self.today}T08:00:00Z",
        }
        response = self.client.post("/api/v1/trips/", payload, format="json")
        self.assertEqual(response.status_code, 400)
        self.assertIn("arrival_at", response.data)

    def test_serializer_accepts_valid_same_day_arrival(self):
        payload = {
            "route": self.route.pk,
            "vehicle": self.bus.pk,
            "departure_at": f"{self.today}T08:00:00Z",
            "arrival_at": f"{self.today}T14:00:00Z",
            "note": "Trajet de test",
        }
        response = self.client.post("/api/v1/trips/", payload, format="json")
        self.assertEqual(response.status_code, 201)
        self.assertIsNotNone(response.data["arrival_at"])


class WeeklyScheduleTests(APITestCase):
    """Planning hebdomadaire par défaut et génération des trajets réels."""

    def setUp(self):
        self.context = build_operational_context()
        self.route = self.context["route"]
        self.reverse = Route.objects.create(origin=self.route.destination, destination=self.route.origin)
        self.bus = self.context["vehicle"]
        self.client.force_authenticate(self.context["admin"])

    def test_init_command_creates_exact_seven_day_schedule(self):
        # Lancer la commande init_weekly_schedule
        call_command("init_weekly_schedule", weeks=2)

        schedules = list(WeeklySchedule.objects.order_by("day_of_week"))
        self.assertEqual(len(schedules), 7)

        # Lundi (0) : 13h00 (Parakou -> Cotonou)
        mon = schedules[0]
        self.assertEqual(mon.day_of_week, WeeklySchedule.DayOfWeek.MONDAY)
        self.assertTrue(mon.is_active)
        self.assertEqual(mon.departure_time, time(13, 0))
        self.assertEqual(mon.route.origin.name, "Parakou")
        self.assertEqual(mon.route.destination.name, "Cotonou")

        # Mardi (1) : 08h00 (Cotonou -> Parakou)
        tue = schedules[1]
        self.assertEqual(tue.day_of_week, WeeklySchedule.DayOfWeek.TUESDAY)
        self.assertTrue(tue.is_active)
        self.assertEqual(tue.departure_time, time(8, 0))
        self.assertEqual(tue.route.origin.name, "Cotonou")
        self.assertEqual(tue.route.destination.name, "Parakou")

        # Mercredi (2) : Repos / Aucun trajet
        wed = schedules[2]
        self.assertEqual(wed.day_of_week, WeeklySchedule.DayOfWeek.WEDNESDAY)
        self.assertFalse(wed.is_active)
        self.assertIn("Repos", wed.notes)

        # Jeudi (3) : 08h00 (Parakou -> Cotonou)
        thu = schedules[3]
        self.assertTrue(thu.is_active)
        self.assertEqual(thu.departure_time, time(8, 0))

        # Vendredi (4) : 08h00 (Cotonou -> Parakou)
        fri = schedules[4]
        self.assertTrue(fri.is_active)
        self.assertEqual(fri.departure_time, time(8, 0))

        # Samedi (5) : 08h00 (Parakou -> Cotonou)
        sat = schedules[5]
        self.assertTrue(sat.is_active)
        self.assertEqual(sat.departure_time, time(8, 0))

        # Dimanche (6) : 13h00 (Cotonou -> Parakou)
        sun = schedules[6]
        self.assertTrue(sun.is_active)
        self.assertEqual(sun.departure_time, time(13, 0))
        self.assertEqual(sun.route.origin.name, "Cotonou")
        self.assertEqual(sun.route.destination.name, "Parakou")

    def test_api_list_and_patch_weekly_schedule(self):
        call_command("init_weekly_schedule", weeks=0)
        response = self.client.get("/api/v1/weekly-schedules/")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(len(response.data), 7)

        # Modifier l'horaire du lundi (13h -> 14h)
        monday = WeeklySchedule.objects.get(day_of_week=WeeklySchedule.DayOfWeek.MONDAY)
        patch_res = self.client.patch(
            f"/api/v1/weekly-schedules/{monday.id}/",
            {"departure_time": "14:00"},
            format="json",
        )
        self.assertEqual(patch_res.status_code, 200)
        monday.refresh_from_db()
        self.assertEqual(monday.departure_time, time(14, 0))

    def test_generate_trips_api_action(self):
        call_command("init_weekly_schedule", weeks=0)
        response = self.client.post("/api/v1/weekly-schedules/generate-trips/", {"weeks": 2}, format="json")
        self.assertEqual(response.status_code, 201)
        created_count = response.data["created"]
        self.assertGreater(created_count, 0)

        # Une 2e exécution ne crée pas de doublons
        second_res = self.client.post("/api/v1/weekly-schedules/generate-trips/", {"weeks": 2}, format="json")
        self.assertEqual(second_res.status_code, 201)
        self.assertEqual(second_res.data["created"], 0)

    def test_only_admin_can_modify_schedule(self):
        call_command("init_weekly_schedule", weeks=0)
        monday = WeeklySchedule.objects.get(day_of_week=WeeklySchedule.DayOfWeek.MONDAY)

        # Contrôleur / personnel non-admin refusé en modification (403)
        self.client.force_authenticate(self.context["controller"])
        res = self.client.patch(f"/api/v1/weekly-schedules/{monday.id}/", {"departure_time": "15:00"}, format="json")
        self.assertEqual(res.status_code, 403)

        # Mais le personnel peut consulter le planning (200)
        list_res = self.client.get("/api/v1/weekly-schedules/?all=true")
        self.assertEqual(list_res.status_code, 200)
