"""Villes, ordre de la ligne et tarifs créés ou retirés depuis /admin, avec journal."""
from io import StringIO

from django.core.management import call_command
from rest_framework.test import APITestCase

from apps.core.axis import axis_routes
from apps.core.models import LineChange, LineStop, Location, SegmentFare, SegmentFareChange, User
from apps.core.services import SegmentFareMissing, resolve_segment_fare

FARES = "/api/v1/segment-fares/"
LINE = "/api/v1/line/"
LOCATIONS = "/api/v1/locations/"


def place(name):
    return Location.objects.get(name=name)


class LineAdminTests(APITestCase):
    def setUp(self):
        call_command("load_segment_fares", stdout=StringIO())
        Location.objects.update(active=True)
        self.admin = User.objects.create_user(username="admin-test", password="TEST-pass-123", role=User.Role.ADMIN)
        self.client.force_authenticate(self.admin)

    def ids(self, names):
        return [place(name).pk for name in names]

    def test_reads_line_in_order(self):
        names = [stop["name"] for stop in self.client.get(LINE).json()["stops"]]
        self.assertEqual(names, ["Parakou", "Savè", "Glazoué", "Dassa", "Bohicon", "Cotonou"])

    def test_reorders_and_adds_a_city_with_log_and_routes(self):
        Location.objects.create(name="Ville TEST")
        order = ["Parakou", "Glazoué", "Savè", "Ville TEST", "Dassa", "Bohicon", "Cotonou"]
        response = self.client.put(LINE, {"location_ids": self.ids(order)}, format="json")
        self.assertEqual(response.status_code, 200, response.content)
        self.assertEqual([s["name"] for s in response.json()["stops"]], order)
        forward, backward = axis_routes()
        self.assertEqual([s.location.name for s in forward.stops.order_by("position")], order)
        self.assertEqual([s.location.name for s in backward.stops.order_by("position")], order[::-1])
        self.assertEqual(LineChange.objects.count(), 1)

    def test_terminus_cannot_change(self):
        order = ["Savè", "Parakou", "Glazoué", "Dassa", "Bohicon", "Cotonou"]
        response = self.client.put(LINE, {"location_ids": self.ids(order)}, format="json")
        self.assertEqual(response.status_code, 400)
        self.assertEqual(LineChange.objects.count(), 0)

    def test_removed_stop_loses_its_fares(self):
        order = ["Parakou", "Glazoué", "Dassa", "Bohicon", "Cotonou"]
        self.assertEqual(self.client.put(LINE, {"location_ids": self.ids(order)}, format="json").status_code, 200)
        self.assertGreater(LineStop.objects.get(location__name="Savè").position, 100)
        with self.assertRaises(SegmentFareMissing):
            resolve_segment_fare(place("Parakou"), place("Savè"))

    def test_creates_retires_and_restores_a_fare_with_log(self):
        response = self.client.post(
            FARES, {"origin_id": place("Dassa").pk, "destination_id": place("Glazoué").pk, "amount": 1500}, format="json"
        )
        self.assertEqual(response.status_code, 201, response.content)
        fare_id = response.json()["id"]
        self.assertEqual(resolve_segment_fare(place("Dassa"), place("Glazoué")).amount, 1500)
        again = self.client.post(
            FARES, {"origin_id": place("Glazoué").pk, "destination_id": place("Dassa").pk, "amount": 1000}, format="json"
        )
        self.assertEqual(again.status_code, 400)

        self.assertEqual(self.client.post(f"{FARES}{fare_id}/retire/").status_code, 200)
        with self.assertRaises(SegmentFareMissing):
            resolve_segment_fare(place("Dassa"), place("Glazoué"))
        self.assertEqual(self.client.post(f"{FARES}{fare_id}/restore/").status_code, 200)
        self.assertEqual(resolve_segment_fare(place("Glazoué"), place("Dassa")).amount, 1500)
        notes = list(SegmentFareChange.objects.filter(fare_id=fare_id).order_by("id").values_list("note", flat=True))
        self.assertEqual(notes, ["Tarif créé", "Tarif retiré", "Tarif rétabli"])
        self.assertEqual(SegmentFare.objects.filter(pk=fare_id).count(), 1)

    def test_fare_needs_two_line_stops(self):
        Location.objects.create(name="Hors ligne TEST")
        response = self.client.post(
            FARES, {"origin_id": place("Parakou").pk, "destination_id": place("Hors ligne TEST").pk, "amount": 900},
            format="json",
        )
        self.assertEqual(response.status_code, 400)

    def test_city_rename_is_logged_and_delete_refused(self):
        city = place("Savè")
        self.assertEqual(self.client.patch(f"{LOCATIONS}{city.pk}/", {"name": "Savè TEST"}, format="json").status_code, 200)
        self.assertIn("Savè → Savè TEST", LineChange.objects.get().detail)
        self.assertEqual(self.client.delete(f"{LOCATIONS}{city.pk}/").status_code, 405)

    def test_non_admin_is_refused(self):
        counter = User.objects.create_user(username="guichet-test", password="TEST-pass-123", role=User.Role.COUNTER)
        self.client.force_authenticate(counter)
        self.assertEqual(self.client.get(LINE).status_code, 403)
        self.assertEqual(self.client.post(FARES, {}, format="json").status_code, 403)
