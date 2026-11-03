from datetime import datetime, time, timedelta
from django.utils import timezone
from rest_framework.test import APITestCase

from apps.core.models import (
    LineStop,
    Location,
    Route,
    RouteStop,
    SegmentFare,
    SegmentFareChange,
    Trip,
    Vehicle,
)
from apps.core.services import (
    build_homepage_banner,
    find_next_available_trip,
    generate_trip_seats,
)


class HomepageBannerAndNextAvailableTests(APITestCase):
    def setUp(self):
        # Villes
        self.parakou = Location.objects.create(name="Parakou TEST", active=True)
        self.save = Location.objects.create(name="Savè TEST", active=True)
        self.dassa = Location.objects.create(name="Dassa TEST", active=True)
        self.bohicon = Location.objects.create(name="Bohicon TEST", active=True)
        self.cotonou = Location.objects.create(name="Cotonou TEST", active=True)

        # LineStop
        self.ls_parakou = LineStop.objects.create(location=self.parakou, position=1)
        self.ls_save = LineStop.objects.create(location=self.save, position=2)
        self.ls_dassa = LineStop.objects.create(location=self.dassa, position=3)
        self.ls_bohicon = LineStop.objects.create(location=self.bohicon, position=4)
        self.ls_cotonou = LineStop.objects.create(location=self.cotonou, position=5)

        # Tarifs
        def _add_fare(start_ls, end_ls, amount):
            fare = SegmentFare.objects.create(start=start_ls, end=end_ls, amount=amount)
            SegmentFareChange.objects.create(fare=fare, old_amount=None, new_amount=amount)
            return fare

        _add_fare(self.ls_parakou, self.ls_cotonou, 7500)
        _add_fare(self.ls_save, self.ls_cotonou, 6500)
        _add_fare(self.ls_parakou, self.ls_save, 4500)

        # Véhicule
        self.vehicle = Vehicle.objects.create(
            category=Vehicle.Category.BUS,
            name="Yutong TEST",
            capacity=50,
            state=Vehicle.State.ACTIVE,
        )

        # Route 1 : Cotonou → Parakou (Montant)
        self.route_up = Route.objects.create(origin=self.cotonou, destination=self.parakou, active=True)
        for pos, (loc, offset) in enumerate(
            [(self.cotonou, 0), (self.bohicon, 45), (self.dassa, 120), (self.save, 210), (self.parakou, 360)],
            start=1,
        ):
            RouteStop.objects.create(route=self.route_up, location=loc, position=pos, offset_minutes=offset)

        # Route 2 : Parakou → Cotonou (Descendant)
        self.route_down = Route.objects.create(origin=self.parakou, destination=self.cotonou, active=True)
        for pos, (loc, offset) in enumerate(
            [(self.parakou, 0), (self.save, 150), (self.dassa, 240), (self.bohicon, 315), (self.cotonou, 360)],
            start=1,
        ):
            RouteStop.objects.create(route=self.route_down, location=loc, position=pos, offset_minutes=offset)

    def test_banner_single_trip_today_with_stops_and_tomorrow(self):
        """Cas normal : un trajet aujourd'hui avec escales actives et un trajet retour demain."""
        now = timezone.localtime()
        today = now.date()
        tomorrow = today + timedelta(days=1)

        dep_today = timezone.make_aware(datetime.combine(today, time(23, 45)))
        dep_tomorrow = timezone.make_aware(datetime.combine(tomorrow, time(8, 0)))

        t_today = Trip.objects.create(route=self.route_down, vehicle=self.vehicle, departure_at=dep_today)
        t_tomorrow = Trip.objects.create(route=self.route_up, vehicle=self.vehicle, departure_at=dep_tomorrow)
        generate_trip_seats(t_today)
        generate_trip_seats(t_tomorrow)

        banner = build_homepage_banner()
        self.assertTrue(banner["has_departure_today"])
        self.assertIn("Aujourd'hui, le bus va de Parakou TEST vers Cotonou TEST", banner["banner_text"])
        self.assertIn("Savè TEST, Dassa TEST, Bohicon TEST", banner["banner_text"])
        self.assertIn("Demain, il repart vers Parakou TEST", banner["banner_text"])

        # Test endpoint API
        res = self.client.get("/api/v1/client/trips/banner/")
        self.assertEqual(res.status_code, 200)
        self.assertEqual(res.json()["banner_text"], banner["banner_text"])

    def test_banner_rest_day_no_trip_today(self):
        """Cas repos : aucun départ aujourd'hui, prochain départ annoncé avec date et heure."""
        now = timezone.localtime()
        after_tomorrow = now.date() + timedelta(days=2)
        dep = timezone.make_aware(datetime.combine(after_tomorrow, time(8, 0)))
        t = Trip.objects.create(route=self.route_down, vehicle=self.vehicle, departure_at=dep)
        generate_trip_seats(t)

        banner = build_homepage_banner()
        self.assertFalse(banner["has_departure_today"])
        self.assertIn("Pas de départ aujourd'hui. Prochain départ :", banner["banner_text"])
        self.assertIn("Parakou TEST → Cotonou TEST", banner["banner_text"])

    def test_banner_trip_already_departed_today(self):
        """Cas départ déjà parti : le voyage d'aujourd'hui est passé, annonce du prochain départ."""
        now = timezone.localtime()
        today = now.date()
        # Voyage à 01:00 ce matin
        dep_past = timezone.make_aware(datetime.combine(today, time(1, 0)))
        dep_next = timezone.make_aware(datetime.combine(today + timedelta(days=2), time(8, 0)))

        t_past = Trip.objects.create(
            route=self.route_down, vehicle=self.vehicle, departure_at=dep_past, status=Trip.Status.IN_PROGRESS
        )
        t_next = Trip.objects.create(route=self.route_up, vehicle=self.vehicle, departure_at=dep_next)
        generate_trip_seats(t_past)
        generate_trip_seats(t_next)

        banner = build_homepage_banner()
        self.assertFalse(banner["has_departure_today"])
        self.assertIn("Le voyage d'aujourd'hui", banner["banner_text"])
        self.assertIn("est déjà parti. Prochain départ :", banner["banner_text"])

    def test_banner_two_trips_same_day(self):
        """Cas exceptionnel : deux départs le même jour."""
        now = timezone.localtime()
        today = now.date()
        dep1 = timezone.make_aware(datetime.combine(today, time(22, 0)))
        dep2 = timezone.make_aware(datetime.combine(today, time(23, 30)))

        t1 = Trip.objects.create(route=self.route_down, vehicle=self.vehicle, departure_at=dep1)
        t2 = Trip.objects.create(route=self.route_up, vehicle=self.vehicle, departure_at=dep2)
        generate_trip_seats(t1)
        generate_trip_seats(t2)

        banner = build_homepage_banner()
        self.assertTrue(banner["has_departure_today"])
        self.assertEqual(banner["today_trips_count"], 2)
        self.assertIn("Aujourd'hui, départs prévus :", banner["banner_text"])

    def test_next_available_trip_when_search_empty(self):
        """Recherche sans résultat : renvoie la prochaine date où le même tronçon est vendable."""
        now = timezone.localtime()
        next_day = now.date() + timedelta(days=3)
        dep = timezone.make_aware(datetime.combine(next_day, time(8, 0)))

        trip = Trip.objects.create(route=self.route_down, vehicle=self.vehicle, departure_at=dep)
        generate_trip_seats(trip)

        # Recherche sur un jour vide (ex: demain)
        empty_date = (now.date() + timedelta(days=1)).isoformat()
        response = self.client.get(
            f"/api/v1/client/trips/?origin={self.parakou.id}&destination={self.cotonou.id}&date={empty_date}"
        )
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertEqual(len(data["results"]), 0)
        self.assertIsNotNone(data["next_available"])
        self.assertEqual(data["next_available"]["trip_id"], trip.id)
        self.assertEqual(data["next_available"]["date"], next_day.isoformat())
        self.assertEqual(data["next_available"]["formatted_time"], "08:00")

    def test_arrival_at_hidden_when_no_offset_and_no_explicit_arrival(self):
        """L'heure d'arrivée est absente (None / null) quand aucun offset_minutes n'est renseigné."""
        loc1 = Location.objects.create(name="Ville X TEST", active=True)
        loc2 = Location.objects.create(name="Ville Y TEST", active=True)
        route_no_offset = Route.objects.create(origin=loc1, destination=loc2, active=True)
        RouteStop.objects.create(route=route_no_offset, location=loc1, position=1, offset_minutes=None)
        RouteStop.objects.create(route=route_no_offset, location=loc2, position=2, offset_minutes=None)

        now = timezone.now() + timedelta(days=1)
        t = Trip.objects.create(route=route_no_offset, vehicle=self.vehicle, departure_at=now, arrival_at=None)
        generate_trip_seats(t)

        res = self.client.get(f"/api/v1/client/trips/{t.id}/")
        self.assertEqual(res.status_code, 200)
        self.assertIsNone(res.json()["arrival_at"])

    def test_arrival_at_calculated_when_offset_minutes_present(self):
        """L'heure d'arrivée est calculée dynamiquement d'après RouteStop.offset_minutes du terminus."""
        now = timezone.now() + timedelta(days=1)
        t = Trip.objects.create(route=self.route_down, vehicle=self.vehicle, departure_at=now, arrival_at=None)
        generate_trip_seats(t)

        res = self.client.get(f"/api/v1/client/trips/{t.id}/")
        self.assertEqual(res.status_code, 200)
        expected_arrival = (now + timedelta(minutes=360)).isoformat().replace("+00:00", "Z")
        self.assertIsNotNone(res.json()["arrival_at"])
        # Vérifie que l'écart correspond exactement aux 360 minutes
        from django.utils.dateparse import parse_datetime
        dep_parsed = parse_datetime(res.json()["departure_at"])
        arr_parsed = parse_datetime(res.json()["arrival_at"])
        self.assertEqual(int((arr_parsed - dep_parsed).total_seconds() / 60), 360)

    def test_prochains_departs_returns_both_directions(self):
        """Prochains départs affiche tous les sens sans restriction."""
        now = timezone.now() + timedelta(days=1)
        t1 = Trip.objects.create(route=self.route_down, vehicle=self.vehicle, departure_at=now)
        t2 = Trip.objects.create(route=self.route_up, vehicle=self.vehicle, departure_at=now + timedelta(hours=4))
        generate_trip_seats(t1)
        generate_trip_seats(t2)

        res = self.client.get("/api/v1/client/trips/")
        self.assertEqual(res.status_code, 200)
        data = res.json()
        trips = data if isinstance(data, list) else data["results"]
        labels = [t["route_detail"]["label"] for t in trips]
        self.assertIn("Parakou TEST → Cotonou TEST", labels)
        self.assertIn("Cotonou TEST → Parakou TEST", labels)
